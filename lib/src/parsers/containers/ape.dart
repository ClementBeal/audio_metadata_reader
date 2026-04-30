import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:mime/mime.dart';

/// Parsed values from an APEv2 footer.
typedef ApeTagFooter = ({
  int version,
  int size,
  int itemCount,
  int flags,
});

/// Parser for APEv2 metadata tags.
///
/// APEv2 stores metadata as key/value items, usually in a footer placed at the
/// end of the file (32 bytes):
/// - 8 bytes: "APETAGEX"
/// - 4 bytes: version (little-endian), usually 2000
/// - 4 bytes: tag size
/// - 4 bytes: item count
/// - 4 bytes: tag flags
/// - 8 bytes: reserved
///
/// We currently implement read-only metadata extraction:
/// - text items are mapped to [ApeMetadata]
/// - binary cover items (`Cover Art (...)`) are mapped to [Picture]
class ApeParser extends TagParser<ApeMetadata> {
  /// Reader helper bound to the current file.
  late final Buffer _buffer;

  /// Create an APEv2 parser.
  ApeParser({super.fetchImage = false});

  @override
  ApeMetadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);
    _buffer = Buffer(randomAccessFile: reader);

    final footerOffset = _findFooterOffset(reader);

    if (footerOffset == null) {
      reader.closeSync();
      throw StateError('No APEv2 footer found');
    }

    reader.setPositionSync(footerOffset);
    final footerBytes = reader.readSync(32);
    final footer = _parseFooter(footerBytes);
    final fileLength = reader.lengthSync();

    // Why these checks:
    // - version < 2000: this parser only supports APEv2 (2.000 and later).
    // - size < 32: impossible because footer itself is 32 bytes.
    // - size > file length: malformed footer because a tag cannot be bigger
    //   than the entire file that contains it.
    if (footer.version < 2000 || footer.size < 32 || footer.size > fileLength) {
      reader.closeSync();
      throw StateError('Invalid APEv2 footer values');
    }

    final startOffsets = _buildCandidateStartOffsets(
      footerOffset: footerOffset,
      footerSize: footer.size,
    );

    ApeMetadata? parsedMetadata;
    for (final startOffset in startOffsets) {
      final metadata = _tryParseItems(
        startOffset: startOffset,
        footerOffset: footerOffset,
        itemCount: footer.itemCount,
      );

      if (metadata != null) {
        parsedMetadata = metadata;
        break;
      }
    }

    reader.closeSync();

    if (parsedMetadata == null) {
      throw StateError('Malformed APEv2 tag: cannot parse items');
    }

    return parsedMetadata;
  }

  /// Returns true when we can locate a valid APEv2 footer.
  ///
  /// Some files end with an ID3v1 tag (128 bytes) after the APEv2 footer.
  /// We therefore probe both:
  /// - EOF - 32
  /// - EOF - 128 - 32 (when ID3v1 is present)
  static bool canUserParser(RandomAccessFile reader) {
    return _findFooterOffset(reader) != null;
  }

  static int? _findFooterOffset(RandomAccessFile reader) {
    final length = reader.lengthSync();

    if (length < 32) {
      return null;
    }

    final endOffset = length - 32;
    if (_isApeFooterAt(reader, endOffset)) {
      return endOffset;
    }

    // APEv2 can coexist with ID3v1. In that case, ID3v1 is usually the last
    // structure in the file and the APE footer sits right before it.
    if (length >= 160 && _isId3v1At(reader, length - 128)) {
      final beforeId3Offset = length - 160;

      if (_isApeFooterAt(reader, beforeId3Offset)) {
        return beforeId3Offset;
      }
    }

    return null;
  }

  static bool _isApeFooterAt(RandomAccessFile reader, int offset) {
    if (offset < 0) {
      return false;
    }

    reader.setPositionSync(offset);
    final signature = reader.readSync(8);

    // We require exactly 8 bytes because the APE signature is exactly
    // "APETAGEX" (8 ASCII bytes). If fewer bytes are returned, we are too
    // close to EOF and cannot have a valid footer.
    return signature.length == 8 &&
        String.fromCharCodes(signature) == 'APETAGEX';
  }

  static bool _isId3v1At(RandomAccessFile reader, int offset) {
    if (offset < 0) {
      return false;
    }

    reader.setPositionSync(offset);
    final marker = reader.readSync(3);
    return marker.length == 3 && String.fromCharCodes(marker) == 'TAG';
  }

  ApeTagFooter _parseFooter(Uint8List footerBytes) {
    return (
      version: getUint32LE(footerBytes.sublist(8, 12)),
      size: getUint32LE(footerBytes.sublist(12, 16)),
      itemCount: getUint32LE(footerBytes.sublist(16, 20)),
      flags: getUint32LE(footerBytes.sublist(20, 24)),
    );
  }

  /// Build possible item-start offsets.
  ///
  /// Different implementations interpret the stored `size` differently
  /// (footer included/excluded), so we probe both formulas and keep the first
  /// one that decodes all declared items without crossing the footer.
  List<int> _buildCandidateStartOffsets({
    required int footerOffset,
    required int footerSize,
  }) {
    final candidates = <int>{
      footerOffset - (footerSize - 32),
      footerOffset - footerSize,
    };

    return candidates.where((offset) => offset >= 0).toList();
  }

  ApeMetadata? _tryParseItems({
    required int startOffset,
    required int footerOffset,
    required int itemCount,
  }) {
    final metadata = ApeMetadata();
    _buffer.setPositionSync(startOffset);

    for (int i = 0; i < itemCount; i++) {
      if (_buffer.fileCursor + 8 > footerOffset) {
        return null;
      }

      final valueSize = getUint32LE(_buffer.read(4));
      final itemFlags = getUint32LE(_buffer.read(4));

      final keyBytes = <int>[];
      while (_buffer.fileCursor < footerOffset) {
        final byte = _buffer.read(1)[0];
        if (byte == 0x00) {
          break;
        }
        keyBytes.add(byte);
      }

      if (keyBytes.isEmpty || _buffer.fileCursor > footerOffset) {
        return null;
      }

      if (_buffer.fileCursor + valueSize > footerOffset) {
        return null;
      }

      final value = _buffer.read(valueSize);
      final key = ascii.decode(keyBytes, allowInvalid: true);
      _parseItem(metadata, key, itemFlags, value);
    }

    return metadata;
  }

  /// Decode one APE item.
  ///
  /// Item flags use:
  /// - bit 0: read-only
  /// - bits 1..2: item type (text/binary/external/reserved)
  void _parseItem(
    ApeMetadata metadata,
    String key,
    int itemFlags,
    Uint8List value,
  ) {
    final normalizedKey = _normalizeApeKey(key);

    // APE item type is encoded in bits 1..2 (2 bits):
    // 00 = text, 01 = binary, 10 = external, 11 = reserved.
    // We right-shift by 1 to align that field, then keep only 2 bits.
    final itemType = (itemFlags >> 1) & 0x03;

    switch (itemType) {
      case 0:
        _parseTextItem(metadata, normalizedKey, value);
        break;
      case 1:
        _parseBinaryItem(metadata, normalizedKey, value);
        break;
      default:
        // External/reserved items are intentionally ignored for now.
        break;
    }
  }

  void _parseTextItem(
    ApeMetadata metadata,
    String normalizedKey,
    Uint8List value,
  ) {
    final text = utf8.decode(value, allowMalformed: true);

    // APEv2 text items can contain multiple values separated by NUL.
    final values = text.split('\u0000').where((entry) => entry.isNotEmpty);

    for (final entry in values) {
      _applyTextEntry(metadata, normalizedKey, entry);
    }
  }

  void _parseBinaryItem(
    ApeMetadata metadata,
    String normalizedKey,
    Uint8List value,
  ) {
    if (!fetchImage || !normalizedKey.startsWith('COVER_ART_')) {
      return;
    }

    // APE cover item payload is typically:
    // "<filename or description>\0<raw image bytes>"
    final separator = value.indexOf(0x00);
    final imageBytes = separator >= 0 ? value.sublist(separator + 1) : value;

    if (imageBytes.isEmpty) {
      return;
    }

    final pictureType = normalizedKey.contains('BACK')
        ? PictureType.coverBack
        : PictureType.coverFront;

    metadata.pictures.add(
      Picture(
        Uint8List.fromList(imageBytes),
        lookupMimeType('cover', headerBytes: imageBytes) ??
            'application/octet-stream',
        pictureType,
      ),
    );
  }

  String _normalizeApeKey(String key) {
    final upper = key.trim().toUpperCase();
    final normalized = upper.replaceAll(RegExp(r'\s+'), '_');

    return switch (normalized) {
      'TRACK' => 'TRACKNUMBER',
      'DISC' => 'DISCNUMBER',
      'YEAR' => 'DATE',
      'ALBUM_ARTIST' => 'ALBUMARTIST',
      'LYRIC' => 'LYRICS',
      _ => normalized,
    };
  }

  void _applyTextEntry(ApeMetadata metadata, String key, String value) {
    switch (key) {
      case 'TITLE':
        metadata.title = value;
        break;
      case 'ARTIST':
        metadata.artist = value;
        break;
      case 'ALBUM':
        metadata.album = value;
        break;
      case 'ALBUMARTIST':
        metadata.albumArtist = value;
        break;
      case 'TRACKNUMBER':
        final (number, total) = _parseNumberPair(value);
        if (number != null) {
          metadata.trackNumber = number;
        }
        if (total != null) {
          metadata.trackTotal = total;
        }
        break;
      case 'TRACKTOTAL' || 'TOTALTRACKS':
        metadata.trackTotal = int.tryParse(value) ?? metadata.trackTotal;
        break;
      case 'DISCNUMBER':
        final (number, total) = _parseNumberPair(value);
        if (number != null) {
          metadata.discNumber = number;
        }
        if (total != null) {
          metadata.discTotal = total;
        }
        break;
      case 'DISCTOTAL' || 'TOTALDISCS':
        metadata.discTotal = int.tryParse(value) ?? metadata.discTotal;
        break;
      case 'DATE':
        final parsedDate = _parseDate(value);
        if (parsedDate != null) {
          metadata.date = parsedDate;
        } else {
          metadata.unknowns[key] = value;
        }
        break;
      case 'GENRE':
        metadata.genres.add(value);
        break;
      case 'LYRICS':
        metadata.lyric = value;
        break;
      case 'COMMENT':
        metadata.comment = value;
        break;
      case 'COMPOSER':
        metadata.composer = value;
        break;
      case 'COPYRIGHT':
        metadata.copyright = value;
        break;
      case 'ENCODED_BY' || 'ENCODEDBY':
        metadata.encodedBy = value;
        break;
      case 'PERFORMER':
        metadata.performer.add(value);
        break;
      case 'LANGUAGE' || 'LANG':
        metadata.language.add(value);
        break;
      default:
        metadata.unknowns[key] = value;
        break;
    }
  }

  (int?, int?) _parseNumberPair(String value) {
    if (value.contains('/')) {
      final pair = value.split('/');
      final first = int.tryParse(pair.first);
      final second = pair.length > 1 ? int.tryParse(pair[1]) : null;
      return (first, second);
    }

    return (int.tryParse(value), null);
  }

  DateTime? _parseDate(String value) {
    final parsedDateTime = DateTime.tryParse(value);
    if (parsedDateTime != null) {
      return parsedDateTime;
    }

    if (value.contains('/')) {
      final year = int.tryParse(value.split('/').first);
      return year == null ? null : DateTime(year);
    }

    final parsedYear = int.tryParse(value);
    return parsedYear == null ? null : DateTime(parsedYear);
  }
}
