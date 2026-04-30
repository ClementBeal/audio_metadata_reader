import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:mime/mime.dart';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';

// https://xhelmboyx.tripod.com/formats/mp4-layout.txt

///
/// Contains the data of a box header
///
/// The size is the sum of the box header size and the box data
class BoxHeader {
  /// Total box size in bytes (header + payload).
  int size;

  /// Four-character box type.
  String type;

  /// Build a box header.
  BoxHeader(this.size, this.type);
}

/// MP4 box types this parser understands and recursively explores.
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
  "chpl",
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
class MP4Parser extends TagParser<Mp4Metadata> {
  /// Parsed MP4 metadata.
  Mp4Metadata tags = Mp4Metadata();

  /// Reader helper bound to the current file.
  late final Buffer buffer;

  /// Create an MP4 parser.
  MP4Parser({bool fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  Mp4Metadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);
    buffer = Buffer(randomAccessFile: reader);

    final lengthFile = reader.lengthSync();

    while (buffer.fileCursor < lengthFile) {
      final box = _readBox(buffer);

      if (supportedBox.contains(box.type)) {
        processBox(buffer, box);
      } else {
        // We substract 8 to the box size because we already read the data for
        // the box header
        buffer.skip(box.size - 8);
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
  BoxHeader _readBox(Buffer buffer) {
    final headerBytes = buffer.read(8);
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

  /// Parse a box
  ///
  /// The metadata are inside special boxes. We only read data when we need it
  /// otherwise we skip them
  void processBox(Buffer buffer, BoxHeader box) {
    if (box.type == "moov") {
      parseRecurvise(buffer, box);
    } else if (box.type == "mvhd") {
      final version = buffer.read(1)[0];

      // version 0 has 100 bytes
      // version 1 has 112 bytes
      final bytes = buffer.read(version == 1 ? 111 : 99);

      int timeScale = 0;
      int timeUnit = 0;

      if (version == 0) {
        timeScale = getUint32(bytes.sublist(11, 15));
        timeUnit = getUint32(bytes.sublist(15, 19));
      } else {
        timeScale = getUint32(bytes.sublist(19, 23));
        timeUnit = getUint64BE(bytes.sublist(23, 31));
      }

      double microseconds = (timeUnit / timeScale) * 1000000;
      tags.duration = Duration(microseconds: microseconds.toInt());
    } else if (box.type == "udta") {
      parseRecurvise(buffer, box);
    } else if (box.type == "ilst") {
      parseRecurvise(buffer, box);
    } else if (["trak", "mdia", "minf", "stbl", "stsd"].contains(box.type)) {
      parseRecurvise(buffer, box);
    } else if (box.type == "meta") {
      buffer.read(4);

      parseRecurvise(buffer, box);
    } else if (box.type == "chpl") {
      // `chpl` is a chapter list atom used by many MP4/M4A encoders.
      _parseChapterListBox(buffer.read(box.size - 8));
    } else if (box.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap", "gen"]
            .contains(box.type)) {
      final boxName = (box.type[0] == "©") ? box.type.substring(1) : box.type;

      if (boxName == "covr" && !fetchImage) {
        buffer.skip(box.size - 8);
        return;
      }

      final metadataValue = buffer.read(box.size - 8);

      // sometimes the data is stored inside another box called `data`
      // we try to find out if the data contains the box type "data" (0:4 is the box size)
      // otherwise we just skip the Apple's tag of 4 chars
      final data = (String.fromCharCodes(metadataValue.sublist(4, 8)) == "data")
          ? metadataValue.sublist(16)
          : metadataValue.sublist(4);

      final value = _decodeString(data);

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
          tags.discNumber = getUint16(data.sublist(2, 4));
          tags.totalDiscs = getUint16(data.sublist(4, 6));
          break;

        case "covr":
          final imageData = data;
          tags.picture = Picture(
              imageData,
              lookupMimeType("no path", headerBytes: imageData) ?? "",
              PictureType.coverFront);
          break;
        case "trkn":
          final a = getUint16(data.sublist(2, 4));
          final totalTracks = getUint16(data.sublist(4, 6));
          tags.totalTracks = totalTracks;
          if (a > 0) {
            tags.trackNumber = a;
          }
          break;
      }
    } else if (box.type == "----") {
      final mean = _readBox(buffer);
      String.fromCharCodes(buffer.read(mean.size - 8)); // mean value

      final name = _readBox(buffer);

      final nameValue =
          String.fromCharCodes(buffer.read(name.size - 8).sublist(4));
      final dataBox = _readBox(buffer);
      final data = buffer.read(dataBox.size - 8);
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
      final bytes = buffer.read(box.size - 8);

      // tags.bitrate = timeScale;
      tags.sampleRate = getUint32(bytes.sublist(22, 26));
    } else {
      buffer.setPositionSync(buffer.fileCursor + box.size - 8);
    }
  }

  String _decodeString(Uint8List value) {
    try {
      // Chapter titles and iTunes text metadata are usually UTF-8.
      return utf8.decode(value);
    } catch (_) {
      // Keep latin1 fallback for malformed or legacy tags.
      return latin1.decode(value);
    }
  }

  /// Parse chapter list atom (`chpl`) and append parsed chapters.
  ///
  /// The most common layout is:
  /// - 4 bytes: version + flags (full box)
  /// - 4 bytes: reserved
  /// - 1 byte: chapter count
  /// - N chapters:
  ///   - 8 bytes: start timestamp in 100ns units
  ///   - 1 byte: title size
  ///   - title bytes (UTF-8)
  void _parseChapterListBox(Uint8List value) {
    if (value.length < 5) {
      return;
    }

    // We handle both layouts found in the wild:
    // - [version+flags][reserved][count]...  => count at offset 8
    // - [version+flags][count]...            => count at offset 4
    final chapterFromReserved = _extractChapters(value, chapterCountOffset: 8);
    final chapterWithoutReserved =
        _extractChapters(value, chapterCountOffset: 4);
    final chapters = _pickBestChapterList(
      chapterFromReserved,
      chapterWithoutReserved,
    );

    if (chapters == null) {
      return;
    }

    tags.chapters.addAll(chapters);
  }

  List<Chapter>? _pickBestChapterList(
    List<Chapter>? withReserved,
    List<Chapter>? withoutReserved,
  ) {
    if (withReserved == null) {
      return withoutReserved;
    }

    if (withoutReserved == null) {
      return withReserved;
    }

    if (withoutReserved.length > withReserved.length) {
      // Prefer the parse that produced more complete chapters.
      return withoutReserved;
    }

    return withReserved;
  }

  List<Chapter>? _extractChapters(
    Uint8List value, {
    required int chapterCountOffset,
  }) {
    if (chapterCountOffset >= value.length) {
      return null;
    }

    int offset = chapterCountOffset;
    final chapterCount = value[offset];
    offset += 1;
    final chapters = <Chapter>[];

    for (int i = 0; i < chapterCount; i++) {
      // Each entry needs at least 8 bytes timestamp + 1 byte title length.
      if (offset + 9 > value.length) {
        return null;
      }

      final startIn100Nanoseconds =
          getUint64BE(value.sublist(offset, offset + 8));
      offset += 8;

      final titleLength = value[offset];
      offset += 1;

      // If one entry is truncated, consider this parse strategy invalid.
      if (offset + titleLength > value.length) {
        return null;
      }

      final titleBytes = value.sublist(offset, offset + titleLength);
      offset += titleLength;

      chapters.add(
        Chapter(
          // `chpl` stores timestamps in 100ns ticks, Duration uses microseconds.
          start: Duration(microseconds: (startIn100Nanoseconds / 10).round()),
          title: _decodeString(titleBytes),
        ),
      );
    }

    return chapters;
  }

  /// Parse a box with multiple sub boxes.
  void parseRecurvise(Buffer buffer, BoxHeader box) {
    final limit = box.size - 8;
    int offset = 0;

    // the `meta` box has 4 additional bytes that are not useful. We skip them
    if ("meta" == box.type) {
      offset += 4;
    } else if (box.type == "stsd") {
      offset += 8;
      buffer.read(8);
    }

    while (offset < limit) {
      final newBox = _readBox(buffer);

      if (supportedBox.contains(newBox.type)) {
        processBox(buffer, newBox);
      } else {
        buffer.skip(newBox.size - 8);
      }

      offset += newBox.size;
    }
  }

  /// To detect if this parser can be used to parse this file, we need to detect
  /// the first box. It should be a `ftyp` box
  /// Returns `true` when [reader] looks like an MP4-family file.
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(4);

    final headerBytes = reader.readSync(4);
    final boxName = String.fromCharCodes(headerBytes);

    return boxName == "ftyp";
  }
}
