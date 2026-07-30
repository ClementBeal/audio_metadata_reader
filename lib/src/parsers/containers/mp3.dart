import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/containers/ape.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v1.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

/// Container-level parser for MP3 files.
///
/// Protocol section: leading ID3v2 tags and the first MPEG audio frame.
///
/// Bytes: ID3v2 header 0..9
/// Layout:
/// ```text
/// 4944 33VV RRFF SSSS SSSS
/// ```
/// Meaning:
/// - `49 44 33`: the ASCII `ID3` tag marker.
/// - `VV`, `RR`: ID3v2 major and revision versions.
/// - `FF`: flags. In ID3v2.4, bit 4 declares a 10-byte footer.
/// - `SS SS SS SS`: 28-bit sync-safe tag size, big-endian; the high bit of
///   every byte is zero. This size excludes the 10-byte header and footer.
///
/// Bytes: MPEG audio frame header 0..3
/// Layout:
/// ```text
/// 11111111 111VVVLL BBBBSSPP CCCCCCCC
/// ```
/// Meaning:
/// - leading `1` bits: the 11-bit MPEG frame sync word;
/// - `VVV`, `LL`, `BBBB`, `SS`: MPEG version, layer, bitrate and sample-rate
///   indices used to derive audio properties.
///
/// Constraints:
/// - a leading ID3v2 tag is parsed for metadata; additional consecutive tags
///   are skipped because this parser has no metadata-merging policy for them;
/// - malformed additional tag sizes stop the skip and fall back to MPEG frame
///   resynchronisation, rather than seeking past the end of the file.
///
/// MP3 metadata is usually stored in ID3 tags, but finding those tags is a
/// responsibility of the MP3 container, not of the individual tag parsers:
/// - ID3v2, when present, starts at the beginning of the file.
/// - ID3v1, when present, occupies the last 128 bytes of the file.
///
/// The tag parsers receive the same [RandomAccessFile] positioned at the start
/// of the tag they must parse. This avoids loading the whole tag in memory,
/// which matters for large ID3v2 tags containing embedded pictures.
class MP3Parser extends TagParser<Mp3Metadata> {
  MP3Parser({super.fetchImage = false});

  @override
  Mp3Metadata parse(RandomAccessFile reader) {
    late final Mp3Metadata metadata;

    if (hasID3v2Tag(reader)) {
      final audioStartOffset = _getLeadingID3v2TotalSize(reader);
      reader.setPositionSync(0);
      metadata = ID3v2Parser(fetchImage: fetchImage).parse(reader);
      _parseAudioFrames(reader, metadata, audioStartOffset);
    } else if (hasID3v1Tag(reader)) {
      reader.setPositionSync(reader.lengthSync() - 128);
      metadata = ID3v1Parser(fetchImage: fetchImage).parse(reader);
      _parseAudioFrames(reader, metadata, 0);
    } else {
      // ID3 is optional. A valid MP3 may contain only MPEG audio frames, as do
      // files produced by some mobile recorders and media importers.
      metadata = Mp3Metadata();
      _parseAudioFrames(reader, metadata, 0);

      if (metadata.samplerate == null) {
        throw StateError("No MPEG audio frame found in this MP3 file");
      }
    }

    _mergeApeMetadata(reader, metadata);
    return metadata;
  }

  /// Merge an optional trailing APEv2 tag into the MP3 metadata.
  ///
  /// MP3 files in the wild can carry ID3v2 at the beginning and APEv2 at the
  /// end. ID3v2 is treated as the primary source for overlapping fields; APEv2
  /// fills missing values and contributes fields such as ReplayGain/pictures.
  void _mergeApeMetadata(
    RandomAccessFile reader,
    Mp3Metadata metadata,
  ) {
    if (!ApeParser.canUserParser(reader)) {
      return;
    }

    final ape = ApeParser(fetchImage: fetchImage).parse(reader);

    metadata.album ??= ape.album;
    metadata.leadPerformer ??= ape.artist;
    metadata.songName ??= ape.title;
    metadata.lyric ??= ape.lyric;
    metadata.languages ??= ape.language.firstOrNull;
    metadata.trackNumber ??= ape.trackNumber;
    metadata.trackTotal ??= ape.trackTotal;
    metadata.discNumber ??= ape.discNumber;
    metadata.totalDics ??= ape.discTotal;
    metadata.year ??= ape.date?.year;
    metadata.bitrate ??= ape.bitrate;
    metadata.samplerate ??= ape.sampleRate;
    metadata.duration ??= ape.duration;

    for (final genre in ape.genres) {
      if (!metadata.genres.contains(genre)) {
        metadata.genres.add(genre);
      }
    }

    metadata.pictures.addAll(ape.pictures);

    for (final entry in ape.unknowns.entries) {
      metadata.customMetadata.putIfAbsent(entry.key, () => entry.value);
    }
  }

  /// Returns true when this file has an ID3 tag that this MP3 parser can use.
  static bool canUserParser(RandomAccessFile reader) {
    return hasID3v2Tag(reader) ||
        hasID3v1Tag(reader) ||
        hasMpegAudioFrame(reader);
  }

  /// Returns true when the file starts with a valid MPEG audio frame. This is
  /// intentionally independent from ID3 detection: metadata tags are optional
  /// in an MP3 container.
  ///
  /// Keep this probe constant-cost. [readMetadata] calls every format detector
  /// in sequence, so reading a large prefix here would slow down unrelated
  /// files. The full bounded scan remains in [_findFirstMp3Frame], once this
  /// cheap probe has selected the MP3 parser.
  static bool hasMpegAudioFrame(RandomAccessFile reader) {
    final fileLength = reader.lengthSync();
    if (fileLength < 4) {
      return false;
    }

    reader.setPositionSync(0);
    final bytes = reader.readSync(4);
    final word =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

    return _isValidFrameHeader(word);
  }

  /// ID3v2 tags are identified by the "ID3" marker in the first 3 bytes.
  static bool hasID3v2Tag(RandomAccessFile reader) {
    if (reader.lengthSync() < 10) {
      return false;
    }

    reader.setPositionSync(0);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "ID3";
  }

  /// ID3v1 tags are identified by the "TAG" marker 128 bytes before EOF.
  static bool hasID3v1Tag(RandomAccessFile reader) {
    if (reader.lengthSync() < 128) {
      return false;
    }

    reader.setPositionSync(reader.lengthSync() - 128);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "TAG";
  }

  /// Returns the offset where MPEG audio begins after consecutive ID3v2 tags.
  ///
  /// Some tag editors prepend a replacement ID3v2 tag instead of replacing
  /// the old one. We parse the first tag as the metadata source, then jump
  /// across each following well-formed tag. This avoids treating an embedded
  /// image or text frame as a byte-by-byte MPEG resynchronisation region.
  int _getLeadingID3v2TotalSize(RandomAccessFile reader) {
    const id3v2HeaderSize = 10;
    const id3v2FooterSize = 10;
    final fileLength = reader.lengthSync();

    // [parse] reached this method only after checking the first three bytes
    // for `ID3`. Preserve the existing first-tag behavior even if the tag is
    // malformed; validation is only needed for optional following tags.
    reader.setPositionSync(0);
    final firstHeader = reader.readSync(id3v2HeaderSize);
    var offset = id3v2HeaderSize +
        _getID3v2TagSize(firstHeader) +
        (_hasID3v2Footer(firstHeader) ? id3v2FooterSize : 0);

    while (offset <= fileLength - id3v2HeaderSize) {
      reader.setPositionSync(offset);
      final header = reader.readSync(id3v2HeaderSize);

      if (!_isValidID3v2Header(header)) {
        break;
      }

      final tagSize = _getID3v2TagSize(header);
      final footerSize = _hasID3v2Footer(header) ? id3v2FooterSize : 0;
      final totalTagSize = id3v2HeaderSize + tagSize + footerSize;

      if (totalTagSize > fileLength - offset) {
        // Do not seek beyond EOF while looking for optional subsequent tags.
        break;
      }

      offset += totalTagSize;
    }

    return offset;
  }

  static bool _isValidID3v2Header(Uint8List header) {
    return header[0] == 0x49 &&
        header[1] == 0x44 &&
        header[2] == 0x33 &&
        header[6] & 0x80 == 0 &&
        header[7] & 0x80 == 0 &&
        header[8] & 0x80 == 0 &&
        header[9] & 0x80 == 0;
  }

  static int _getID3v2TagSize(Uint8List header) {
    return (header[9] & 0x7F) |
        ((header[8] & 0x7F) << 7) |
        ((header[7] & 0x7F) << 14) |
        ((header[6] & 0x7F) << 21);
  }

  static bool _hasID3v2Footer(Uint8List header) {
    // The footer-present flag only exists in ID3v2.4. It contributes a second
    // ten-byte structure after the tag payload and is excluded from tag size.
    return header[3] == 4 && (header[5] & 0x10) != 0;
  }

  /// Extract MPEG audio properties from the first valid frame.
  ///
  /// ID3 tags describe metadata, but bitrate, sample rate, and duration belong
  /// to the MP3 audio stream. We therefore do this work here, after the tag
  /// parser has filled the ID3 fields.
  void _parseAudioFrames(
    RandomAccessFile reader,
    Mp3Metadata metadata,
    int audioStartOffset,
  ) {
    final buffer = Buffer(randomAccessFile: reader);
    buffer.setPositionSync(audioStartOffset);

    final frame = _findFirstMp3Frame(buffer);

    if (frame == null) {
      return;
    }

    final mp3FrameHeader = frame.header;
    final mpegVersion = switch ((mp3FrameHeader[1] >> 3) & 0x3) {
      0x00 => 3,
      0x01 => -1,
      0x02 => 2,
      0x03 => 1,
      _ => -1
    };
    final mpegLayer = switch ((mp3FrameHeader[1] >> 1) & 0x3) {
      0 => -1,
      1 => 3,
      2 => 2,
      3 => 1,
      _ => -1,
    };

    final bitrateIndex = mp3FrameHeader[2] >> 4;
    // The sampling-rate index occupies bits 3..4 of the third header byte.
    // Parentheses are required here: without them Dart evaluates the shift
    // before the bitwise AND and turns index 1 (48 kHz) into index 0 (44.1 kHz).
    final samplerateIndex = (mp3FrameHeader[2] & 0x0C) >> 2;

    metadata.samplerate = _getSampleRate(mpegVersion, samplerateIndex);
    metadata.bitrate = _getBitrate(mpegVersion, mpegLayer, bitrateIndex);

    if (metadata.duration != null && metadata.duration != Duration.zero) {
      return;
    }

    // Xing is a VBR header commonly located shortly after the first frame.
    // We scan a bounded window to keep parsing cheap on large files.
    final possibleXingHeader = buffer.readAtMost(1500);
    final xingOffset = _findXingOffset(possibleXingHeader);

    if (xingOffset != null) {
      final xingFrameFlag = possibleXingHeader[xingOffset + 7] & 0x1;

      if (xingFrameFlag == 1) {
        final numberOfFrames = getUint32(
            possibleXingHeader.sublist(xingOffset + 8, xingOffset + 12));
        final samplesPerFrame = _getSamplePerFrame(mpegVersion, mpegLayer) ?? 0;
        final sampleRate = metadata.samplerate;

        if (sampleRate != null && sampleRate > 0 && samplesPerFrame > 0) {
          final totalSamples = numberOfFrames * samplesPerFrame;
          final durationInSeconds = totalSamples / sampleRate;
          final durationInMicroseconds = (durationInSeconds * 1000000).toInt();

          metadata.duration = Duration(microseconds: durationInMicroseconds);
        }
      }
    } else if (metadata.bitrate != null && metadata.bitrate! > 0) {
      final id3v1Size = hasID3v1Tag(reader) ? 128 : 0;
      final fileSizeWithoutMetadata =
          reader.lengthSync() - frame.offset - id3v1Size;
      final durationInSeconds =
          (8 * fileSizeWithoutMetadata) / metadata.bitrate!;
      final durationInMicroseconds = (durationInSeconds * 1000000).toInt();

      metadata.duration = Duration(microseconds: durationInMicroseconds);
    }
  }

  /// Search and return the first valid MPEG audio frame header.
  ///
  /// A frame starts with an 11-bit sync word. Some files contain runs of 0x00
  /// or 0xFF, so the candidate is validated against MPEG version/layer,
  /// bitrate, sample rate, and emphasis flags before being accepted.
  _Mp3Frame? _findFirstMp3Frame(Buffer buffer) {
    final frameHeader = buffer.readAtMost(4);

    while (frameHeader.length == 4) {
      if (frameHeader[0] == 0xFF) {
        final word = (frameHeader[0] << 24) |
            (frameHeader[1] << 16) |
            (frameHeader[2] << 8) |
            frameHeader[3];

        if (_isValidFrameHeader(word)) {
          return _Mp3Frame(
            Uint8List.fromList(frameHeader),
            buffer.fileCursor - 4,
          );
        }
      }

      final nextByte = buffer.readByteOrNull();
      if (nextByte == null) {
        break;
      }

      frameHeader[0] = frameHeader[1];
      frameHeader[1] = frameHeader[2];
      frameHeader[2] = frameHeader[3];
      frameHeader[3] = nextByte;
    }

    return null;
  }

  static bool _isValidFrameHeader(int word) {
    if ((word & 0xFFE00000) != 0xFFE00000) {
      return false;
    }

    return (word & 0x180000) != 0x080000 && // reserved version ID
        (word & 0x060000) != 0x000000 && // reserved layer
        (word & 0x00F000) != 0x000000 && // free bitrate
        (word & 0x00F000) != 0x00F000 && // bad bitrate
        (word & 0x000C00) != 0x000C00 && // reserved sampling rate
        (word & 0x000003) != 0x000002; // reserved emphasis
  }

  int? _findXingOffset(Uint8List bytes) {
    for (var i = 0; i < bytes.length - 11; i++) {
      if (bytes[i] == 0x58 &&
          bytes[i + 1] == 0x69 &&
          bytes[i + 2] == 0x6E &&
          bytes[i + 3] == 0x67) {
        return i;
      }
    }

    return null;
  }

  int? _getSampleRate(int mpegVersion, int sampleRateIndex) {
    if (mpegVersion == 1) {
      return switch (sampleRateIndex) {
        0 => 44100,
        1 => 48000,
        2 => 32000,
        _ => null,
      };
    }

    if (mpegVersion == 2) {
      return switch (sampleRateIndex) {
        0 => 22050,
        1 => 24000,
        2 => 16000,
        _ => null,
      };
    }

    if (mpegVersion == 3) {
      return switch (sampleRateIndex) {
        0 => 11025,
        1 => 12000,
        2 => 8000,
        _ => null,
      };
    }

    return null;
  }

  int? _getBitrate(int mpegVersion, int mpegLayer, int bitrateIndex) {
    if (mpegVersion == 1 && mpegLayer == 1) {
      return switch (bitrateIndex) {
        0 => null,
        1 => 32000,
        2 => 64000,
        3 => 96000,
        4 => 128000,
        5 => 160000,
        6 => 192000,
        7 => 224000,
        8 => 256000,
        9 => 288000,
        10 => 320000,
        11 => 352000,
        12 => 384000,
        13 => 416000,
        14 => 448000,
        _ => null,
      };
    }

    if (mpegVersion == 1 && mpegLayer == 2) {
      return switch (bitrateIndex) {
        0 => null,
        1 => 32000,
        2 => 48000,
        3 => 56000,
        4 => 64000,
        5 => 80000,
        6 => 96000,
        7 => 112000,
        8 => 128000,
        9 => 160000,
        10 => 192000,
        11 => 224000,
        12 => 256000,
        13 => 320000,
        14 => 384000,
        _ => null,
      };
    }

    if (mpegVersion == 1 && mpegLayer == 3) {
      return switch (bitrateIndex) {
        0 => null,
        1 => 32000,
        2 => 40000,
        3 => 48000,
        4 => 56000,
        5 => 64000,
        6 => 80000,
        7 => 96000,
        8 => 112000,
        9 => 128000,
        10 => 160000,
        11 => 192000,
        12 => 224000,
        13 => 256000,
        14 => 320000,
        _ => null,
      };
    }

    if (mpegVersion == 2 && mpegLayer == 1) {
      return switch (bitrateIndex) {
        0 => null,
        1 => 32000,
        2 => 48000,
        3 => 56000,
        4 => 64000,
        5 => 80000,
        6 => 96000,
        7 => 112000,
        8 => 128000,
        9 => 144000,
        10 => 160000,
        11 => 176000,
        12 => 192000,
        13 => 224000,
        14 => 256000,
        _ => null,
      };
    }

    if (mpegVersion == 2 && (mpegLayer == 2 || mpegLayer == 3)) {
      return switch (bitrateIndex) {
        0 => null,
        1 => 8000,
        2 => 16000,
        3 => 24000,
        4 => 32000,
        5 => 40000,
        6 => 48000,
        7 => 56000,
        8 => 64000,
        9 => 80000,
        10 => 96000,
        11 => 112000,
        12 => 128000,
        13 => 144000,
        14 => 160000,
        _ => null,
      };
    }

    return null;
  }

  int? _getSamplePerFrame(int mpegAudioVersion, int mpegLayer) {
    if (mpegAudioVersion == 1) {
      return switch (mpegLayer) {
        1 => 384,
        2 => 1152,
        3 => 1152,
        _ => null,
      };
    } else if (mpegAudioVersion == 2) {
      return switch (mpegLayer) {
        1 => 192,
        2 => 1152,
        3 => 576,
        _ => null,
      };
    }

    return null;
  }
}

class _Mp3Frame {
  final Uint8List header;
  final int offset;

  _Mp3Frame(this.header, this.offset);
}
