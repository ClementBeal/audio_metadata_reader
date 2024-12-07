import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:mime/mime.dart';

import '../../audio_metadata_reader.dart';
import '../utils/bit_manipulator.dart';

// https://xhelmboyx.tripod.com/formats/mp4-layout.txt

///
/// Contains the data of a box header
///
/// The size is the sum of the box header size and the box data
class BoxHeader {
  int size;
  String type;

  BoxHeader(this.size, this.type);
}

final supportedBox = [
  "moov",
  "mvhd",
  "meta",
  "mdat",
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
  "©lyr",
  "©gen",
  "----",
  "trak",
  "mdia",
  "minf",
  "stbl",
  "stsd",
  "mp4a",
];

///
/// The parser for the MP4 files
///
/// The mp4 metadata format uses boxes (also called atoms) to format its data
/// In our case, we only need the metadata and some additional information like
/// bitrate and duration.
///
/// In short, the metadata are stored there:
/// `moov` -> `udta` - `meta` -> `ilst`
///
/// Information about the bitrate and duration are stored in `mvhd`
///
class MP4Parser extends TagParser {
  Mp4Metadata tags = Mp4Metadata();

  MP4Parser({fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final lengthFile = reader.lengthSync();

    while (reader.positionSync() < lengthFile) {
      final box = _readBox(reader);

      if (supportedBox.contains(box.type)) {
        processBox(reader, box);
      } else {
        // We substract 8 to the box size because we already read the data for
        // the box header
        reader.setPositionSync(reader.positionSync() + box.size - 8);
      }
    }

    reader.closeSync();

    return tags;
  }

  ///
  /// A box (or atom) header uses 8 bytes
  ///
  /// [0...3] -> box size (header + body)
  /// [4...7] -> box name (ASCII)
  ///
  BoxHeader _readBox(RandomAccessFile reader) {
    final headerBytes = reader.readSync(8);
    final parser = ByteData.sublistView(headerBytes);

    final boxSize = parser.getUint32(0);
    final boxNameBytes = headerBytes.sublist(4);

    // throw error if we don't have a correct box name
    if (boxNameBytes[0] == 0 &&
        boxNameBytes[1] == 0 &&
        boxNameBytes[2] == 0 &&
        boxNameBytes[3] == 0) {
      throw MetadataParserException(
          track: File(""), message: "Malformed MP4 file");
    }

    return BoxHeader(boxSize, String.fromCharCodes(boxNameBytes));
  }

  ///
  /// Parse a box
  ///
  /// The metadata are inside special boxes. We only read data when we need it
  /// otherwise we skip them
  ///
  void processBox(RandomAccessFile reader, BoxHeader box) {
    if (box.type == "moov") {
      parseRecurvise(reader, box);
    } else if (box.type == "mvhd") {
      final bytes = reader.readSync(100);

      final timeScale = getUint32(bytes.sublist(12, 16));
      final timeUnit = getUint32(bytes.sublist(16, 20));

      double microseconds = (timeUnit / timeScale) * 1000000;
      tags.duration = Duration(microseconds: microseconds.toInt());
    } else if (box.type == "udta") {
      parseRecurvise(reader, box);
    } else if (box.type == "ilst") {
      parseRecurvise(reader, box);
    } else if (["trak", "mdia", "minf", "stbl", "stsd"].contains(box.type)) {
      parseRecurvise(reader, box);
    } else if (box.type == "meta") {
      reader.readSync(4);

      parseRecurvise(reader, box);
    } else if (box.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap", "gen"]
            .contains(box.type)) {
      final bytes = reader.readSync(box.size - 8);

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
          break;
        case "lyr":
          tags.lyrics = value;
          break;
        case "gen":
          tags.genre = value;
          break;
        case "day":
          final intDay = int.tryParse(value);

          if (intDay != null) {
            tags.year = DateTime(intDay);
          } else {
            tags.year = DateTime.tryParse(value);
          }
          break;
        case "too":
          break;
        case "disk":
          tags.discNumber = getUint16(bytes.sublist(18, 20));
          tags.totalDiscs = getUint16(bytes.sublist(20, 22));
          break;

        case "covr":
          if (fetchImage) {
            final imageData = bytes.sublist(16);
            tags.picture = Picture(
                imageData,
                lookupMimeType("no path", headerBytes: imageData) ?? "",
                PictureType.coverFront);
          }
        case "trkn":
          final a = getUint16(bytes.sublist(18, 20));
          final totalTracks = getUint16(bytes.sublist(20, 22));
          tags.totalTracks = totalTracks;
          if (a > 0) {
            tags.trackNumber = a;
          }
          break;
      }
    } else if (box.type == "----") {
      final mean = _readBox(reader);
      String.fromCharCodes(reader.readSync(mean.size - 8)); // mean value

      final name = _readBox(reader);

      final nameValue =
          String.fromCharCodes(reader.readSync(name.size - 8).sublist(4));
      final dataBox = _readBox(reader);
      final data = reader.readSync(dataBox.size - 8);
      final finalValue = String.fromCharCodes(data.sublist(8));

      switch (nameValue) {
        case "iTunes_CDDB_TrackNumber":
          tags.trackNumber = int.parse(finalValue);
          break;
        // case "iTunes_CDDB_TrackNumber":
        //   tags.trackNumber = int.parse(finalValue);
        //   break;
        default:
      }
    } else if (box.type == "mp4a") {
      final bytes = reader.readSync(box.size - 8);

      // tags.bitrate = timeScale;
      tags.sampleRate = getUint32(bytes.sublist(22, 26));
    } else {
      reader.setPositionSync(reader.positionSync() + box.size - 8);
    }
  }

  ///
  /// Parse a box with multiple sub boxes.
  ///
  void parseRecurvise(RandomAccessFile reader, BoxHeader box) {
    final limit = box.size - 8;
    int offset = 0;

    // the `meta` box has 4 additional bytes that are not useful. We skip them
    if ("meta" == box.type) {
      offset += 4;
    } else if (box.type == "stsd") {
      offset += 8;
      reader.readSync(8);
    }

    while (offset < limit) {
      final newBox = _readBox(reader);

      if (supportedBox.contains(newBox.type)) {
        processBox(reader, newBox);
      } else {
        reader.setPositionSync(reader.positionSync() + newBox.size - 8);
      }

      offset += newBox.size;
    }
  }

  ///
  /// To detect if this parser can be used to parse this file, we need to detect
  /// the first box. It should be a `ftyp` box
  ///
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(4);

    final headerBytes = reader.readSync(4);
    final boxName = String.fromCharCodes(headerBytes);

    return boxName == "ftyp";
  }
}
