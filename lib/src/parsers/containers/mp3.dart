import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v1.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

/// Container-level parser for MP3 files.
///
/// MP3 metadata is usually stored in ID3 tags, but finding those tags is a
/// responsibility of the MP3 container, not of the individual tag parsers:
/// - ID3v2, when present, starts at the beginning of the file.
/// - ID3v1, when present, occupies the last 128 bytes of the file.
///
/// The tag parsers receive the same [RandomAccessFile] positioned at the start
/// of the tag they must parse. This avoids loading the whole tag in memory,
/// which matters for large ID3v2 tags containing embedded pictures.
class MP3Parser extends TagParser {
  MP3Parser({super.fetchImage = false});

  @override
  ParserTag parse(RandomAccessFile reader) {
    try {
      if (hasID3v2Tag(reader)) {
        final audioStartOffset = _getID3v2TotalSize(reader);
        reader.setPositionSync(0);
        final metadata =
            ID3v2Parser(fetchImage: fetchImage).parse(reader) as Mp3Metadata;
        _parseAudioFrames(reader, metadata, audioStartOffset);
        return metadata;
      }

      if (hasID3v1Tag(reader)) {
        reader.setPositionSync(reader.lengthSync() - 128);
        final metadata =
            ID3v1Parser(fetchImage: fetchImage).parse(reader) as Mp3Metadata;
        _parseAudioFrames(reader, metadata, 0);
        return metadata;
      }

      throw StateError("No ID3 tag found in this MP3 file");
    } finally {
      reader.closeSync();
    }
  }

  /// Returns true when this file has an ID3 tag that this MP3 parser can use.
  static bool canUserParser(RandomAccessFile reader) {
    return hasID3v2Tag(reader) || hasID3v1Tag(reader);
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

  /// Returns the total byte size of the ID3v2 tag, including its 10-byte
  /// header. The size stored in ID3v2 is sync-safe and excludes that header.
  int _getID3v2TotalSize(RandomAccessFile reader) {
    reader.setPositionSync(0);
    final headerBytes = reader.readSync(10);
    final sizeBytes = headerBytes.sublist(6);

    final tagSize = (sizeBytes[3] & 0x7F) |
        ((sizeBytes[2] & 0x7F) << 7) |
        ((sizeBytes[1] & 0x7F) << 14) |
        ((sizeBytes[0] & 0x7F) << 21);

    return 10 + tagSize;
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
    final samplerateIndex = mp3FrameHeader[2] & 12 >> 0x3;

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

      if (buffer.remainingBytes == 0) {
        break;
      }

      frameHeader[0] = frameHeader[1];
      frameHeader[1] = frameHeader[2];
      frameHeader[2] = frameHeader[3];
      frameHeader[3] = buffer.read(1)[0];
    }

    return null;
  }

  bool _isValidFrameHeader(int word) {
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
