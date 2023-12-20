import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/mp4_metadata.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';

class Box {
  Uint8List data;
  String type;

  Box(this.data, this.type);
}

final recursiveBox = ["moov"];
final supportedBox = [
  "moov",
  // "mvhd",
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
  // "----",
];

class Mp4Writer {
  bool _hasTitle = false;
  bool _hasArtist = false;
  bool _hasAlbum = false;
  bool _hasYear = false;
  bool _hasDisk = false;
  bool _hasTrackNumber = false;
  bool _hasGenre = false;
  bool _hasTempo = false;
  bool _hasCover = false;

  Future<void> write(RandomAccessFile reader, Mp4Metadata metadata) async {
    final writer = BytesBuilder();

    reader.setPositionSync(0);

    final lengthFile = reader.lengthSync();

    while (reader.positionSync() < lengthFile) {
      final box = await _readBox(reader);

      if (supportedBox.contains(box.type)) {
        final newBox = processBox(reader, metadata, box);

        _writeBox(writer, newBox.type, newBox.data);
      } else {
        _writeBox(writer, box.type, box.data);
      }
    }

    reader.closeSync();
    File("test.mp4").writeAsBytesSync(writer.takeBytes());
  }

  Box processBox(
      RandomAccessFile reader, Mp4Metadata metadata, Box originalBox) {
    if (originalBox.type == "moov") {
      final newBox = parseRecurvise(reader, metadata, originalBox);
      return Box(newBox.data, newBox.type);
    } else if (originalBox.type == "udta") {
      final newBox = parseRecurvise(reader, metadata, originalBox);

      return Box(newBox.data, newBox.type);
    } else if (originalBox.type == "ilst") {
      final newBox = parseRecurvise(reader, metadata, originalBox);

      return Box(newBox.data, newBox.type);
    } else if (originalBox.type == "meta") {
      // reader.readSync(4);

      final newBox = parseRecurvise(reader, metadata, originalBox);
      // print(String.fromCharCodes(newBox.data).substring(0, 100));
      return Box(Uint8List.fromList([0, 0, 0, 0, ...newBox.data]), newBox.type);
    } else if (originalBox.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap"]
            .contains(originalBox.type)) {
      final writer = BytesBuilder();
      writer.add("data".codeUnits);

      String value;
      try {
        value = const Utf8Decoder().convert(originalBox.data.sublist(16));
      } catch (e) {
        value = String.fromCharCodes(originalBox.data.sublist(16));
      }

      final boxName = (originalBox.type[0] == "©")
          ? originalBox.type.substring(1)
          : originalBox.type;

      switch (boxName) {
        case "nam":
          writer.add([0, 0, 0, 1]); // text flag
          writer.add([0, 0, 0, 0]); // ?
          writer.add((metadata.title ?? value).codeUnits);

          _hasTitle = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        case "ART":
          writer.add([0, 0, 0, 1]); // text flag
          writer.add([0, 0, 0, 0]);
          writer.add((metadata.artist ?? value).codeUnits);
          _hasArtist = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        case "day":
          writer.add([0, 0, 0, 1]); // text flag
          writer.add([0, 0, 0, 0]);
          writer.add((metadata.year?.year ?? value).toString().codeUnits);

          _hasYear = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        case "alb":
          writer.add([0, 0, 0, 1]); // text flag
          writer.add([0, 0, 0, 0]);
          writer.add((metadata.album ?? value).codeUnits);
          _hasAlbum = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        case "trkn":
          writer.add([0, 0, 0, 0]); // number flag
          writer.add([0, 0, 0, 0]);
          writer.add((metadata.trackNumber ?? value).toString().codeUnits);
          _hasTrackNumber = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        // case "gnre":
        //   writer.add([0, 0, 0, 1]); // number flag
        //   writer.add([0, 0, 0, 0]);
        //   writer.add((metadata. ?? value).toString().codeUnits);
        //   _hasTrackNumber = true;

        //   return Box(
        //       Uint8List.fromList(
        //           [...intToUint32(writer.length + 4), ...writer.toBytes()]),
        //       originalBox.type);

        case "covr":
          writer.add(intToUint32(0xD)); // cover flag
          writer.add([0, 0, 0, 0]);
          writer.add(metadata.picture?.bytes ?? value.codeUnits);
          _hasCover = true;

          return Box(
              Uint8List.fromList(
                  [...intToUint32(writer.length + 4), ...writer.toBytes()]),
              originalBox.type);
        // case "cmt":
        //   // tags. = value;
        //   break;
        // case "too":
        //   // print("too ->");
        //   break;
        // // tags.year = int.parse(value);
        // case "disk":
        //   tags.discNumber = getUint32(bytes.sublist(16, 20));
        //   break;
        default:
          return originalBox;
      }
    } else {
      return originalBox;
    }
  }

  Box parseRecurvise(RandomAccessFile reader, Mp4Metadata metadata, Box box) {
    final limit = box.data.length;
    final writer = BytesBuilder();

    int offset = 0;

    if (box.type == "meta") {
      offset += 4;
    }

    while (offset < limit) {
      final newBox = _readBoxFromData(box.data, offset);

      if (supportedBox.contains(newBox.type)) {
        final resultBox = processBox(reader, metadata, newBox);
        _writeBox(writer, resultBox.type, resultBox.data);
      } else {
        _writeBox(writer, newBox.type, newBox.data);
      }

      offset += newBox.data.length + 8; // 8 is box header size
    }

    // if (box.type == "ilst") {
    //   final newMetadataWriter = BytesBuilder();
    //   if (metadata.title != null && !_hasTitle) {
    //     print("--- title");
    //     newMetadataWriter.add("data".codeUnits);

    //     newMetadataWriter.add([0, 0, 0, 1]); // text flag
    //     newMetadataWriter.add([0, 0, 0, 0]); // ?
    //     newMetadataWriter.add((metadata.title!).codeUnits);
    //     final b = Box(
    //         Uint8List.fromList([
    //           ...intToUint32(newMetadataWriter.length + 4),
    //           ...newMetadataWriter.takeBytes()
    //         ]),
    //         "nam");
    //     _writeBox(writer, b.type, b.data);
    //   }

    //   // if (metadata.artist != null && !_hasArtist) {
    //   //   newMetadataWriter.add("data".codeUnits);

    //   //   newMetadataWriter.add([0, 0, 0, 1]); // text flag
    //   //   newMetadataWriter.add([0, 0, 0, 0]); // ?
    //   //   newMetadataWriter.add((metadata.artist!).codeUnits);
    //   //   final b = Box(
    //   //       Uint8List.fromList([
    //   //         ...intToUint32(newMetadataWriter.length + 4),
    //   //         ...newMetadataWriter.takeBytes()
    //   //       ]),
    //   //       "ART");
    //   //   _writeBox(writer, b.type, b.data);
    //   // }

    //   if (metadata.year != null && !_hasYear) {
    //     newMetadataWriter.add("data".codeUnits);

    //     newMetadataWriter.add([0, 0, 0, 1]); // text flag
    //     newMetadataWriter.add([0, 0, 0, 0]); // ?
    //     newMetadataWriter.add((metadata.year!.year.toString()).codeUnits);
    //     final b = Box(
    //         Uint8List.fromList([
    //           ...intToUint32(newMetadataWriter.length + 4),
    //           ...newMetadataWriter.takeBytes()
    //         ]),
    //         "day");
    //     _writeBox(writer, b.type, b.data);
    //   }

    //   // if (metadata.album != null && !_hasAlbum) {
    //   //   newMetadataWriter.add("data".codeUnits);

    //   //   newMetadataWriter.add([0, 0, 0, 1]); // text flag
    //   //   newMetadataWriter.add([0, 0, 0, 0]); // ?
    //   //   newMetadataWriter.add((metadata.album!).codeUnits);
    //   //   final b = Box(
    //   //       Uint8List.fromList([
    //   //         ...intToUint32(newMetadataWriter.length + 4),
    //   //         ...newMetadataWriter.toBytes()
    //   //       ]),
    //   //       "alb");
    //   //   _writeBox(writer, b.type, b.data);
    //   // }
    // }

    return Box(writer.takeBytes(), box.type);
  }

  void _writeBox(BytesBuilder writer, String name, Uint8List data) {
    writer.add(intToUint32(data.length + 8));
    writer.add(name.codeUnits);
    writer.add(data);
  }

  Future<Box> _readBox(RandomAccessFile reader) async {
    final headerBytes = reader.readSync(8);
    final parser = ByteData.sublistView(headerBytes);

    final boxSize = parser.getUint32(0);
    final boxName = String.fromCharCodes(headerBytes.sublist(4));

    return Box(reader.readSync(boxSize - 8), boxName);
  }

  Box _readBoxFromData(Uint8List data, int offset) {
    final parser = ByteData.sublistView(data);

    final boxSize = getUint32(data.sublist(offset, 4 + offset));
    final boxName = String.fromCharCodes(data.sublist(4 + offset, 8 + offset));

    return Box(data.sublist(8 + offset, offset + boxSize), boxName);
  }
}
