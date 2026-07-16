import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart';

/// Serializes APEv2 metadata without changing the audio payload.
///
/// APEv2 tag layout (all integer fields are unsigned little-endian):
///
/// Protocol section: APEv2 item
/// Bytes: variable
/// Layout:
/// AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA
/// BBBBBBBB BBBBBBBB BBBBBBBB BBBBBBBB
/// CCCCCCCC ... 00000000 DDDDDDDD ...
/// Meaning:
/// - A: value size, 32 bits, little-endian.
/// - B: item flags, 32 bits, little-endian. Bits 1..2 contain the item type:
///   `00` text and `01` binary. This writer only emits those two types.
/// - C: ASCII item key, followed by one NUL byte. A key must be 2..255
///   printable ASCII bytes; NUL and non-ASCII keys are invalid.
/// - D: value bytes. Text is UTF-8; cover art is `filename\0image-bytes`.
///
/// Protocol section: APEv2 footer
/// Bytes: 0..31
/// Layout:
/// AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA AAAAAAAA
/// BBBBBBBB BBBBBBBB BBBBBBBB BBBBBBBB CCCCCCCC CCCCCCCC CCCCCCCC CCCCCCCC
/// DDDDDDDD DDDDDDDD DDDDDDDD DDDDDDDD EEEEEEEE EEEEEEEE EEEEEEEE EEEEEEEE
/// FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF 00000000 00000000 00000000 00000000
/// 00000000 00000000 00000000 00000000
/// Meaning:
/// - A: ASCII `APETAGEX` signature, 8 bytes.
/// - B: version 2000, 32-bit little-endian (APEv2.000).
/// - C: complete tag size, including items and this footer, 32-bit LE.
/// - D: item count, 32-bit LE.
/// - E: footer flags. This writer uses zero because it emits no optional header.
/// - F: eight reserved bytes, all zero.
/// Constraints:
/// - APEv2 has no CRC or checksum.
/// - The footer is immediately before an optional trailing ID3v1 tag.
/// - Rewrites remove a preceding APEv2 header when one is physically present,
///   even if its footer flags are stale.
class ApeWriter extends BaseMetadataWriter<ApeMetadata> {
  static const _footerLength = 32;
  static const _id3v1Length = 128;
  static const _apeSignature = 'APETAGEX';

  @override
  void write(File file, ApeMetadata metadata) {
    final original = file.readAsBytesSync();
    final layout = _splitExistingTag(original);
    final tag = _buildTag(metadata);

    // Construct the replacement in one contiguous buffer. This avoids writing
    // the file in-place: if the new tag is a different size, in-place writes
    // can leave bytes from the old tag behind or overwrite the ID3v1 trailer.
    final output = BytesBuilder(copy: false)
      ..add(original.sublist(0, layout.audioEnd))
      ..add(tag)
      ..add(original.sublist(layout.id3v1Start));

    file.writeAsBytesSync(output.takeBytes());
  }

  _ExistingTagLayout _splitExistingTag(Uint8List bytes) {
    var id3v1Start = bytes.length;
    if (bytes.length >= _id3v1Length &&
        _hasAsciiAt(bytes, bytes.length - _id3v1Length, 'TAG')) {
      id3v1Start = bytes.length - _id3v1Length;
    }

    final footerOffset = id3v1Start - _footerLength;
    if (footerOffset < 0 || !_hasAsciiAt(bytes, footerOffset, _apeSignature)) {
      return _ExistingTagLayout(audioEnd: id3v1Start, id3v1Start: id3v1Start);
    }

    final tagSize =
        getUint32LE(bytes.sublist(footerOffset + 12, footerOffset + 16));
    // The minimum valid tag is exactly the footer. Treat corrupt values as
    // audio bytes instead of deleting data based on an untrusted length.
    if (tagSize < _footerLength || tagSize > footerOffset + _footerLength) {
      return _ExistingTagLayout(audioEnd: id3v1Start, id3v1Start: id3v1Start);
    }

    var tagStart = footerOffset - (tagSize - _footerLength);
    if (tagStart < 0) {
      return _ExistingTagLayout(audioEnd: id3v1Start, id3v1Start: id3v1Start);
    }

    // APEv2 headers are optional. The footer flag is not trusted here because
    // taggers in the wild can leave it stale; the actual signature is the
    // authoritative signal. The writer emits footer-only tags after rewrite.
    // Most encoders exclude the header from `tagSize`, placing it 32 bytes
    // before the first item. A few include it, placing it at `tagStart`.
    final headerOffset = tagStart - _footerLength;
    if (_hasAsciiAt(bytes, tagStart, _apeSignature)) {
      // `tagSize` included the header, so tagStart already points to it.
    } else if (headerOffset >= 0 &&
        _hasAsciiAt(bytes, headerOffset, _apeSignature)) {
      tagStart = headerOffset;
    }

    return _ExistingTagLayout(audioEnd: tagStart, id3v1Start: id3v1Start);
  }

  Uint8List _buildTag(ApeMetadata metadata) {
    final items = BytesBuilder(copy: false);
    var itemCount = 0;

    void addText(String key, String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      _writeItem(items,
          key: key, flags: 0, value: Uint8List.fromList(utf8.encode(value)));
      itemCount += 1;
    }

    void addTextValues(String key, Iterable<String> values) {
      for (final value in values) {
        addText(key, value);
      }
    }

    addText('TITLE', metadata.title);
    addText('ARTIST', metadata.artist);
    addText('ALBUM', metadata.album);
    addText('ALBUMARTIST', metadata.albumArtist);
    addText('LYRICS', metadata.lyric);
    addText('COMMENT', metadata.comment);
    addText('COMPOSER', metadata.composer);
    addText('COPYRIGHT', metadata.copyright);
    addText('ENCODEDBY', metadata.encodedBy);
    addText('DATE', _formatDate(metadata.date));
    addText(
        'TRACK', _formatNumberPair(metadata.trackNumber, metadata.trackTotal));
    if (metadata.trackNumber == null) {
      addText('TRACKTOTAL', metadata.trackTotal?.toString());
    }
    addText('DISC', _formatNumberPair(metadata.discNumber, metadata.discTotal));
    if (metadata.discNumber == null) {
      addText('DISCTOTAL', metadata.discTotal?.toString());
    }
    addTextValues('GENRE', metadata.genres);
    addTextValues('LANGUAGE', metadata.language);
    addTextValues('PERFORMER', metadata.performer);

    // Known fields are emitted first. An unknown key that collides with one of
    // them is skipped, otherwise parsing the rewritten tag would depend on the
    // order of duplicate values.
    for (final entry in metadata.unknowns.entries) {
      if (!_knownKeys.contains(entry.key.toUpperCase())) {
        addText(entry.key, entry.value);
      }
    }

    for (final picture in metadata.pictures) {
      final key = switch (picture.pictureType) {
        PictureType.coverFront => 'Cover Art (Front)',
        PictureType.coverBack => 'Cover Art (Back)',
        _ => null,
      };
      if (key == null || picture.bytes.isEmpty) {
        continue;
      }

      final value = BytesBuilder(copy: false)
        ..add(ascii.encode(_coverFilename(picture.mimetype)))
        ..addByte(0)
        ..add(picture.bytes);
      _writeItem(items, key: key, flags: 0x00000002, value: value.takeBytes());
      itemCount += 1;
    }

    final itemBytes = items.takeBytes();
    final footer = BytesBuilder(copy: false)
      ..add(ascii.encode(_apeSignature))
      ..add(intToUint32LE(2000))
      ..add(intToUint32LE(itemBytes.length + _footerLength))
      ..add(intToUint32LE(itemCount))
      ..add(intToUint32LE(0))
      ..add(Uint8List(8));

    return Uint8List.fromList(<int>[...itemBytes, ...footer.takeBytes()]);
  }

  void _writeItem(
    BytesBuilder target, {
    required String key,
    required int flags,
    required Uint8List value,
  }) {
    final keyBytes = ascii.encode(key);
    if (!_isValidKey(keyBytes)) {
      throw ArgumentError.value(
        key,
        'key',
        'An APEv2 item key must contain 2..255 printable ASCII characters.',
      );
    }

    target
      ..add(intToUint32LE(value.length))
      ..add(intToUint32LE(flags))
      ..add(keyBytes)
      ..addByte(0)
      ..add(value);
  }

  bool _isValidKey(List<int> keyBytes) {
    return keyBytes.length >= 2 &&
        keyBytes.length <= 255 &&
        keyBytes.every((byte) => byte >= 0x20 && byte <= 0x7e);
  }

  bool _hasAsciiAt(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  String? _formatDate(DateTime? date) {
    if (date == null) {
      return null;
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String? _formatNumberPair(int? number, int? total) {
    if (number == null) {
      return null;
    }
    return total == null ? '$number' : '$number/$total';
  }

  String _coverFilename(String mimeType) {
    return switch (mimeType) {
      'image/jpeg' => 'cover.jpg',
      'image/png' => 'cover.png',
      'image/webp' => 'cover.webp',
      _ => 'cover.bin',
    };
  }

  static const _knownKeys = <String>{
    'TITLE',
    'ARTIST',
    'ALBUM',
    'ALBUMARTIST',
    'LYRICS',
    'COMMENT',
    'COMPOSER',
    'COPYRIGHT',
    'ENCODEDBY',
    'DATE',
    'TRACK',
    'TRACKTOTAL',
    'DISC',
    'DISCTOTAL',
    'GENRE',
    'LANGUAGE',
    'PERFORMER',
  };
}

class _ExistingTagLayout {
  const _ExistingTagLayout({
    required this.audioEnd,
    required this.id3v1Start,
  });

  final int audioEnd;
  final int id3v1Start;
}
