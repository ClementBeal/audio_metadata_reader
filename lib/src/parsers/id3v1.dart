import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

class ID3v1Parser extends TagParser {
  final Mp3Metadata metadata = Mp3Metadata();

  ID3v1Parser({super.fetchImage = false});

  ///  Extract the part text between the [start] and the [end]
  ///  until we reach a "\x00" character
  String _extract(Uint8List tagData, int start, int end) {
    int i = start;

    while (i < end && tagData[i] != 0) {
      i++;
    }

    if (tagData[i] == 0) {
      return utf8.decode(tagData.sublist(start, i));
    }

    return latin1.decode(tagData.sublist(start, end));
  }

  @override
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(reader.lengthSync() - 128);

    final tagData = reader.readSync(128);
    metadata.songName = _extract(tagData, 3, 33);
    metadata.leadPerformer = _extract(tagData, 33, 63);
    metadata.album = _extract(tagData, 63, 93);
    metadata.year = getUint32(tagData.sublist(93, 97));
    metadata.year = metadata.year == 0 ? null : metadata.year;
    metadata.comments = [
      Comment("", _extract(tagData, 97, 127)),
    ];
    metadata.genres = [""];

    // metadata.genres =  [tagData[127]];

    final buffer = Buffer(randomAccessFile: reader);
    buffer.setPositionSync(0);
    // List<int> mp3FrameHeader = [...buffer.read(4)];
    Uint8List mp3FrameHeader = Uint8List(4);
    mp3FrameHeader[0] = buffer.read(1)[0];

    // CHECK : may have performance issues
    while (mp3FrameHeader.first != 0xff) {
      mp3FrameHeader[0] = buffer.read(1)[0];
    }

    mp3FrameHeader[1] = buffer.read(1)[0];
    mp3FrameHeader[2] = buffer.read(1)[0];
    mp3FrameHeader[3] = buffer.read(1)[0];

    final mpegVersion = (mp3FrameHeader[1] >> 3) & 0x3;
    final mpegLayer = (mp3FrameHeader[1] >> 1) & 3;

    final bitrateIndex = mp3FrameHeader[2] >> 4;
    final samplerateIndex = mp3FrameHeader[2] & 12 >> 0x3;

    metadata.samplerate = _getSampleRate(mpegVersion, samplerateIndex);

    // arbitrary choice.  Usually the `Xing` header is located after ~30 bytes
    // then the header size is about ~150 bytes
    final possibleXingHeader = buffer.read(400);

    int i = 0;
    while (possibleXingHeader[i] == 0) {
      i++;
    }

    if (possibleXingHeader[i] == 0x58 &&
        possibleXingHeader[i + 1] == 0X69 &&
        possibleXingHeader[i + 2] == 0x6E &&
        possibleXingHeader[i + 3] == 0x67) {
      // it's a VBR file (Variable Bit Rate)
      final xingFrameFlag = possibleXingHeader[i + 7] & 0x1;
      // final xingBytesFlag = possibleXingHeader[7] >> 1 & 0x1;
      // final xingTOCFlag = possibleXingHeader[7] >> 2 & 0x1;
      // final xingVBRScaleFlag = possibleXingHeader[7] >> 3 & 0x1;

      if (xingFrameFlag == 1) {
        final numberOfFrames =
            getUint32(possibleXingHeader.sublist(i + 8, i + 12));
        metadata.duration = Duration(
            seconds: numberOfFrames *
                (_getSamplePerFrame(mpegVersion, mpegLayer) ?? 0) ~/
                metadata.samplerate!);
      }
    } else {
      // it's a CBR file (Constant Bit Rate)
      metadata.bitrate = _getBitrate(mpegVersion, mpegLayer, bitrateIndex);

      if (metadata.bitrate != null) {
        final fileSizeWithoutMetadata = reader.lengthSync() - 128;
        metadata.duration = Duration(
            seconds: (8 * fileSizeWithoutMetadata / metadata.bitrate!).round());
      }
    }

    reader.closeSync();
    return metadata;
  }

  /// To detect if this file can be parsed with this parser,
  /// We have to check the 128 last bytes
  /// And if the first 3 are "TAG", it's ID3v1
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(reader.lengthSync() - 128);

    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "TAG";
  }

  int? _getSampleRate(int mpegVersion, int sampleRateIndex) {
    if (mpegVersion == 3) {
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

    if (mpegVersion == 1) {
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
    if (mpegVersion == 3 && mpegLayer == 3) {
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

    if (mpegVersion == 3 && mpegLayer == 2) {
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

    if (mpegVersion == 3 && mpegLayer == 1) {
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
    if (mpegVersion != 3 && mpegLayer == 3) {
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
    if (mpegVersion != 3) {
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
    if (mpegAudioVersion == 3) {
      return switch (mpegLayer) {
        3 => 384,
        2 => 1152,
        1 => 1152,
        _ => null,
      };
    } else if (mpegAudioVersion == 2) {
      return switch (mpegLayer) {
        3 => 192,
        2 => 1152,
        1 => 576,
        _ => null,
      };
    }

    return null;
  }
}
