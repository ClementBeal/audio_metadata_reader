import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:charset/charset.dart';
import 'tag_parser.dart';

class ID3v3Frame {
  final String id;
  final int size;
  final Uint8List flags;

  ID3v3Frame(this.id, this.size, this.flags);
}

///
/// Metadata frame defined in the ID3 tag
///
class TextFrame {
  late final int encoding;
  late final String information;

  TextFrame(Uint8List information) {
    encoding = information.first;

    switch (encoding) {
      case 0:
        final nullCharacterPosition = information.indexOf(0, 1);
        final informationBytes = information.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        this.information = const Latin1Decoder().convert(informationBytes);
        break;
      case 1:
        int nullCharacterPosition = -1;
        int i = 1;
        while (i + 1 < information.length) {
          if (information[i] == 0 && information[i + 1] == 0) {
            nullCharacterPosition = i;
          }
          i += 2;
        }

        final informationBytes = information.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        this.information = const Utf16Decoder().decodeUtf16Le(informationBytes);
        break;
      case 2:
        int nullCharacterPosition = 1;
        bool zeroFound = false;
        while (nullCharacterPosition < information.length) {
          if (information[nullCharacterPosition] == 0) {
            if (zeroFound) {
              break;
            }
            zeroFound = true;
          }
          nullCharacterPosition++;
        }

        final informationBytes = information.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        this.information = const Utf16Decoder().decodeUtf16Le(informationBytes);
        break;
      case 3:
        final nullCharacterPosition = information.indexOf(0, 1);
        final informationBytes = information.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        this.information = const Utf8Decoder().convert(informationBytes);
        break;
    }
  }
}

///
/// Custom metadata frame
/// Can be used my MusicBrainz for instance
///
class TXXXFrame {
  late final int encoding;
  late final String description;
  late final String information;

  TXXXFrame(Uint8List information) {
    encoding = information.first;

    final nullCharacterPositionDescription = information.indexOf(0, 1);
    final informationBytesDescription = information.sublist(
        1,
        (nullCharacterPositionDescription >= 0)
            ? nullCharacterPositionDescription
            : null);

    switch (encoding) {
      case 0:
        description =
            const Latin1Decoder().convert(informationBytesDescription);

        this.information = const Latin1Decoder()
            .convert(information.sublist(nullCharacterPositionDescription));
        break;
      case 1:
        description =
            const Utf16Decoder().decodeUtf16Le(informationBytesDescription);

        this.information = const Utf16Decoder().decodeUtf16Le(
            information.sublist(nullCharacterPositionDescription));
        break;
      case 2:
        description =
            const Utf16Decoder().decodeUtf16Le(informationBytesDescription);

        this.information = const Utf16Decoder().decodeUtf16Le(
            information.sublist(nullCharacterPositionDescription));
        break;
      case 3:
        description = const Utf8Decoder().convert(informationBytesDescription);

        this.information = const Utf8Decoder()
            .convert(information.sublist(nullCharacterPositionDescription));
        break;
    }
  }
}

///
/// Parser for the ID3 tags
///
///
/// https://teslabs.com/openplayer/docs/docs/specs/id3v2.3.0%20-%20ID3.org.pdf
///
class ID3v2Parser extends TagParser {
  final Mp3Metadata metadata = Mp3Metadata();
  late final Buffer buffer;

  static final _discRegex = RegExp(r"(\d+)/(\d+)");
  static final _trackRegex = RegExp(r"(\d+)/(\d+)");

  ID3v2Parser({fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(0);
    buffer = Buffer(randomAccessFile: reader);

    final headerBytes = buffer.read(10);
    final majorVersion = headerBytes[3];

    if (majorVersion == 1) {
      return metadata;
    }

    var sizeBytes = headerBytes.sublist(6);

    // size of the ID3 tag minus id3 header size
    int size = (sizeBytes[3] & 0x7F) |
        ((sizeBytes[2] & 0x7F) << 7) |
        ((sizeBytes[1] & 0x7F) << 14) |
        ((sizeBytes[0] & 0x7F) << 21);

    var offset = 10;

    while (offset < size) {
      final frame = getFrame(reader, majorVersion == 4);

      if (frame == null) {
        break;
      }

      offset = offset + 10 + frame.size;

      try {
        processFrame(frame.id, frame.size);
      } catch (e) {
        rethrow;
      }
    }

    if (metadata.duration == null || metadata.duration == Duration.zero) {
      buffer.setPositionSync(size + 10);

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
      final possibleXingHeader = buffer.read(1500);

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
          final fileSizeWithoutMetadata = reader.lengthSync() - size;
          metadata.duration = Duration(
              seconds:
                  (8 * fileSizeWithoutMetadata / metadata.bitrate!).round());
        }
      }
    }

    reader.closeSync();
    return metadata;
  }

  /// Process a frame.
  ///
  /// If the frame ID is not defined in the id3vX specs, then its content is dropped.
  void processFrame(String frameId, int size) {
    // why do we duplicate the content in every block?
    // it's because the biggest thing to get in the cover
    // sometimes, we don't want to read so we have to read the content
    // at the very last time
    final handlers = switch (frameId) {
      "APIC" => () {
          if (fetchImage) {
            final content = buffer.read(size);
            final picture = getPicture(content);
            metadata.pictures.add(picture);
          }
        },
      "TALB" => () {
          final content = buffer.read(size);
          metadata.album = TextFrame(content).information;
        },
      "TBPM" => () {
          final content = buffer.read(size);
          metadata.bpm = TextFrame(content).information;
        },
      "TCOP" => () {
          final content = buffer.read(size);
          metadata.copyrightMessage = TextFrame(content).information;
        },
      "TCON" => () {
          final content = buffer.read(size);
          metadata.contentType = TextFrame(content).information;
          final regex = RegExp(r"(\d+).*");
          final containRegex = RegExp(r";|/|\||,");

          if (metadata.contentType!.contains(containRegex)) {
            metadata.genres.addAll(metadata.contentType!
                .split(containRegex)
                .map((e) => e.trim())
                .toList());
          } else if (regex.hasMatch(metadata.contentType!)) {
            metadata.genres.add(id3Genres[
                    regex.allMatches(metadata.contentType!).first.group(0)!] ??
                "");
          } else if (metadata.contentType!.isNotEmpty) {
            metadata.genres.add(metadata.contentType!);
          }
        },
      "TCOM" => () {
          final content = buffer.read(size);
          metadata.composer = TextFrame(content).information;
        },
      "TDAT" => () {
          final content = buffer.read(size);
          metadata.date = TextFrame(content).information;
        },
      "TDLY" => () {
          final content = buffer.read(size);
          metadata.playlistDelay = TextFrame(content).information;
        },
      "TENC" => () {
          final content = buffer.read(size);
          metadata.encodedBy = TextFrame(content).information;
        },
      "TFLT" => () {
          final content = buffer.read(size);
          metadata.fileType = TextFrame(content).information;
        },
      "TCMP" => () {
          // TextFrame(content).information;
          //print("Encoding by: " + TextFrame(frame.content).information);
        },
      "TIME" => () {
          final content = buffer.read(size);
          metadata.time = TextFrame(content).information;
        },
      "TIPL" => () {
          // TextFrame(content).information;
        },
      "TIT1" => () {
          final content = buffer.read(size);
          metadata.contentGroupDescription = TextFrame(content).information;
        },
      "TIT2" => () {
          final content = buffer.read(size);
          metadata.songName = TextFrame(content).information;
        },
      "TIT3" => () {
          final content = buffer.read(size);
          metadata.subtitle = TextFrame(content).information;
        },
      "TKEY" => () {
          final content = buffer.read(size);
          metadata.initialKey = TextFrame(content).information;
        },
      "TLAN" => () {
          final content = buffer.read(size);
          metadata.languages = TextFrame(content).information;
        },
      "TLEN" => () {
          final content = buffer.read(size);
          final time = int.parse(TextFrame(content).information);

          if ((time / 1000) < 1) {
            metadata.duration = Duration(seconds: time);
          } else {
            metadata.duration = Duration(milliseconds: time);
          }
        },
      "TMED" => () {
          final content = buffer.read(size);
          metadata.mediatype = TextFrame(content).information;
        },
      "TOAL" => () {
          final content = buffer.read(size);
          metadata.originalAlbum = TextFrame(content).information;
        },
      "TOFN" => () {
          final content = buffer.read(size);
          metadata.originalFilename = TextFrame(content).information;
        },
      "TOLY" => () {
          final content = buffer.read(size);
          metadata.originalTextWriter = TextFrame(content).information;
        },
      "TOPE" => () {
          final content = buffer.read(size);
          metadata.originalArtist = TextFrame(content).information;
        },
      "TORY" => () {
          final content = buffer.read(size);
          metadata.originalReleaseYear =
              _parseYear(TextFrame(content).information);
        },
      "TDRL" => () {
          // tag.originalArtist == TextFrame(content).information;
        },
      "TOWN" => () {
          final content = buffer.read(size);
          metadata.fileOwner == TextFrame(content).information;
        },
      "TDRC" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TYER" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TRDA" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TPE1" => () {
          final content = buffer.read(size);
          metadata.leadPerformer = TextFrame(content).information;
        },
      "TPE2" => () {
          final content = buffer.read(size);
          metadata.bandOrOrchestra = TextFrame(content).information;
        },
      "TPE3" => () {
          final content = buffer.read(size);
          metadata.conductor = TextFrame(content).information;
        },
      "TPE4" => () {
          final content = buffer.read(size);
          metadata.interpreted = TextFrame(content).information;
        },
      "TEXT" => () {
          final content = buffer.read(size);
          metadata.textWriter = TextFrame(content).information;
        },
      "TPOS" || "TPA" => () {
          final content = buffer.read(size);
          final value = TextFrame(content).information;
          metadata.partOfSet = value;

          final match = _discRegex.firstMatch(value);

          if (match != null) {
            metadata.discNumber = int.parse(match.group(1)!);
            metadata.totalDics = int.parse(match.group(2)!);
          } else {
            metadata.discNumber = int.tryParse(value);
          }
        },
      "TPUB" => () {
          final content = buffer.read(size);
          metadata.publisher = TextFrame(content).information;
        },
      "TRCK" => () {
          final content = buffer.read(size);
          final trackInfo = TextFrame(content).information;

          final match = _trackRegex.firstMatch(trackInfo);

          if (match != null) {
            metadata.trackNumber = int.parse(match.group(1)!);
            metadata.trackTotal = int.parse(match.group(2)!);
          } else {
            metadata.trackNumber = int.parse(trackInfo);
          }
        },
      "TRSN" => () {
          final content = buffer.read(size);
          metadata.internetRadioStationName = TextFrame(content).information;
        },
      "TRSO" => () {
          final content = buffer.read(size);
          metadata.internetRadioStationOwner = TextFrame(content).information;
        },
      "TSIZ" => () {
          final content = buffer.read(size);
          metadata.size = TextFrame(content).information;
        },
      "TSRC" => () {
          final content = buffer.read(size);
          metadata.isrc = TextFrame(content).information;
        },
      "TXXX" => () {
          final content = buffer.read(size);
          final frame = TXXXFrame(content);
          metadata.customMetadata[frame.description] = frame.information;
        },
      "PRIV" => () {
          // TextFrame(content).information;
          //print("PRIV: " + String.fromCharCodes(frame.content));
        },
      "WCOM" => () {
          // TextFrame(content).information;
          //print("WCOM (commercial informtin): " +
          // String.fromCharCodes(frame.content));
        },
      "COMM" => () {
          // TextFrame(content).information;

          //print("COMM: " + getComments(frame.content));
        },
      "RGAD" => () {
          // TextFrame(content).information;
          //print("Replay gain: " + TextFrame(frame.content).information);
        },
      "USLT" => () {
          final content = buffer.read(size);
          metadata.lyric = getUnsynchronisedLyric(content);
          // TextFrame(content).information;
          //print("Recording date: " + getUnsynchronisedLyric(frame.content));
        },
      "TSSE" => () {
          final content = buffer.read(size);
          metadata.encoderSoftware = TextFrame(content).information;
        },
      "TSOC" => () {},
      "TSO2" => () {},
      _ => () {}
    };

    handlers.call();
  }

  ID3v3Frame? getFrame(RandomAccessFile reader, bool isV4) {
    final headerBytes = buffer.read(10);

    if (headerBytes.every((element) => element == 0)) return null;

    int size;

    // the id3 v4 ignore the first bit of every byte from the size
    if (isV4) {
      size = (headerBytes[7] & 0xFF) |
          ((headerBytes[6] & 0xFF) << 7) |
          ((headerBytes[5] & 0xFF) << 14) |
          ((headerBytes[4] & 0xFF) << 21);
    } else {
      size = headerBytes[7] +
          (headerBytes[6] << 8) +
          (headerBytes[5] << 16) +
          (headerBytes[4] << 24);
    }

    final flags = headerBytes.sublist(8);
    final id = String.fromCharCodes(headerBytes.sublist(0, 4));

    return ID3v3Frame(
      id,
      size,
      flags,
    );
  }

  Picture getPicture(Uint8List content) {
    var offset = 1;

    final reader = ByteData.sublistView(content);

    final mimetype = [reader.getUint8(offset++)];

    while (mimetype.last != 0) {
      mimetype.add(reader.getUint8(offset));
      offset++;
    }
    mimetype.removeLast();

    final pictureType = reader.getUint8(offset);

    offset++;

    final description = [reader.getUint8(offset)];
    offset += 1;

    while (description.last != 0) {
      final a = reader.getUint8(offset);
      description.add(a);
      offset++;
    }

    return Picture(
      reader.buffer.asUint8List(offset),
      String.fromCharCodes(mimetype),
      getPictureTypeEnum(pictureType),
    );
  }

  String getUnsynchronisedLyric(Uint8List content) {
    var offset = 1;

    final reader = ByteData.sublistView(content);
    final encoding = reader.getInt8(0);

    [
      reader.getInt8(offset++),
      reader.getInt8(offset++),
      reader.getInt8(offset++),
    ]; // language

    final description = [reader.getInt8(offset)];

    while (description.last != 0) {
      description.add(reader.getInt8(offset));
      offset++;
    }

    final rest = reader.buffer.asUint8List(offset);

    switch (encoding) {
      case 0:
        final nullCharacterPosition = rest.indexOf(0, 1);
        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return const Latin1Decoder().convert(informationBytes);
      case 1:
        int nullCharacterPosition = -1;
        int i = 1;
        while (i + 1 < rest.length) {
          if (rest[i] == 0 && rest[i + 1] == 0) {
            nullCharacterPosition = i;
          }
          i += 2;
        }

        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return const Utf16Decoder().decodeUtf16Le(informationBytes);

      case 2:
        int nullCharacterPosition = 1;
        bool zeroFound = false;
        while (nullCharacterPosition < rest.length) {
          if (rest[nullCharacterPosition] == 0) {
            if (zeroFound) {
              break;
            }
            zeroFound = true;
          }
          nullCharacterPosition++;
        }

        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return const Utf16Decoder().decodeUtf16Le(informationBytes);
      case 3:
        final nullCharacterPosition = rest.indexOf(0, 1);
        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return const Utf8Decoder().convert(informationBytes);
    }

    return "";
  }

  ///
  /// To detect if this file can be parsed with this parser, the first 3 bytes
  /// must be equal to `ID3`
  ///
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "ID3";
  }

  static bool isID3v1(RandomAccessFile reader) {
    reader.setPositionSync(reader.lengthSync() - 128);

    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "TAG";
  }

  int _parseYear(String year) {
    if (year.contains("-")) {
      return int.parse(year.split("-").first);
    } else if (year.contains("/")) {
      return int.parse(year.split("/").first);
    } else {
      return int.parse(year);
    }
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
