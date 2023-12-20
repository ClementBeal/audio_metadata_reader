import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:charset/charset.dart';
import 'tag_parser.dart';

final bitrateTable = {
  0: null,
  1: 32,
  2: 40,
  3: 48,
  4: 56,
  5: 64,
  6: 80,
  7: 96,
  8: 112,
  9: 128,
  10: 160,
  11: 192,
  12: 224,
  13: 256,
  14: 320,
  15: null,
};

final samplerateTable = {
  0: 44100,
  1: 48000,
  2: 32000,
  3: null,
};

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

  ID3v2Parser({fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  Future<ParserTag> parse(RandomAccessFile reader) async {
    reader.setPositionSync(0);

    final headerBytes = reader.readSync(10);
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
      final frameContent = reader.readSync(frame.size);
      offset = offset + 10 + frame.size;

      try {
        processFrame(frame.id, frameContent);
      } catch (e) {
        rethrow;
      }
    }

    // if (metadata.duration == null || metadata.duration == Duration.zero) {
    reader.setPositionSync(size + 10);

    List<int> mp3FrameHeader = [...reader.readSync(4)];

    // CHECK : may have performance issues
    while (mp3FrameHeader.first != 0xff) {
      mp3FrameHeader.add(reader.readByteSync());
      mp3FrameHeader.removeAt(0);
    }

    final bitrateCode = mp3FrameHeader[2] >> 4;
    final samplerateCode = mp3FrameHeader[2] & 12 >> 2;

    metadata.bitrate = bitrateTable[bitrateCode];
    metadata.samplerate = samplerateTable[samplerateCode];

    if (metadata.bitrate != null && metadata.samplerate != null) {
      final frameLength =
          144 * metadata.bitrate! * 1000 / metadata.samplerate! + 1;
      final fileSizeWithoutMetadata = reader.lengthSync() - size;
      metadata.duration = Duration(
          seconds: (fileSizeWithoutMetadata ~/ frameLength * 0.026).ceil());
    }

    reader.closeSync();
    return metadata;
  }

  void processFrame(String frameId, Uint8List content) {
    final handlers = switch (frameId) {
      "APIC" => () {
          if (fetchImage) {
            final picture = getPicture(content);
            metadata.pictures.add(picture);
          }
        },
      "TALB" => () {
          metadata.album = TextFrame(content).information;
        },
      "TBPM" => () {
          metadata.bpm = TextFrame(content).information;
        },
      "TCOP" => () {
          metadata.copyrightMessage = TextFrame(content).information;
        },
      "TCON" => () {
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
          metadata.composer = TextFrame(content).information;
        },
      "TDAT" => () {
          metadata.date = TextFrame(content).information;
        },
      "TDLY" => () {
          metadata.playlistDelay = TextFrame(content).information;
        },
      "TENC" => () {
          metadata.encodedBy = TextFrame(content).information;
        },
      "TFLT" => () {
          metadata.fileType = TextFrame(content).information;
        },
      "TCMP" => () {
          // TextFrame(content).information;
          //print("Encoding by: " + TextFrame(frame.content).information);
        },
      "TIME" => () {
          metadata.time = TextFrame(content).information;
        },
      "TIPL" => () {
          // TextFrame(content).information;
        },
      "TIT1" => () {
          metadata.contentGroupDescription = TextFrame(content).information;
        },
      "TIT2" => () {
          metadata.songName = TextFrame(content).information;
        },
      "TIT3" => () {
          metadata.subtitle = TextFrame(content).information;
        },
      "TKEY" => () {
          metadata.initialKey = TextFrame(content).information;
        },
      "TLAN" => () {
          metadata.languages = TextFrame(content).information;
        },
      "TLEN" => () {
          final time = int.parse(TextFrame(content).information);

          if ((time / 1000) < 1) {
            metadata.duration = Duration(seconds: time);
          } else {
            metadata.duration = Duration(milliseconds: time);
          }
        },
      "TMED" => () {
          metadata.mediatype = TextFrame(content).information;
        },
      "TOAL" => () {
          metadata.originalAlbum = TextFrame(content).information;
        },
      "TOFN" => () {
          metadata.originalFilename = TextFrame(content).information;
        },
      "TOLY" => () {
          metadata.originalTextWriter = TextFrame(content).information;
        },
      "TOPE" => () {
          metadata.originalArtist = TextFrame(content).information;
        },
      "TORY" => () {
          metadata.originalReleaseYear =
              _parseYear(TextFrame(content).information);
        },
      "TDRL" => () {
          // tag.originalArtist == TextFrame(content).information;
        },
      "TOWN" => () {
          metadata.fileOwner == TextFrame(content).information;
        },
      "TDRC" => () {
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TYER" => () {
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TRDA" => () {
          metadata.year = _parseYear(TextFrame(content).information);
        },
      "TPE1" => () {
          metadata.leadPerformer = TextFrame(content).information;
        },
      "TPE2" => () {
          metadata.bandOrOrchestra = TextFrame(content).information;
        },
      "TPE3" => () {
          metadata.conductor = TextFrame(content).information;
        },
      "TPE4" => () {
          metadata.interpreted = TextFrame(content).information;
        },
      "TEXT" => () {
          metadata.textWriter = TextFrame(content).information;
        },
      "TPOS" || "TPA" => () {
          final value = TextFrame(content).information;
          metadata.partOfSet = value;

          if (RegExp(r"\d+/\d+").hasMatch(value)) {
            metadata.discNumber = int.parse(value.split("/").first);
          } else {
            metadata.discNumber = int.tryParse(value);
          }
        },
      "TPUB" => () {
          metadata.publisher = TextFrame(content).information;
        },
      "TRCK" => () {
          final trackInfo = TextFrame(content).information;
          if (trackInfo.contains("/")) {
            metadata.trackNumber ??= int.tryParse(trackInfo.split("/").first);
            metadata.trackTotal ??= int.tryParse(trackInfo.split("/").last);
          } else {
            metadata.trackNumber = int.tryParse(trackInfo);
          }
        },
      "TRSN" => () {
          metadata.internetRadioStationName = TextFrame(content).information;
        },
      "TRSO" => () {
          metadata.internetRadioStationOwner = TextFrame(content).information;
        },
      "TSIZ" => () {
          metadata.size = TextFrame(content).information;
        },
      "TSRC" => () {
          metadata.isrc = TextFrame(content).information;
        },
      "TXXX" => () {
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
          // TextFrame(content).information;
          //print("Recording date: " + getUnsynchronisedLyric(frame.content));
        },
      "TSSE" => () {
          metadata.encoderSoftware = TextFrame(content).information;
        },
      "TSOC" => () {},
      "TSO2" => () {},
      _ => () {}
    };

    handlers.call();
  }

  ID3v3Frame? getFrame(RandomAccessFile reader, bool isV4) {
    final headerBytes = reader.readSync(10);

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
    // offset++;
    // print(String.fromCharCodes(mimetype));

    final pictureType = reader.getUint8(offset);
    // print(pictureType);

    offset++;

    final description = [reader.getUint8(offset)];
    offset += 1;
    while (description.last != 0) {
      final a = reader.getUint8(offset);
      // print(a);
      description.add(a);
      offset++;
    }

    // print(description);
    // print(String.fromCharCodes(description));
    // print(reader.buffer.asUint8List(offset).sublist(0, 10));
// 14
    // print(offset);
    return Picture(reader.buffer.asUint8List(offset),
        String.fromCharCodes(mimetype), getPictureTypeEnum(pictureType));
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

    return switch (encoding) {
      0 => const Latin1Decoder().convert(rest),
      1 => utf16.decode(rest),
      2 => utf16.decode(rest),
      3 || _ => const Utf8Decoder().convert(rest),
    };
  }

  ///
  /// To detect if this file can be parsed with this parser, the first 3 bytes
  /// must be equal to `ID3`
  ///
  static Future<bool> canUserParser(RandomAccessFile reader) async {
    reader.setPositionSync(0);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "ID3";
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
}
