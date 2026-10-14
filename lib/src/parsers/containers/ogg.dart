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
      OggPage? page;
      int startGranule = pages.first.granulePosition;

      // An Opus stream may not start at granule 0 (RFC 7845, section 4.3):
      // its start is the first audio page granule minus the samples it holds.
      if (isOpus) {
        page = _parseUniquePage();
        if (page.headerType & 0x04 == 0) {
          startGranule = max(page.granulePosition - _opusPageSamples(page), 0);
        }
      }

      while (page?.headerType != 0x04) {
        page = _parseUniquePageHeader();
      }

      final int granuleRate = isOpus ? 48000 : m.sampleRate!;
      final int totalSamples =
          page!.granulePosition - startGranule - (isOpus ? opusPreSkip : 0);

      m.duration = Duration(
        microseconds: (max(totalSamples, 0) * 1000000 / granuleRate).round(),
      );
    }

    return m;
  }

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

  VorbisMetadata _parseVorbisComment(
    Uint8List page,
    int headerOffset,
    VorbisMetadata m,
  ) {
    final dataBuffer = List<int>.from(page.sublist(headerOffset));
    int offset = 0;

    final vendorLength = getUint32LE(dataBuffer.sublist(offset, offset + 4));
    offset += 4;
    offset += vendorLength;

    final userCommentListLength =
        getUint32LE(dataBuffer.sublist(offset, offset + 4));
    offset += 4;

    for (int i = 0; i < userCommentListLength; i++) {
      final commentLength = getUint32LE(dataBuffer.sublist(offset, offset + 4));
      offset += 4;

      while (dataBuffer.length - offset < commentLength) {
        dataBuffer.addAll(_parseUniquePage().data);
      }
      final commentData = dataBuffer.sublist(offset, offset + commentLength);
      offset += commentLength;
      parseVorbisComment(commentData, m, fetchImage: fetchImage);
    }

    return m;
  }

  /// Check if the OGG parser can be use for a specific file
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final capturePatternBytes = reader.readSync(4);
    final capturePattern = String.fromCharCodes(capturePatternBytes);

    return capturePattern == "OggS";
  }

  /// Parse a unique OGG page
  /// It means from the OggS magic word to the last segment
  OggPage _parseUniquePage() {
    // for the spec, see: https://wiki.xiph.org/Ogg
    List<int> data = []; //  contains data from previous (continuing) pages

    Uint8List headerData;
    try {
      headerData = buffer.read(27);
    } catch (e) {
      // Handle end of file gracefully (return what we have or throw an error)
      if (data.isNotEmpty) {
        return OggPage(
          data: Uint8List.fromList(data),
          granulePosition: 0, // Or handle this differently
          headerType: 0x04, // Treat as end of stream
          bitstreamSerialNumber: -1,
        );
      } else {
        // EOF reached
        rethrow;
      }
    }

    final oggs = headerData.sublist(0, 4);
    final version = headerData[4];
    final headerType = headerData[5];
    final granulePosition = getUint64LE(headerData.sublist(6, 14));
    final bitstreamSerialNumber = getUint32LE(headerData.sublist(14, 18));

    if (String.fromCharCodes(oggs) != 'OggS' || version != 0) {
      throw Exception('Not a valid ogg file!');
    }

    // define the total of segments in this page
    final totalSegments = headerData[26];
    final segsizes = buffer.read(totalSegments);
    List<int> pageData = []; // Data for the current page

    for (final segsize in segsizes) {
      pageData.addAll(buffer.read(segsize));
    }

    // Concatenate data from continuing pages if necessary

    return OggPage(
      data: Uint8List.fromList(pageData),
      granulePosition: granulePosition,
      headerType: headerType,
      bitstreamSerialNumber: bitstreamSerialNumber,
      segmentSizes: segsizes,
    );
  }

  /// Parse the header of an OGG page
  /// We also skip the content of the page to be synchronized
  OggPage _parseUniquePageHeader() {
    Uint8List headerData;

    headerData = buffer.read(27);

    final headerType = headerData[5];
    final granulePosition = getUint64LE(headerData.sublist(6, 14));
    final bitstreamSerialNumber = getUint32LE(headerData.sublist(14, 18));

    final totalSegments = headerData[26];
    final segsizes = buffer.read(totalSegments);
    int total = 0;

    for (final segsize in segsizes) {
      total += segsize;
    }

    buffer.skip(total);

    return OggPage(
      data: Uint8List(0),
      headerType: headerType,
      granulePosition: granulePosition,
      bitstreamSerialNumber: bitstreamSerialNumber,
    );
  }
}
