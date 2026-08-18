import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/containers/mp4.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart';

/*
 * Protocol section: ISO Base Media File Format (MP4/M4A) boxes.
 *
 * Bytes 0..3: unsigned big-endian box size, including this 8-byte header.
 * Bytes 4..7: four-character box type (FourCC).
 * A `meta` full box starts with 4 bytes of version and flags, followed by
 * child boxes. Some files omit that full-box prefix, so the writer preserves
 * the form it reads.
 *
 * `stco` layout:
 *   bytes 0..3: version and flags
 *   bytes 4..7: unsigned big-endian entry count
 *   bytes 8.. : entry count unsigned 32-bit chunk offsets
 *
 * `co64` has the same layout, except each chunk offset is an unsigned
 * 64-bit big-endian value. Chunk offsets are absolute file offsets, therefore
 * changing the size of a `moov` box before media data requires rewriting them.
 * Invalid sizes and offsets are rejected before the destination is written.
 */

/// Writer for MP4/M4A metadata atoms.
class Mp4Writer extends BaseMetadataWriter<Mp4Metadata> {
  /// Boxes whose payload is itself a sequence of child boxes.
  static const Set<String> _recursiveBoxes = <String>{
    "moov",
    "udta",
    "meta",
    "ilst",
  };

  /// Containers that may contain `stco` or `co64` somewhere below them.
  static const Set<String> _chunkOffsetContainers = <String>{
    "moov",
    "trak",
    "mdia",
    "minf",
    "stbl",
    "udta",
    "meta",
    "ilst",
    "edts",
    "dinf",
    "mvex",
    "moof",
    "traf",
  };

  /// Metadata currently being serialized.
  late Mp4Metadata mp4metadata;

  @override
  void writeContents(File source, File destination, Mp4Metadata metadata) {
    mp4metadata = metadata;
    final reader = source.openSync();
    final List<_TopLevelBox> boxes = <_TopLevelBox>[];

    try {
      final lengthFile = reader.lengthSync();

      while (reader.positionSync() < lengthFile) {
        final int boxStart = reader.positionSync();
        final Uint8List headerBytes = reader.readSync(8);
        final BoxHeader box = _readBox(headerBytes);
        final int bodyLength = box.size - 8;

        if (bodyLength > lengthFile - reader.positionSync()) {
          throw const FormatException("MP4 box extends beyond the file");
        }

        final Uint8List boxData = reader.readSync(bodyLength);
        boxes.add(_TopLevelBox(boxStart, box, boxData));
      }
    } finally {
      reader.closeSync();
    }

    int? mdatStart;
    for (final _TopLevelBox box in boxes) {
      if (box.header.type == "mdat") {
        mdatStart ??= box.start;
        break;
      }
    }

    final Map<_TopLevelBox, Uint8List> processedMoov =
        <_TopLevelBox, Uint8List>{};
    int moovDeltaBeforeMdat = 0;

    for (final _TopLevelBox box in boxes) {
      if (box.header.type != "moov") {
        continue;
      }

      final Uint8List processedData = _processBox(box.data);
      processedMoov[box] = processedData;

      if (mdatStart != null && box.start < mdatStart) {
        moovDeltaBeforeMdat += processedData.length + 8 - box.header.size;
      }
    }

    final BytesBuilder outputBuilder = BytesBuilder();
    for (final _TopLevelBox box in boxes) {
      Uint8List outputData = box.data;

      if (box.header.type == "moov") {
        outputData = processedMoov[box]!;

        if (mdatStart != null &&
            box.start < mdatStart &&
            moovDeltaBeforeMdat != 0) {
          outputData = _adjustChunkOffsets(
            outputData,
            moovDeltaBeforeMdat,
            box.start + box.header.size,
          );
        }
      }

      outputBuilder.add(_serializeBox(box.header.type, outputData));
    }

    destination.writeAsBytesSync(outputBuilder.takeBytes());
  }

  Uint8List _processBox(Uint8List data) {
    int offset = 0;
    final BytesBuilder byteBuilder = BytesBuilder();

    while (offset < data.length) {
      final BoxHeader box = _readBox(_readBytes(data, offset, 8));
      offset += 8;

      final int boxDataLength = box.size - 8;
      if (boxDataLength > data.length - offset) {
        throw const FormatException("Nested MP4 box extends beyond its parent");
      }

      final Uint8List boxData = data.sublist(offset, offset + boxDataLength);
      offset += boxDataLength;

      if (box.type == "ilst") {
        final newMetadataData = _replaceMetadata(boxData);
        byteBuilder.add(_serializeBox(box.type, newMetadataData));
      } else if (_recursiveBoxes.contains(box.type)) {
        if (box.type == "meta") {
          final int childrenOffset = _metaChildrenOffset(boxData);
          final Uint8List recursiveBoxData =
              _processBox(boxData.sublist(childrenOffset));
          final BytesBuilder metaBuilder = BytesBuilder();

          if (childrenOffset == 4) {
            metaBuilder.add(boxData.sublist(0, 4));
          }
          metaBuilder.add(recursiveBoxData);
          byteBuilder.add(_serializeBox(box.type, metaBuilder.toBytes()));
        } else {
          final Uint8List recursiveBoxData = _processBox(boxData);
          byteBuilder.add(_serializeBox(box.type, recursiveBoxData));
        }
      } else {
        byteBuilder.add(_serializeBox(box.type, boxData));
      }
    }

    return byteBuilder.toBytes();
  }

  /// Rewrites absolute chunk offsets after a preceding `moov` changed size.
  ///
  /// The [delta] is the total size change of all `moov` boxes before `mdat`.
  /// An offset at or after [shiftStart] points into bytes that move with the
  /// old `moov` boundary. Offsets before that boundary are left untouched.
  Uint8List _adjustChunkOffsets(
    Uint8List data,
    int delta,
    int shiftStart,
  ) {
    int offset = 0;
    final BytesBuilder byteBuilder = BytesBuilder();

    while (offset < data.length) {
      final BoxHeader box = _readBox(_readBytes(data, offset, 8));
      offset += 8;

      final int boxDataLength = box.size - 8;
      if (boxDataLength > data.length - offset) {
        throw const FormatException("Nested MP4 box extends beyond its parent");
      }

      final Uint8List boxData = data.sublist(offset, offset + boxDataLength);
      offset += boxDataLength;
      Uint8List rewrittenData = boxData;

      if (box.type == "stco") {
        rewrittenData = _adjustStco(boxData, delta, shiftStart);
      } else if (box.type == "co64") {
        rewrittenData = _adjustCo64(boxData, delta, shiftStart);
      } else if (_chunkOffsetContainers.contains(box.type)) {
        if (box.type == "meta") {
          final int childrenOffset = _metaChildrenOffset(boxData);
          final Uint8List adjustedChildren = _adjustChunkOffsets(
            boxData.sublist(childrenOffset),
            delta,
            shiftStart,
          );
          final BytesBuilder metaBuilder = BytesBuilder();

          if (childrenOffset == 4) {
            metaBuilder.add(boxData.sublist(0, 4));
          }
          metaBuilder.add(adjustedChildren);
          rewrittenData = metaBuilder.toBytes();
        } else {
          rewrittenData = _adjustChunkOffsets(boxData, delta, shiftStart);
        }
      }

      byteBuilder.add(_serializeBox(box.type, rewrittenData));
    }

    return byteBuilder.toBytes();
  }

  Uint8List _adjustStco(Uint8List data, int delta, int shiftStart) {
    if (data.length < 8) {
      throw const FormatException("Malformed stco box");
    }

    final ByteData byteData = ByteData.sublistView(data);
    final int entryCount = byteData.getUint32(4, Endian.big);
    final int expectedLength = 8 + entryCount * 4;
    if (expectedLength != data.length) {
      throw const FormatException("Malformed stco entry table");
    }

    final Uint8List adjusted = Uint8List.fromList(data);
    final ByteData adjustedData = ByteData.sublistView(adjusted);
    for (int index = 0; index < entryCount; index++) {
      final int entryOffset = 8 + index * 4;
      final int originalOffset =
          adjustedData.getUint32(entryOffset, Endian.big);
      final int newOffset = _adjustOffset(originalOffset, delta, shiftStart);

      if (newOffset > 0xFFFFFFFF) {
        throw const FormatException(
            "stco offset exceeds 32 bits after rewriting moov");
      }
      adjustedData.setUint32(entryOffset, newOffset, Endian.big);
    }
    return adjusted;
  }

  Uint8List _adjustCo64(Uint8List data, int delta, int shiftStart) {
    if (data.length < 8) {
      throw const FormatException("Malformed co64 box");
    }

    final ByteData byteData = ByteData.sublistView(data);
    final int entryCount = byteData.getUint32(4, Endian.big);
    final int expectedLength = 8 + entryCount * 8;
    if (expectedLength != data.length) {
      throw const FormatException("Malformed co64 entry table");
    }

    final Uint8List adjusted = Uint8List.fromList(data);
    final ByteData adjustedData = ByteData.sublistView(adjusted);
    for (int index = 0; index < entryCount; index++) {
      final int entryOffset = 8 + index * 8;
      final int originalOffset =
          adjustedData.getUint64(entryOffset, Endian.big);
      final int newOffset = _adjustOffset(originalOffset, delta, shiftStart);
      if (newOffset < 0) {
        throw const FormatException("co64 offset became negative");
      }
      adjustedData.setUint64(entryOffset, newOffset, Endian.big);
    }
    return adjusted;
  }

  int _adjustOffset(int originalOffset, int delta, int shiftStart) {
    if (originalOffset < shiftStart) {
      return originalOffset;
    }

    final int adjustedOffset = originalOffset + delta;
    if (adjustedOffset < 0) {
      throw const FormatException("Chunk offset became negative");
    }
    return adjustedOffset;
  }

  int _metaChildrenOffset(Uint8List data) {
    if (data.length < 4) {
      throw const FormatException("Malformed meta box");
    }

    if (data.length >= 8 && _looksLikeBoxHeader(data, 0, data.length)) {
      return 0;
    }
    return 4;
  }

  bool _looksLikeBoxHeader(Uint8List data, int offset, int limit) {
    if (offset + 8 > limit) {
      return false;
    }

    final int size = getUint32(data.sublist(offset, offset + 4));
    if (size < 8 || size > limit - offset) {
      return false;
    }

    final List<int> typeBytes = data.sublist(offset + 4, offset + 8);
    return typeBytes.every((int byte) => byte >= 0x20);
  }

  Uint8List _readBytes(Uint8List data, int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > data.length) {
      throw const FormatException("MP4 box header is truncated");
    }
    return data.sublist(offset, offset + length);
  }

  Uint8List _serializeBox(String type, Uint8List data) {
    final int size = data.length + 8;
    if (size > 0xFFFFFFFF) {
      throw const FormatException("MP4 box is too large for a 32-bit header");
    }

    final BytesBuilder builder = BytesBuilder();
    builder.add(intToUint32(size));
    builder.add(type.codeUnits);
    builder.add(data);
    return builder.toBytes();
  }

  Uint8List _replaceMetadata(Uint8List data) {
    final ilstBuilder = BytesBuilder();

    if (mp4metadata.title != null) {
      ilstBuilder.add(_buildStringTag("©nam", mp4metadata.title!));
    }
    if (mp4metadata.artist != null) {
      ilstBuilder.add(_buildStringTag("©ART", mp4metadata.artist!));
    }
    if (mp4metadata.album != null) {
      ilstBuilder.add(_buildStringTag("©alb", mp4metadata.album!));
    }
    if (mp4metadata.genre != null) {
      ilstBuilder.add(_buildStringTag("©gen", mp4metadata.genre!));
    }
    if (mp4metadata.year != null) {
      ilstBuilder
          .add(_buildStringTag("©day", mp4metadata.year!.year.toString()));
    }
    if (mp4metadata.lyrics != null) {
      ilstBuilder.add(_buildStringTag("©lyr", mp4metadata.lyrics!));
    }

    if (mp4metadata.picture != null) {
      final covrTag = _buildCovrTag(mp4metadata.picture!);
      if (covrTag != null) {
        ilstBuilder.add(covrTag);
      }
    }

    if (mp4metadata.trackNumber != null) {
      ilstBuilder.add(_buildIntegerTag(
          "trkn", mp4metadata.trackNumber!, mp4metadata.totalTracks));
    }
    if (mp4metadata.discNumber != null) {
      ilstBuilder.add(_buildIntegerTag(
          "disk", mp4metadata.discNumber!, mp4metadata.totalDiscs));
    }

    return ilstBuilder.toBytes();
  }

  Uint8List _buildStringTag(String tagType, String value) {
    final valueBytes = utf8.encode(value);

    // --- Build the inner 'data' box ---
    // size (4 bytes) + 'data' (4 bytes) + version/flags (4 bytes) + locale (4 bytes) + value
    final dataBoxSize = 8 + 4 + 4 + valueBytes.length;
    final dataBuilder = BytesBuilder();
    dataBuilder.add(intToUint32(dataBoxSize)); // data box size
    dataBuilder.add("data".codeUnits); // data box type
    dataBuilder.add(intToUint32(1)); // version=0, flags=1 (UTF-8)
    dataBuilder.add(intToUint32(0)); // locale=0
    dataBuilder.add(valueBytes); // the actual string data

    // --- Build the outer tag box (e.g., ©nam) ---
    final dataBoxBytes = dataBuilder.toBytes();
    final tagBoxSize = 8 + dataBoxBytes.length;
    final tagBuilder = BytesBuilder();
    tagBuilder.add(intToUint32(tagBoxSize));
    tagBuilder.add(tagType.codeUnits);
    tagBuilder.add(dataBoxBytes);

    return tagBuilder.toBytes();
  }

  Uint8List? _buildCovrTag(Picture picture) {
    int dataTypeFlag;
    if (picture.mimetype.toLowerCase() == 'image/jpeg') {
      dataTypeFlag = 13; // JPEG data type
    } else if (picture.mimetype.toLowerCase() == 'image/png') {
      dataTypeFlag = 14; // PNG data type
    } else {
      print(
          "Warning: Unsupported picture mime type for 'covr' tag: ${picture.mimetype}. Skipping cover art.");
      return null; // Unsupported type
    }

    final valueBytes = picture.bytes;

    // --- Build the inner 'data' box ---
    // size (4) + 'data' (4) + version/flags (4, contains type) + locale (4) + value
    final dataBoxSize = 8 + 4 + 4 + valueBytes.length;
    final dataBuilder = BytesBuilder();
    dataBuilder.add(intToUint32(dataBoxSize)); // data box size
    dataBuilder.add("data".codeUnits);
    dataBuilder.add(intToUint32(dataTypeFlag)); // version=0, flags=dataTypeFlag
    dataBuilder.add(intToUint32(0)); // locale=0
    dataBuilder.add(valueBytes);

    // --- Build the outer 'covr' tag box ---
    final dataBoxBytes = dataBuilder.toBytes();
    final tagBoxSize = 8 + dataBoxBytes.length;
    final tagBuilder = BytesBuilder();
    tagBuilder.add(intToUint32(tagBoxSize));
    tagBuilder.add("covr".codeUnits);
    tagBuilder.add(dataBoxBytes);

    return tagBuilder.toBytes();
  }

  Uint8List _buildIntegerTag(String tagType, int current, [int? total]) {
    final dataBuilder = BytesBuilder();

    final valueBytes = BytesBuilder();
    valueBytes.add([0x00, 0x00]); // reserved
    valueBytes.add(intToUint16(current));
    valueBytes.add(intToUint16(total ?? 0));
    valueBytes.add([0x00, 0x00]); // reserved

    final fullData = valueBytes.toBytes();

    final dataBoxSize = 8 + 4 + 4 + fullData.length;
    dataBuilder.add(intToUint32(dataBoxSize));
    dataBuilder.add("data".codeUnits);
    dataBuilder.add(intToUint32(0)); // version=0, flags=0 (binary)
    dataBuilder.add(intToUint32(0)); // locale
    dataBuilder.add(fullData);

    final dataBox = dataBuilder.toBytes();
    final tagBoxSize = 8 + dataBox.length;

    final tagBuilder = BytesBuilder();
    tagBuilder.add(intToUint32(tagBoxSize));
    tagBuilder.add(tagType.codeUnits);
    tagBuilder.add(dataBox);

    return tagBuilder.toBytes();
  }

  /// A box (or atom) header uses 8 bytes
  ///
  /// [0...3] -> box size (header + body)
  /// [4...7] -> box name (ASCII)
  BoxHeader _readBox(Uint8List headerBytes) {
    if (headerBytes.length != 8) {
      throw const FormatException("MP4 box header must contain 8 bytes");
    }

    final boxSize = getUint32(headerBytes.sublist(0, 4));
    final boxNameBytes = headerBytes.sublist(4);

    if (boxSize < 8 || boxNameBytes.any((int byte) => byte < 0x20)) {
      throw const FormatException("Malformed MP4 box header");
    }

    return BoxHeader(boxSize, String.fromCharCodes(boxNameBytes));
  }
}

class _TopLevelBox {
  final int start;
  final BoxHeader header;
  final Uint8List data;

  _TopLevelBox(this.start, this.header, this.data);
}
