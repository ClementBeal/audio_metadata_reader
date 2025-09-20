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

    // if (metadata.duration == null || metadata.duration == Duration.zero) {
    if (true) {
      buffer.setPositionSync(size + 10);

      final mp3FrameHeader = _findFirstMp3Frame(buffer);

      if (mp3FrameHeader == null) {
        reader.closeSync();
        return metadata;
      }

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

      // arbitrary choice.  Usually the `Xing` header is located after ~30 bytes
      // then the header size is about ~150 bytes.
      final possibleXingHeader = buffer.readAtMost(1500);

      int i = 0;
      while (i < possibleXingHeader.length && possibleXingHeader[i] == 0) {
        i++;
      }

      if ((i < possibleXingHeader.length - 11) &&
          possibleXingHeader[i] == 0x58 &&
          possibleXingHeader[i + 1] == 0X69 &&
          possibleXingHeader[i + 2] == 0x6E &&
          possibleXingHeader[i + 3] == 0x67) {
        // it's a VBR file (Variable Bit Rate)
        final xingFrameFlag = possibleXingHeader[i + 7] & 0x1;

        if (xingFrameFlag == 1) {
          final numberOfFrames =
              getUint32(possibleXingHeader.sublist(i + 8, i + 12));
          final samplesPerFrame =
              _getSamplePerFrame(mpegVersion, mpegLayer) ?? 0;
          final sampleRate = metadata.samplerate;

          if (sampleRate != null && sampleRate > 0 && samplesPerFrame > 0) {
            final totalSamples = numberOfFrames * samplesPerFrame;
            final durationInSeconds = totalSamples / sampleRate;

            final durationInMicroseconds =
                (durationInSeconds * 1000000).toInt();
            metadata.duration = Duration(microseconds: durationInMicroseconds);
          }
        }
      } else {
        // it's a CBR file (Constant Bit Rate)
        if (metadata.bitrate != null && metadata.bitrate! > 0) {
          final fileSizeWithoutMetadata = reader.lengthSync() - size;
          final durationInSeconds =
              (8 * fileSizeWithoutMetadata) / metadata.bitrate!;

          // Convert to microseconds
          final durationInMicroseconds = (durationInSeconds * 1000000).toInt();
          metadata.duration = Duration(microseconds: durationInMicroseconds);
        }
      }
    }

    reader.closeSync();
    return metadata;
  }

  /// Search and return the first MP3 frame header.
  /// Returns null if none has been found.
  ///
  /// The MP3 frame has a magic word : 0xFFF or 0xFFE
  ///
  /// Sometimes the MP3 files contains blocks of 0x00 or 0xFF and relying on the magic word
  /// is not reliable anymore.
  ///
  /// To prevent false positives, we need to verify that the bytes after the potential
  /// valid word are correct. The MP3 specs specify several flags that must be set or not.
  ///
  /// Credit to [exiftool](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/MPEG.pm#L464)
  Uint8List? _findFirstMp3Frame(Buffer buffer) {
    Uint8List frameHeader = buffer.readAtMost(4);

    while (frameHeader.length == 4) {
      // Look for frame sync (0xFF followed by 3 bytes)
      if (frameHeader[0] == 0xFF) {
        int word = (frameHeader[0] << 24) |
            (frameHeader[1] << 16) |
            (frameHeader[2] << 8) |
            (frameHeader[3]);

        if ((word & 0xFFE00000) != 0xFFE00000) {
          frameHeader[0] = frameHeader[1];
          frameHeader[1] = frameHeader[2];
          frameHeader[2] = frameHeader[3];
          frameHeader[3] = buffer.read(1)[0];
          continue;
        }

        // Check for invalid MPEG version (01), layer (00), bitrate index (0000 or 1111),
        // reserved sampling frequency (11), reserved emphasis (10), and not Layer III if MP3
        if ((word & 0x180000) == 0x080000 || // reserved version ID
            (word & 0x060000) == 0x000000 || // reserved layer
            (word & 0x00F000) == 0x000000 || // free bitrate
            (word & 0x00F000) == 0x00F000 || // bad bitrate
            (word & 0x000C00) == 0x000C00 || // reserved sampling rate
            (word & 0x000003) == 0x000002) {
          frameHeader[0] = frameHeader[1];
          frameHeader[1] = frameHeader[2];
          frameHeader[2] = frameHeader[3];
          frameHeader[3] = buffer.read(1)[0];
          continue;
        }

        return frameHeader;
      }

      frameHeader[0] = frameHeader[1];
      frameHeader[1] = frameHeader[2];
      frameHeader[2] = frameHeader[3];
      frameHeader[3] = buffer.read(1)[0];
    }

    return null;
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
          metadata.fileOwner == getTextFromFrame(content);
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
  if (content.isEmpty) return "";

  int offset = 1; // encoding
  final reader = ByteData.sublistView(content);
  final encoding = reader.getInt8(0);

  // 跳过 language (3 bytes)
  offset += 3;

  // description 字节，以 0 结束
  while (offset < content.length && reader.getInt8(offset) != 0) {
    offset++;
  }
  offset++; // 跳过 description 的 null

  // 跳过可能的 padding 0
  while ((encoding == 1 || encoding == 2) && offset < content.length && reader.getInt8(offset) == 0) {
    offset++;
  }

  // 剩余就是歌词内容
  final rest = content.sublist(offset);

  switch (encoding) {
    case 0: // Latin1
      return latin1Decoder.convert(rest).trimRight();
    case 1: // UTF-16 LE
    case 2: // UTF-16 BE
      String text = utf16Decoder.decodeUtf16Le(rest, 0, rest.length);
      return text.replaceAll('\u0000', '').trimRight();
    case 3: // UTF-8
      return utf8Decoder.convert(rest).trimRight();
    default:
      return "";
  }
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

  int? _parseYear(String year) {
    if (year.contains("-")) {
      return int.tryParse(year.split("-").first);
    } else if (year.contains("/")) {
      return int.tryParse(year.split("/").first);
    } else {
      return int.tryParse(year);
    }
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
