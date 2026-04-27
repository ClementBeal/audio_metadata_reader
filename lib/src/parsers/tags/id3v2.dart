import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:charset/charset.dart';
import 'tag_parser.dart';

const utf8Decoder = Utf8Decoder();
const utf16Decoder = Utf16Decoder();
const latin1Decoder = Latin1Decoder();

class ID3v3Frame {
  final String id;
  final int size;
  final Uint8List flags;

  ID3v3Frame(this.id, this.size, this.flags);
}

///
/// Metadata frame defined in the ID3 tag
///
String getTextFromFrame(Uint8List information) {
  final encoding = information.first;

  switch (encoding) {
    case 0:
      final nullCharacterPosition = information.indexOf(0, 1);
      return latin1Decoder.convert(
          information,
          1,
          (nullCharacterPosition >= 0)
              ? nullCharacterPosition
              : information.length);

    case 1:
      int nullCharacterPosition = -1;
      for (int i = 1; i + 1 < information.length; i += 2) {
        if (information[i] == 0 && information[i + 1] == 0) {
          nullCharacterPosition = i;
          break;
        }
      }
      return utf16Decoder.decodeUtf16Le(information.sublist(
          1,
          (nullCharacterPosition >= 0)
              ? nullCharacterPosition
              : information.length));

    case 2:
      int nullCharacterPosition = 1;
      while (nullCharacterPosition < information.length) {
        if (information[nullCharacterPosition] == 0) {
          if (information[nullCharacterPosition + 1] == 0) break;
        }
        nullCharacterPosition++;
      }
      return utf16Decoder
          .decodeUtf16Le(information.sublist(1, nullCharacterPosition));

    case 3:
      final nullCharacterPosition = information.indexOf(0, 1);
      return utf8Decoder.convert(
          information,
          1,
          (nullCharacterPosition >= 0)
              ? nullCharacterPosition
              : information.length);
  }

  return "";
}

/// Custom metadata frame
/// Can be used my MusicBrainz for instance
class TXXXFrame {
  late final int encoding;
  late final String description;
  late final String information;

  TXXXFrame(Uint8List information) {
    int offset = 0;
    encoding = information[offset++];

    final descriptionData = <int>[];
    bool isUTF16 = encoding == 1 || encoding == 2;

    if (isUTF16) {
      while (!(information[offset] == 0 && information[offset + 1] == 0)) {
        descriptionData.add(information[offset]);
        descriptionData.add(information[offset + 1]);
        offset += 2;
      }

      // we pass the final zeros
      while (information[offset] == 0) {
        offset++;
      }
    } else {
      while (information[offset] != 0) {
        descriptionData.add(information[offset++]);
      }
    }

    int lastCharPosition = information.length - 1;

    // can be 00 for utf16 or 0 for other
    bool hasTerminalEmptyCharacter = information[lastCharPosition] == 0 &&
        information[lastCharPosition - 1] == 0;

    // we need to remove the empty character at the end
    // it's a single or double zero
    final length = information.length -
        offset -
        (hasTerminalEmptyCharacter
            ? isUTF16
                ? 2
                : 1
            : 0);
    final rest = information.buffer.asUint8List(offset, length);

    switch (encoding) {
      case 0:
        description = latin1Decoder.convert(descriptionData);

        this.information = latin1Decoder.convert(rest);
        break;
      case 1:
        description = utf16Decoder.decodeUtf16Le(descriptionData);

        this.information = utf16Decoder.decodeUtf16Le(rest);
        break;
      case 2:
        description = utf16Decoder.decodeUtf16Be(descriptionData);

        this.information = utf16Decoder.decodeUtf16Be(rest);
        break;
      case 3:
        description = utf8Decoder.convert(descriptionData);

        this.information = utf8Decoder.convert(rest);
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
class ID3v2Parser extends TagParser<Mp3Metadata> {
  final Mp3Metadata metadata = Mp3Metadata();
  late final Buffer buffer;

  static final _discRegex = RegExp(r"(\d+)/(\d+)");
  static final _trackRegex = RegExp(r"(\d+)/(\d+)");

  ID3v2Parser({fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  Mp3Metadata parse(RandomAccessFile reader) {
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

    int offset = 10;

    // extended header
    // useless
    //
    // > The extended header contains information
    // > that is not vital to the correct
    // > parsing of the tag information
    if (getBit(headerBytes[5], 6) == 1) {
      final extendedHeaderSize = getUint32(buffer.read(4));
      buffer.skip(extendedHeaderSize - 4);
    }

    while (offset < size) {
      final frame = getFrame(reader, majorVersion == 4);

      if (frame == null) {
        break;
      }

      // 10 -> frame header
      offset = offset + 10 + frame.size;
      processFrame(frame.id, frame.size);
    }

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
          } else {
            buffer.skip(size);
          }
        },
      "TALB" => () {
          final content = buffer.read(size);
          metadata.album = getTextFromFrame(content);
        },
      "TBPM" => () {
          final content = buffer.read(size);
          metadata.bpm = getTextFromFrame(content);
        },
      "TCOP" => () {
          final content = buffer.read(size);
          metadata.copyrightMessage = getTextFromFrame(content);
        },
      "TCON" => () {
          final content = buffer.read(size);
          metadata.contentType = getTextFromFrame(content);
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
          metadata.composer = getTextFromFrame(content);
        },
      "TDAT" => () {
          final content = buffer.read(size);
          metadata.date = getTextFromFrame(content);
        },
      "TDLY" => () {
          final content = buffer.read(size);
          metadata.playlistDelay = getTextFromFrame(content);
        },
      "TENC" => () {
          final content = buffer.read(size);
          metadata.encodedBy = getTextFromFrame(content);
        },
      "TFLT" => () {
          final content = buffer.read(size);
          metadata.fileType = getTextFromFrame(content);
        },
      "TIME" => () {
          final content = buffer.read(size);
          metadata.time = getTextFromFrame(content);
        },
      "TIT1" => () {
          final content = buffer.read(size);
          metadata.contentGroupDescription = getTextFromFrame(content);
        },
      "TIT2" => () {
          final content = buffer.read(size);
          metadata.songName = getTextFromFrame(content);
        },
      "TIT3" => () {
          final content = buffer.read(size);
          metadata.subtitle = getTextFromFrame(content);
        },
      "TKEY" => () {
          final content = buffer.read(size);
          metadata.initialKey = getTextFromFrame(content);
        },
      "TLAN" => () {
          final content = buffer.read(size);
          metadata.languages = getTextFromFrame(content);
        },
      "TLEN" => () {
          final content = buffer.read(size);
          final time = int.tryParse(getTextFromFrame(content));

          if (time != null) {
            if ((time / 1000) < 1) {
              metadata.duration = Duration(seconds: time);
            } else {
              metadata.duration = Duration(milliseconds: time);
            }
          }
        },
      "TMED" => () {
          final content = buffer.read(size);
          metadata.mediatype = getTextFromFrame(content);
        },
      "TOAL" => () {
          final content = buffer.read(size);
          metadata.originalAlbum = getTextFromFrame(content);
        },
      "TOFN" => () {
          final content = buffer.read(size);
          metadata.originalFilename = getTextFromFrame(content);
        },
      "TOLY" => () {
          final content = buffer.read(size);
          metadata.originalTextWriter = getTextFromFrame(content);
        },
      "TOPE" => () {
          final content = buffer.read(size);
          metadata.originalArtist = getTextFromFrame(content);
        },
      "TORY" => () {
          final content = buffer.read(size);
          metadata.originalReleaseYear = _parseYear(getTextFromFrame(content));
        },
      "TOWN" => () {
          final content = buffer.read(size);
          metadata.fileOwner = getTextFromFrame(content);
        },
      "TDRC" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(getTextFromFrame(content));
        },
      "TYER" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(getTextFromFrame(content));
        },
      "TRDA" => () {
          final content = buffer.read(size);
          metadata.year = _parseYear(getTextFromFrame(content));
        },
      "TPE1" => () {
          final content = buffer.read(size);
          metadata.leadPerformer = getTextFromFrame(content);
        },
      "TPE2" => () {
          final content = buffer.read(size);
          metadata.bandOrOrchestra = getTextFromFrame(content);
        },
      "TPE3" => () {
          final content = buffer.read(size);
          metadata.conductor = getTextFromFrame(content);
        },
      "TPE4" => () {
          final content = buffer.read(size);
          metadata.interpreted = getTextFromFrame(content);
        },
      "TEXT" => () {
          final content = buffer.read(size);
          metadata.textWriter = getTextFromFrame(content);
        },
      "TPOS" || "TPA" => () {
          final content = buffer.read(size);
          final value = getTextFromFrame(content);
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
          metadata.publisher = getTextFromFrame(content);
        },
      "TRCK" => () {
          final content = buffer.read(size);
          final trackInfo = getTextFromFrame(content);

          if (trackInfo.isEmpty) {
            return;
          }

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
          metadata.internetRadioStationName = getTextFromFrame(content);
        },
      "TRSO" => () {
          final content = buffer.read(size);
          metadata.internetRadioStationOwner = getTextFromFrame(content);
        },
      "TSIZ" => () {
          final content = buffer.read(size);
          metadata.size = getTextFromFrame(content);
        },
      "TSRC" => () {
          final content = buffer.read(size);
          metadata.isrc = getTextFromFrame(content);
        },
      "TXXX" => () {
          final content = buffer.read(size);
          final frame = TXXXFrame(content);
          metadata.customMetadata[frame.description] = frame.information;
        },
      "USLT" => () {
          final content = buffer.read(size);
          metadata.lyric = getUnsynchronisedLyric(content);
        },
      "TSSE" => () {
          final content = buffer.read(size);
          metadata.encoderSoftware = getTextFromFrame(content);
        },
      _ => () {
          buffer.skip(size);
        }
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
    int offset = 0;

    final reader = ByteData.sublistView(content);
    final encoding = reader.getUint8(offset++);

    final mimetype = [reader.getUint8(offset++)];

    while (mimetype.last != 0) {
      mimetype.add(reader.getUint8(offset));
      offset++;
    }
    mimetype.removeLast();

    final pictureType = reader.getUint8(offset);

    offset++;

    final description = [reader.getInt8(offset++)];

    while (description.last != 0) {
      description.add(reader.getInt8(offset++));
    }

    if (encoding == 1 || encoding == 2) {
      while (reader.getInt8(offset) == 0) {
        offset++;
      }
    }

    return Picture(
      reader.buffer.asUint8List(offset),
      String.fromCharCodes(mimetype),
      getPictureTypeEnum(pictureType),
    );
  }

  String getUnsynchronisedLyric(Uint8List content) {
    int offset = 1;

    final reader = ByteData.sublistView(content);
    final encoding = reader.getInt8(0);

    // skip language
    offset += 3;

    final description = [reader.getInt8(offset)];

    while (description.last != 0) {
      description.add(reader.getInt8(offset));
      offset++;
    }

    if (encoding == 1 || encoding == 2) {
      while (offset < reader.lengthInBytes && reader.getInt8(offset) == 0) {
        offset++;
      }
    }

    final rest = reader.buffer.asUint8List(offset);

    switch (encoding) {
      case 0:
        final nullCharacterPosition = rest.indexOf(0, 1);
        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return latin1Decoder.convert(informationBytes);
      case 1:
        if (encoding == 1 || encoding == 2) {
          // Check if rest length is sufficient and properly handle ending
          if (rest.length >= 2 &&
              rest[rest.length - 1] == 0 &&
              rest[rest.length - 2] == 0) {
            return utf16Decoder.decodeUtf16Le(rest, 0, rest.length - 2);
          }
          return utf16Decoder.decodeUtf16Le(rest);
        }
        return utf16Decoder.decodeUtf16Le(rest);
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
        return utf16Decoder.decodeUtf16Le(informationBytes);
      case 3:
        final nullCharacterPosition = rest.indexOf(0, 1);
        final informationBytes = rest.sublist(
            1, (nullCharacterPosition >= 0) ? nullCharacterPosition : null);
        return utf8Decoder.convert(informationBytes);
    }

    return "";
  }

  int? _parseYear(String year) {
    if (year.contains("-")) {
      return int.tryParse(year.split("-").first);
    } else if (year.contains("/")) {
      return int.tryParse(year.split("/").first);
    } else {
      return int.tryParse(year);
    }
  }
}
