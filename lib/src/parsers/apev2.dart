import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

class Apev2Parser extends TagParser {
  final ApeMetadata metadata = ApeMetadata();
  Apev2Parser({super.fetchImage = false});
  @override
  ParserTag parse(RandomAccessFile reader) {
    final fileSize = reader.lengthSync();
    // final lastModified = reader.lastModifiedSync();

    // Read file header (first 76 bytes, sufficient for APE header)
    final headerBytes = reader.readSync(76);
    final header = _parseApeHeader(headerBytes, fileSize);
    // Read file tail to locate APEv2 tag
    // reader.setPositionSync(0);
    const tailSize = 1024 * 128; // Read last 128KB
    final readSize = fileSize < tailSize ? fileSize : tailSize;
    reader.setPositionSync(fileSize - readSize);
    final tagBytes = reader.readSync(readSize);
    final tagOffset = _findApeTagOffset(tagBytes);
    Map<String, dynamic> tag = {};
    if (tagOffset != -1) {
      // Parse APEv2 tag if found
      tag = _parseApeTag(tagBytes, tagOffset);
    }
    final fileMD5 = tagBytes.sublist(tagOffset + 36, tagOffset + 52);

    metadata.title = tag['title'];
    metadata.artist = tag['artist'];
    metadata.album = tag['album'];
    metadata.genres = tag['genre'] != null ? [tag['genre']] : [];
    metadata.duration = header['duration'];
    metadata.year = _parseYear(tag['year']);
    metadata.size = fileSize;
    metadata.bitrate = header['bitrate'] != null ? header['bitrate'] * 1000 : null;
    metadata.samplerate = header['sampleRate'];
    metadata.version = header['version'];
    metadata.totalDics = _parseInt(tag['disc']);
    metadata.trackNumber = _parseTrack(tag['track']);
    metadata.trackTotal = _parseTotal(tag['track']);
    metadata.discNumber = _parseDisc(tag['discnumber']);
    metadata.lyric = tag['unsyncedlyrics'];
    metadata.languages = tag['language'];
    metadata.pictures = [];

    ///
    metadata.comment = tag['comment'];
    // metadata.lastModified= lastModified;
    metadata.fileMD5 = uint8ListToHexString(fileMD5);

    if (fetchImage) {
      metadata.pictures = getPictures(tag);
    }
    return metadata;
  }

  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);
    final bytes = reader.readSync(76);
    final bd = ByteData.sublistView(bytes);
    final id = utf8.decode(bytes.sublist(0, 4));
    if (id != 'MAC ') return false;
    final version = bd.getUint32(4, Endian.little);
    if (version < 3980) return false;
    return true;
  }

  /// Parses the APEv2 tag
  static Map<String, dynamic> _parseApeTag(Uint8List bytes, int offset) {
    final map = <String, dynamic>{};

    if (offset + 32 > bytes.length) {
      throw FormatException('APEv2 header is too short.');
    }

    final itemCount = ByteData.sublistView(bytes, offset + 12, offset + 16).getUint32(0, Endian.little);
    int pos = offset + 32;

    for (int i = 0; i < itemCount && pos + 8 <= bytes.length; i++) {
      final valueSize = ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.little);
      final keyEnd = bytes.indexOf(0x00, pos + 8);
      if (keyEnd == -1 || keyEnd >= bytes.length) break;
      if (bytes.sublist(pos + 8, keyEnd).length < 3) break;

      final key = utf8.decode(bytes.sublist(pos + 8, keyEnd), allowMalformed: true).toLowerCase();
      final valueStart = keyEnd + 1;
      final valueEnd = valueStart + valueSize;
      if (valueEnd > bytes.length) break;

      if (key.startsWith('cover art')) {
        final nullIndex = bytes.indexOf(0x00, valueStart);
        final imageDataStart = (nullIndex != -1) ? nullIndex + 1 : valueStart;
        map[key] = bytes.sublist(imageDataStart, valueEnd);
      } else {
        try {
          map[key] = utf8.decode(bytes.sublist(valueStart, valueEnd), allowMalformed: true);
        } catch (e) {
          map[key] = '';
        }
      }
      pos = valueEnd;
    }
    return map;
  }

  /// Finds the offset of the APEv2 tag
  static int _findApeTagOffset(Uint8List bytes) {
    const signature = 'APETAGEX';
    for (int i = bytes.length - 160; i >= 0; i--) {
      if (i + 8 <= bytes.length && utf8.decode(bytes.sublist(i, i + 8), allowMalformed: true) == signature) {
        return i;
      }
    }
    return -1;
  }

  /// Parses the APE header
  static Map _parseApeHeader(Uint8List bytes, int fileSize) {
    final bd = ByteData.sublistView(bytes);
    final version = bd.getUint32(4, Endian.little);
    final blocksPerFrame = bd.getUint32(56, Endian.little);
    final totalFrames = bd.getUint32(64, Endian.little);
    final bitsPerSample = bd.getUint16(68, Endian.little);
    final channels = bd.getUint16(70, Endian.little);
    final sampleRate = bd.getUint32(72, Endian.little);

    final totalSamples = totalFrames * blocksPerFrame;
    final duration = totalSamples / sampleRate;
    final bitrate = (fileSize * 8) ~/ (duration * 1000);

    return {
      'sampleRate': sampleRate,
      'channels': channels,
      'bitsPerSample': bitsPerSample,
      'bitrate': bitrate,
      'version': '${version / 1000}',
      'duration': _fromDoubleSeconds(duration),
    };
  }

  /// Converts double seconds to Duration
  static Duration _fromDoubleSeconds(double seconds) {
    final whole = seconds.truncate();
    final fractional = ((seconds - whole) * 1000).round();
    return Duration(seconds: whole, milliseconds: fractional);
  }

  /// Parses track number from string
  static int _parseTrack(String? raw) {
    if (raw == null) return 0;
    return int.tryParse(raw.split('/').first) ?? 0;
  }

  /// Parses total tracks from string
  static int _parseTotal(String? raw) {
    final parts = raw?.split('/') ?? [];
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// Parses disc number from string
  static int _parseDisc(String? raw) {
    if (raw == null) return 0;
    return int.tryParse(raw.split('/').first) ?? 0;
  }

  /// Parses integer from string
  static int _parseInt(String? raw) {
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  /// Parses year from string
  static DateTime? _parseYear(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    int? year;

    if (raw.contains("-")) {
      year = int.tryParse(raw.split("-").first);
    } else if (raw.contains("/")) {
      year = int.tryParse(raw.split("/").first);
    } else {
      year = int.tryParse(raw);
    }

    if (year == null) return null;
    return DateTime(year);
  }

  static String uint8ListToHexString(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<Picture> getPictures(Map<String, dynamic> map) {
    List<Picture> pics = [];
    map.forEach((key, value) {
      if (key.startsWith('cover art')) {
        //   other,
        //   fileIcon32x32,
        //   otherFileIcon,
        //   coverFront,
        //   coverBack,
        //   leafletPage,
        //   mediaLabelCD,
        //   leadArtist,
        //   artistPerformer,
        //   conductor,
        //   bandOrchestra,
        //   composer,
        //   lyricistTextWriter,
        //   recordingLocation,
        //   duringRecording,
        //   duringPerformance,
        //   movieVideoScreenCapture,
        //   brightColouredFish,
        //   illustration,
        //   bandArtistLogotype,
        //   publisherStudioLogotype,
        if (key.contains('front')) {
          pics.add(
            Picture(
              value,
              checkImageFormat(value) ?? 'image/jpeg',
              PictureType.coverFront,
            ),
          );
        } else if (key.contains('back')) {
          pics.add(
            Picture(
              value,
              checkImageFormat(value) ?? 'image/jpeg',
              PictureType.coverBack,
            ),
          );
        } else {
          pics.add(
            Picture(
              value,
              checkImageFormat(value) ?? 'image/jpeg',
              PictureType.other,
            ),
          );
        }
      }
    });
    return pics;
  }

  /// Checks image format based on byte signature
  static String? checkImageFormat(Uint8List bytes) {
    if (bytes.length < 8) return null;
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'image/bmp';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return 'image/gif';
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return 'image/webp';
    return 'image/jpeg';
  }
}
