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
/// Contains the validated location and size of an ISO-BMFF box.
class BoxHeader {
  /// Absolute byte position where this box header starts.
  final int start;

  /// Total box size in bytes (header + payload).
  final int size;

  /// Number of bytes occupied by this header: 8 normally, 16 for large-size.
  final int headerSize;

  /// Four-character box type.
  final String type;

  /// Absolute byte position immediately after this box.
  int get end => start + size;

  /// Number of bytes available to this box after its header.
  int get payloadSize => size - headerSize;

  /// Build a box header that has already passed its parent-boundary checks.
  BoxHeader({
    required this.start,
    required this.size,
    required this.headerSize,
    required this.type,
  });
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
/// Protocol section: ISO-BMFF box header
/// Layout (big-endian):
/// ```text
/// SSSS SSSS TTTT TTTT
/// ```
/// Meaning:
/// - `S`: 32-bit box size. `0` extends to the containing scope's end; `1`
///   means an eight-byte 64-bit size follows the type.
/// - `T`: four-byte ASCII/QuickTime box type.
/// Constraints:
/// - Normal boxes are at least 8 bytes; large-size boxes are at least 16.
/// - Child boxes, including size-zero boxes, must end inside their parent.
///   This gives every traversal a finite, forward-only boundary.
/// - `meta` may contain either a 4-byte version/flags field or child boxes
///   directly; both layouts occur in valid MP4-family files in the wild.
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

    final int fileEnd = reader.lengthSync();

    while (buffer.fileCursor < fileEnd) {
      final BoxHeader box = _readBox(buffer, limit: fileEnd);

      if (supportedBox.contains(box.type)) {
        processBox(buffer, box);
      } else {
        // The validated box end is always after the header and within the
        // file, including for size-zero and large-size boxes.
        buffer.setPositionSync(box.end);
      }
    }

    return tags;
  }

  ///
  /// A box (or atom) header normally uses 8 bytes.
  ///
  /// [0...3] -> box size (header + body)
  /// [4...7] -> box name (ASCII)
  /// [8...15] -> 64-bit total size when the 32-bit size is `1`
  ///
  /// [limit] is the absolute end of the current parent scope. Validating
  /// against it before reading a payload prevents malformed child sizes from
  /// seeking into a sibling box or beyond the file.
  BoxHeader _readBox(Buffer buffer, {required int limit}) {
    final int start = buffer.fileCursor;
    _requireBytes(start, 8, limit);

    final Uint8List headerBytes = buffer.read(8);
    final ByteData parser = ByteData.sublistView(headerBytes);
    final int declaredSize = parser.getUint32(0);
    final Uint8List boxNameBytes = headerBytes.sublist(4);

    // throw error if we don't have a correct box name
    if (boxNameBytes[0] == 0 &&
        boxNameBytes[1] == 0 &&
        boxNameBytes[2] == 0 &&
        boxNameBytes[3] == 0) {
      throw MetadataParserException(
          track: File(""), message: "Malformed MP4 file");
    }

    int headerSize = 8;
    int size = declaredSize;

    if (declaredSize == 0) {
      // ISO-BMFF defines zero as extending to EOF. Within a nested traversal,
      // the containing box is the only legal EOF, so use its boundary.
      size = limit - start;
    } else if (declaredSize == 1) {
      _requireBytes(buffer.fileCursor, 8, limit);
      size = getUint64BE(buffer.read(8));
      headerSize = 16;
    }

    if (size < headerSize) {
      _malformed('MP4 box size is smaller than its header');
    }
    if (size > limit - start) {
      _malformed('MP4 box exceeds its parent boundary');
    }

    return BoxHeader(
      start: start,
      size: size,
      headerSize: headerSize,
      type: String.fromCharCodes(boxNameBytes),
    );
  }

  /// Fail before a read or seek would cross the active box boundary.
  void _requireBytes(int position, int length, int limit) {
    if (position < 0 || length < 0 || position + length > limit) {
      _malformed('MP4 box is truncated or exceeds its parent boundary');
    }
  }

  /// Produce one consistent malformed-container error for boundary failures.
  Never _malformed(String message) {
    throw MetadataParserException(track: File(''), message: message);
  }

  /// Parse a box
  ///
  /// The metadata are inside special boxes. We only read data when we need it
  /// otherwise we skip them
  void processBox(Buffer buffer, BoxHeader box) {
    if (box.type == "moov") {
      parseRecursive(buffer, box);
    } else if (box.type == "mvhd") {
      _requirePayloadBytes(buffer, box, 1);
      final int version = buffer.read(1)[0];

      // version 0 has 100 bytes
      // version 1 has 112 bytes
      final int remainingMvhdBytes = version == 1 ? 111 : 99;
      _requirePayloadBytes(buffer, box, remainingMvhdBytes);
      final Uint8List bytes = buffer.read(remainingMvhdBytes);

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
      parseRecursive(buffer, box);
    } else if (box.type == "ilst") {
      parseRecursive(buffer, box);
    } else if (["trak", "mdia", "minf", "stbl", "stsd"].contains(box.type)) {
      parseRecursive(buffer, box);
    } else if (box.type == "meta") {
      parseRecursive(buffer, box);
    } else if (box.type == "chpl") {
      // `chpl` is a chapter list atom used by many MP4/M4A encoders.
      _parseChapterListBox(buffer.read(box.payloadSize));
    } else if (box.type[0] == "©" ||
        ["gnre", "trkn", "disk", "tmpo", "cpil", "too", "covr", "pgap", "gen"]
            .contains(box.type)) {
      final boxName = (box.type[0] == "©") ? box.type.substring(1) : box.type;

      if (boxName == "covr" && !fetchImage) {
        buffer.skip(box.payloadSize);
      } else {
        final Uint8List metadataValue = buffer.read(box.payloadSize);

        // sometimes the data is stored inside another box called `data`
        // we try to find out if the data contains the box type "data" (0:4 is the box size)
        // otherwise we just skip the Apple's tag of 4 chars
        final Uint8List data =
            (String.fromCharCodes(metadataValue.sublist(4, 8)) == "data")
                ? metadataValue.sublist(16)
                : metadataValue.sublist(4);

        final String value = _decodeString(data);

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
            final int? intDay = int.tryParse(value);

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
            final Uint8List imageData = data;
            tags.picture = Picture(
                imageData,
                lookupMimeType("no path", headerBytes: imageData) ?? "",
                PictureType.coverFront);
            break;
          case "trkn":
            final int a = getUint16(data.sublist(2, 4));
            final int totalTracks = getUint16(data.sublist(4, 6));
            tags.totalTracks = totalTracks;
            if (a > 0) {
              tags.trackNumber = a;
            }
            break;
        }
      }
    } else if (box.type == "----") {
      final BoxHeader mean = _readBox(buffer, limit: box.end);
      String.fromCharCodes(buffer.read(mean.payloadSize)); // mean value

      final BoxHeader name = _readBox(buffer, limit: box.end);

      final nameValue =
          String.fromCharCodes(buffer.read(name.payloadSize).sublist(4));
      final BoxHeader dataBox = _readBox(buffer, limit: box.end);
      final Uint8List data = buffer.read(dataBox.payloadSize);
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
      final Uint8List bytes = buffer.read(box.payloadSize);

      // tags.bitrate = timeScale;
      tags.sampleRate = getUint32(bytes.sublist(22, 26));
    } else {
      buffer.setPositionSync(box.end);
    }

    // A specialised parser may consume only the fields it needs. Restore the
    // cursor to the declared end so its parent always starts the next child at
    // a new position; fail instead if a parser crossed this box's boundary.
    if (buffer.fileCursor > box.end) {
      _malformed('MP4 box payload exceeds its declared size');
    }
    if (buffer.fileCursor < box.end) {
      buffer.setPositionSync(box.end);
    }
  }

  /// Ensure a fixed-size field is completely inside [box]'s payload.
  void _requirePayloadBytes(Buffer buffer, BoxHeader box, int length) {
    _requireBytes(buffer.fileCursor, length, box.end);
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

  /// Parse child boxes until the declared end of [box].
  ///
  /// The loop has no manually maintained offset: each iteration reads a
  /// validated header and moves the cursor to that child's absolute end. That
  /// makes forward progress independent of special size values.
  void parseRecursive(Buffer buffer, BoxHeader box) {
    final int childStart = buffer.fileCursor;

    // ISO-BMFF normally stores 4 version/flags bytes at the start of `meta`,
    // but some Android/MediaStore files put child boxes directly there. Probe
    // the first 8 bytes only when they fit inside this parent, and consume the
    // prefix only when those bytes cannot describe a normal child header.
    if (box.type == "meta") {
      final int availableBytes = box.end - buffer.fileCursor;
      bool hasChildBoxHeader = false;

      if (availableBytes >= 8) {
        final Uint8List firstBytes = buffer.read(8);
        final int firstSize = getUint32(firstBytes.sublist(0, 4));
        final String firstType = String.fromCharCodes(firstBytes.sublist(4, 8));
        final bool hasPrintableType = firstType.codeUnits
            .every((int byte) => byte >= 0x20 && byte <= 0x7e);

        if (firstSize == 1 && availableBytes >= 16) {
          final int largeSize = getUint64BE(buffer.read(8));
          hasChildBoxHeader = largeSize >= 16 &&
              largeSize <= availableBytes &&
              hasPrintableType;
        } else if (firstSize == 0) {
          hasChildBoxHeader = hasPrintableType;
        } else {
          hasChildBoxHeader =
              firstSize >= 8 && firstSize <= availableBytes && hasPrintableType;
        }
        buffer.setPositionSync(childStart);
      }

      if (!hasChildBoxHeader) {
        _requireBytes(buffer.fileCursor, 4, box.end);
        buffer.skip(4);
      }
    } else if (box.type == "stsd") {
      // Sample descriptions start with a full-box version/flags field and a
      // 32-bit entry count before their child sample-entry boxes.
      _requireBytes(buffer.fileCursor, 8, box.end);
      buffer.skip(8);
    }

    while (buffer.fileCursor < box.end) {
      final BoxHeader child = _readBox(buffer, limit: box.end);

      if (supportedBox.contains(child.type)) {
        processBox(buffer, child);
      } else {
        buffer.setPositionSync(child.end);
      }
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
