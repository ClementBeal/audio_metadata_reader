import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/mp4_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

import '../../audio_metadata_reader.dart';
import '../utils/bit_manipulator.dart';

// https://xhelmboyx.tripod.com/formats/mp4-layout.txt

class Box {
  int size;
  String type;

  Box(this.size, this.type);
}

final recursiveBox = ["moov"];
final supportedBox = [
  "moov",
  "mvhd",
  "meta",
  "udta",
  "ilst",
  "gnre",
  "trkn",
  "disk",
  "tmpo",
  "cpil",
  "covr",
  "pgap",
  "©nam",
  "©ART",
  "©alb",
  "©cmt",
  "©day",
  "©too",
  "©trk",
  "----",
];

class MP4Parser extends TagParser {
  Mp4Metadata tags = Mp4Metadata();
  final bool fetchImage;

  MP4Parser({this.fetchImage = false});

  @override
  Future<ParserTag> parse(RandomAccessFile reader) async {
    reader.setPositionSync(0);

    final lengthFile = reader.lengthSync();

    while (reader.positionSync() < lengthFile) {
      final box = await _readBox(reader);

      if (supportedBox.contains(box.type)) {
        await processBox(reader, box);
      } else {
        // printIndent(_indent, "${box.type} -> ${box.size}");

        reader.setPositionSync(reader.positionSync() + box.size - 8);
      }
    }

    reader.closeSync();

    return tags;
  }

  Future<Box> _readBox(RandomAccessFile reader) async {
    final headerBytes = reader.readSync(8);
    final parser = ByteData.sublistView(headerBytes);

    final boxSize = parser.getUint32(0);
    final boxName = String.fromCharCodes(headerBytes.sublist(4));

    return Box(boxSize, boxName);
  }

  Future<void> processBox(RandomAccessFile reader, Box box) async {
    // printIndent(_indent, "${box.type} -> ${box.size}");

    if (recursiveBox.contains(box.type)) {
      await parseRecurvise(reader, box);
    } else if (box.type == "mvhd") {
      final bytes = reader.readSync(100);

      final timeScale = getUint32(bytes.sublist(12, 16));
      final timeUnit = getUint32(bytes.sublist(16, 20));

      tags.bitrate = timeScale;

      tags.duration = Duration(seconds: timeUnit ~/ timeScale);
    } else if (box.type == "udta") {
      await parseRecurvise(reader, box);
    } else if (box.type == "ilst") {
      await parseRecurvise(reader, box);
    } else if (box.type == "meta") {
      reader.readSync(4);

      await parseRecurvise(reader, box);
    } else if (box.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap"]
            .contains(box.type)) {
      final bytes = reader.readSync(box.size - 8);
      final i = bytes.sublist(0, 4);
      final dataString = bytes.sublist(4, 8);
      final flags = bytes.sublist(8, 12);

      String value;
      try {
        value = const Utf8Decoder().convert(bytes.sublist(16));
      } catch (e) {
        value = String.fromCharCodes(bytes.sublist(16));
      }
      final boxName = (box.type[0] == "©") ? box.type.substring(1) : box.type;

      switch (boxName) {
        case "nam":
          tags.title = value;
          break;
        case "ART":
          tags.artist = value;
          break;
        case "alb":
          tags.album = value;
          break;
        case "cmt":
          // tags. = value;
          break;
        case "day":
          tags.year = DateTime(int.parse(value));
          // tags.year = int.parse(value);
          break;
        case "too":
          // print("too ->");
          break;
        // tags.year = int.parse(value);
        case "disk":
          tags.discNumber = getUint32(bytes.sublist(16, 20));
          break;

        case "covr":
          tags.picture = Picture(bytes.sublist(16), "", PictureType.coverFront);
        case "trkn":
          final a = getUint32(bytes.sublist(16, 20));
          // print("trkn: $a");
          if (a != 0) {
            tags.trackNumber = a;
          }
          break;
      }
    } else if (box.type == "----") {
      final mean = await _readBox(reader);
      final meanValue = String.fromCharCodes(reader.readSync(mean.size - 8));

      final name = await _readBox(reader);
      // reader.readSync(4);

      final nameValue =
          String.fromCharCodes(reader.readSync(name.size - 8).sublist(4));
      final dataBox = await _readBox(reader);
      final data = reader.readSync(dataBox.size - 8);
      final finalValue = String.fromCharCodes(data.sublist(8));

      switch (nameValue) {
        case "iTunes_CDDB_TrackNumber":
          tags.trackNumber = int.parse(finalValue);
          break;
        default:
      }
    } else {
      reader.setPositionSync(reader.positionSync() + box.size - 8);
    }
  }

  Future<void> parseRecurvise(RandomAccessFile reader, Box box) async {
    final limit = box.size - 8;
    int offset = 0;
    // printIndent(_indent, "Recursive: ${box.type}");

    if (box.type == "meta") {
      offset += 4;
    }

    while (offset < limit) {
      final newBox = await _readBox(reader);

      if (supportedBox.contains(newBox.type)) {
        await processBox(reader, newBox);
      } else {
        // printIndent(_indent, "Not contain: ${newBox.type}");
        reader.setPositionSync(reader.positionSync() + newBox.size - 8);
      }

      offset += newBox.size;
      // printIndent(_indent + 1, "${box.type} -> $offset/${limit}");
    }

    // printIndent(_indent, "End Recursive: ${box.type}");
  }

  static Future<bool> canUserParser(RandomAccessFile reader) async {
    reader.setPositionSync(0);

    final headerBytes = reader.readSync(8);
    final parser = ByteData.sublistView(headerBytes);

    final boxName = String.fromCharCodes(headerBytes.sublist(4));

    return boxName == "ftyp";
  }
}
