import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

/// Parsed content and header information for a single OGG page.
class OggPage {
  /// Concatenated page payload bytes.
  final Uint8List data;

  /// OGG header type flag byte.
  final int headerType;

  /// Absolute granule position carried by the page header.
  final int granulePosition;

  /// Stream serial number this page belongs to.
  final int bitstreamSerialNumber;

  /// Size of each segment of [data], as listed in the page segment table.
  final List<int> segmentSizes;

  /// Build an OGG page structure.
  OggPage({
    required this.data,
    required this.headerType,
    required this.granulePosition,
    required this.bitstreamSerialNumber,
    this.segmentSizes = const <int>[],
  });
}

// The parser for an OGG file
//
// The metadata are using the Vorbis format (like flac)
//
// OGG : https://datatracker.ietf.org/doc/pdf/rfc7845.pdf
// vorbis : http://web.mit.edu/cfox/share/doc/libvorbis-1.0/vorbis-spec-ref.html
class OGGParser extends TagParser<VorbisMetadata> {
  /// Create an OGG parser.
  OGGParser({required super.fetchImage});

  /// Reader helper bound to the current file.
  late final Buffer buffer;

  @override
  VorbisMetadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    buffer = Buffer(randomAccessFile: reader);

    // first page : contains samplerate and bitrate
    // second page : contains the metadata
    // it may not contains all the metadata so we would have to get them later
    final pages = [
      _parseUniquePage(),
      _parseUniquePage(),
    ];

    VorbisMetadata m = VorbisMetadata();
    bool isOpus = false;
    int opusPreSkip = 0;

    for (final page in pages) {
      final content = page.data;

      if (String.fromCharCodes(content.sublist(0, 8)) == "OpusHead") {
        isOpus = true;
        opusPreSkip = content[10] | (content[11] << 8);
        m.sampleRate = getUint32LE(content.sublist(12, 16));
        m.bitrate = getUint32LE(content.sublist(13, 17));
      } else if (String.fromCharCodes(content.sublist(0, 8)) == "OpusTags") {
        _parseVorbisComment(content, 8, m);
      } else if (String.fromCharCodes(content.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x03vorbis"
      {
        _parseVorbisComment(content, 7, m);
      } else if (String.fromCharCodes(content.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x01vorbis"
      {
        m.sampleRate = getUint32LE(content.sublist(12, 16));
        m.bitrate = getUint32LE(content.sublist(20, 24));
      }
    }

    // The granule position of the last page is the total number of samples.
    // Opus always counts them at 48 kHz (the OpusHead sample rate is only the
    // original input rate) and the first `pre-skip` samples must be dropped.
    // This always replaces a duration read from a `LENGTH` comment.
    if (m.sampleRate != null) {
      final int serial = pages.first.bitstreamSerialNumber;
      int startGranule = pages.first.granulePosition;
      int? lastGranule;

      // An Opus stream may not start at granule 0 (RFC 7845, section 4.3):
      // its start is the first audio page granule minus the samples it holds.
      if (isOpus) {
        final OggPage page = _parseUniquePage();
        if (page.headerType & 0x04 == 0) {
          startGranule = max(page.granulePosition - _opusPageSamples(page), 0);
        } else {
          lastGranule = page.granulePosition;
        }
      }

      lastGranule ??=
          _lastGranule(reader, serial) ?? _walkToLastGranule(serial);

      final int granuleRate = isOpus ? 48000 : m.sampleRate!;
      final int totalSamples = (lastGranule ?? startGranule) -
          startGranule -
          (isOpus ? opusPreSkip : 0);

      m.duration = Duration(
        microseconds: (max(totalSamples, 0) * 1000000 / granuleRate).round(),
      );
    }

    return m;
  }

  /// Size of the file tail searched for the last page.
  ///
  /// An Ogg page holds at most 27 + 255 + 255 * 255 = 65,307 bytes, so a
  /// complete last page always fits in this window.
  static const int _tailSize = 65536;

  /// Granule position of the last complete page of stream [serial], read
  /// from the last [_tailSize] bytes of the file.
  ///
  /// Returns `null` when the tail holds no such page (for instance when it is
  /// followed by a lot of non-Ogg data); the caller then walks the pages.
  /// The reader position is restored so that [buffer] stays consistent.
  int? _lastGranule(RandomAccessFile reader, int serial) {
    final int savedPosition = reader.positionSync();
    try {
      final int length = reader.lengthSync();
      final int start = max(0, length - _tailSize);
      reader.setPositionSync(start);
      final Uint8List tail = reader.readSync(length - start);

      for (int i = tail.length - 27; i >= 0; i--) {
        if (tail[i] != 0x4F ||
            tail[i + 1] != 0x67 ||
            tail[i + 2] != 0x67 ||
            tail[i + 3] != 0x53 ||
            tail[i + 4] != 0x00) {
          continue;
        }
        if (_readUint32LE(tail, i + 14) != serial) {
          continue;
        }

        // A false "OggS" match inside audio data rarely describes a page
        // that ends inside the file.
        final int segmentCount = tail[i + 26];
        final int bodyStart = i + 27 + segmentCount;
        if (bodyStart > tail.length) {
          continue;
        }
        int bodySize = 0;
        for (int k = i + 27; k < bodyStart; k++) {
          bodySize += tail[k];
        }
        if (bodyStart + bodySize > tail.length) {
          continue;
        }

        // A granule of -1 means that no packet ends on this page.
        if (_isNoGranule(tail, i + 6)) {
          continue;
        }
        return getUint64LE(Uint8List.sublistView(tail, i + 6, i + 14));
      }
      return null;
    } finally {
      reader.setPositionSync(savedPosition);
    }
  }

  /// Granule position of the last complete page of stream [serial], found by
  /// walking every page from the current position.
  ///
  /// Stops at the end-of-stream page, at the end of the file or at data that
  /// is not an Ogg page. Returns `null` when no page carries a granule.
  int? _walkToLastGranule(int serial) {
    final int length = buffer.randomAccessFile.lengthSync();
    int? lastGranule;

    while (buffer.fileCursor + 27 <= length) {
      final Uint8List header = buffer.read(27);
      if (header[0] != 0x4F ||
          header[1] != 0x67 ||
          header[2] != 0x67 ||
          header[3] != 0x53 ||
          header[4] != 0x00) {
        break;
      }
      final int segmentCount = header[26];
      if (buffer.fileCursor + segmentCount > length) {
        break;
      }
      final Uint8List segmentSizes = buffer.read(segmentCount);
      int bodySize = 0;
      for (final int size in segmentSizes) {
        bodySize += size;
      }
      if (buffer.fileCursor + bodySize > length) {
        break;
      }
      buffer.skip(bodySize);

      if (_readUint32LE(header, 14) == serial && !_isNoGranule(header, 6)) {
        lastGranule = getUint64LE(Uint8List.sublistView(header, 6, 14));
      }
      if (header[5] & 0x04 != 0) {
        break;
      }
    }

    return lastGranule;
  }

  static bool _isNoGranule(Uint8List bytes, int offset) {
    for (int k = offset; k < offset + 8; k++) {
      if (bytes[k] != 0xFF) {
        return false;
      }
    }
    return true;
  }

  static int _readUint32LE(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  /// Number of 48 kHz samples in the Opus packets completed on [page].
  ///
  /// A packet ends on the first segment smaller than 255 bytes.
  int _opusPageSamples(OggPage page) {
    int samples = 0;
    int packetStart = 0;
    int packetLength = 0;

    for (final int segmentSize in page.segmentSizes) {
      packetLength += segmentSize;
      if (segmentSize < 255) {
        if (packetLength > 0) {
          samples += _opusPacketSamples(
              page.data.sublist(packetStart, packetStart + packetLength));
        }
        packetStart += packetLength;
        packetLength = 0;
      }
    }

    return samples;
  }

  /// Number of 48 kHz samples in an Opus packet, read from its TOC byte
  /// (RFC 6716, section 3.1).
  int _opusPacketSamples(Uint8List packet) {
    final int config = packet[0] >> 3;
    final int frameSamples;
    if (config < 12) {
      // SILK-only: 10, 20, 40 or 60 ms.
      frameSamples = const <int>[480, 960, 1920, 2880][config % 4];
    } else if (config < 16) {
      // Hybrid: 10 or 20 ms.
      frameSamples = const <int>[480, 960][config % 2];
    } else {
      // CELT-only: 2.5, 5, 10 or 20 ms.
      frameSamples = const <int>[120, 240, 480, 960][config % 4];
    }

    final int frameCountCode = packet[0] & 0x03;
    final int frameCount;
    if (frameCountCode == 0) {
      frameCount = 1;
    } else if (frameCountCode < 3) {
      frameCount = 2;
    } else {
      frameCount = packet.length > 1 ? packet[1] & 0x3F : 0;
    }

    return frameSamples * frameCount;
  }

  /// Parse the comment packet that starts [headerOffset] bytes into [page].
  ///
  /// A packet larger than a page (typically one holding cover art) continues
  /// on the following pages, which are read on demand.
  VorbisMetadata _parseVorbisComment(
    Uint8List page,
    int headerOffset,
    VorbisMetadata m,
  ) {
    Uint8List data = Uint8List.sublistView(page, headerOffset);
    int offset = 0;

    // Make sure that [size] bytes are available from [offset].
    void ensure(int size) {
      int available = data.length - offset;
      if (available >= size) {
        return;
      }
      final BytesBuilder builder = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(data, offset));
      while (available < size) {
        final Uint8List next = _parseUniquePage().data;
        builder.add(next);
        available += next.length;
      }
      data = builder.takeBytes();
      offset = 0;
    }

    int readLength() {
      ensure(4);
      final int value = _readUint32LE(data, offset);
      offset += 4;
      return value;
    }

    final int vendorLength = readLength();
    ensure(vendorLength);
    offset += vendorLength;

    final int userCommentListLength = readLength();

    for (int i = 0; i < userCommentListLength; i++) {
      final int commentLength = readLength();

      // Cover art that is not wanted is skipped page by page instead of
      // being gathered in memory.
      if (!fetchImage &&
          data.length - offset < commentLength &&
          _startsWithPictureKey(data, offset)) {
        int remaining = commentLength - (data.length - offset);
        while (true) {
          final _OggPageHeader header = _readPageHeader();
          if (header.bodySize <= remaining) {
            buffer.skip(header.bodySize);
            remaining -= header.bodySize;
            if (remaining == 0) {
              data = Uint8List(0);
              offset = 0;
              break;
            }
          } else {
            data = buffer.read(header.bodySize);
            offset = remaining;
            break;
          }
        }
        continue;
      }

      ensure(commentLength);
      final Uint8List commentData =
          Uint8List.sublistView(data, offset, offset + commentLength);
      offset += commentLength;
      parseVorbisComment(commentData, m, fetchImage: fetchImage);
    }

    return m;
  }

  static const List<int> _pictureKey = <int>[
    0x4D, 0x45, 0x54, 0x41, 0x44, 0x41, 0x54, 0x41, 0x5F, // METADATA_
    0x42, 0x4C, 0x4F, 0x43, 0x4B, 0x5F, // BLOCK_
    0x50, 0x49, 0x43, 0x54, 0x55, 0x52, 0x45, 0x3D, // PICTURE=
  ];

  /// Whether the comment at [offset] is a METADATA_BLOCK_PICTURE (ASCII,
  /// compared without case).
  static bool _startsWithPictureKey(Uint8List data, int offset) {
    if (data.length - offset < _pictureKey.length) {
      return false;
    }
    for (int k = 0; k < _pictureKey.length; k++) {
      int byte = data[offset + k];
      if (byte >= 0x61 && byte <= 0x7A) {
        byte -= 0x20;
      }
      if (byte != _pictureKey[k]) {
        return false;
      }
    }
    return true;
  }

  /// Check if the OGG parser can be use for a specific file
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final capturePatternBytes = reader.readSync(4);
    final capturePattern = String.fromCharCodes(capturePatternBytes);

    return capturePattern == "OggS";
  }

  /// Read the header and segment table of the next page.
  _OggPageHeader _readPageHeader() {
    // for the spec, see: https://wiki.xiph.org/Ogg
    final Uint8List headerData = buffer.read(27);

    if (headerData[0] != 0x4F ||
        headerData[1] != 0x67 ||
        headerData[2] != 0x67 ||
        headerData[3] != 0x53 ||
        headerData[4] != 0x00) {
      throw Exception('Not a valid ogg file!');
    }

    final Uint8List segmentSizes = buffer.read(headerData[26]);
    int bodySize = 0;
    for (final int size in segmentSizes) {
      bodySize += size;
    }

    return _OggPageHeader(headerData, segmentSizes, bodySize);
  }

  /// Parse a unique OGG page
  /// It means from the OggS magic word to the last segment
  OggPage _parseUniquePage() {
    final _OggPageHeader header = _readPageHeader();
    final Uint8List headerData = header.bytes;

    return OggPage(
      data: buffer.read(header.bodySize),
      granulePosition: getUint64LE(Uint8List.sublistView(headerData, 6, 14)),
      headerType: headerData[5],
      bitstreamSerialNumber: _readUint32LE(headerData, 14),
      segmentSizes: header.segmentSizes,
    );
  }
}

/// Header bytes, segment table and body size of an OGG page.
class _OggPageHeader {
  final Uint8List bytes;
  final Uint8List segmentSizes;
  final int bodySize;

  _OggPageHeader(this.bytes, this.segmentSizes, this.bodySize);
}
