import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';

/// Parser for an ID3v1 trailer.
///
/// Protocol section: ID3v1 trailer
/// Bytes: 0..127 of the final tag
/// Layout:
/// TAG | title[30] | artist[30] | album[30] | year[4] | comment[30] | genre[1]
/// Meaning:
/// - The first three bytes identify the trailer as `TAG`.
/// - The final byte is an unsigned genre-table index; 255 means undefined.
/// Constraints:
/// - The parser consumes exactly 128 bytes supplied by the container parser.
/// - Genre indexes outside the known table are exposed as no genre.
class ID3v1Parser extends TagParser<Mp3Metadata> {
  /// Parsed ID3v1 metadata.
  final Mp3Metadata metadata = Mp3Metadata();

  /// Create an ID3v1 parser.
  ID3v1Parser({super.fetchImage = false});

  ///  Extract the part text between the [start] and the [end]
  ///  until we reach a "\x00" character
  String _extract(Uint8List tagData, int start, int end) {
    int i = start;

    while (i < end && tagData[i] != 0) {
      i++;
    }

    if (tagData[i] == 0) {
      return utf8.decode(tagData.sublist(start, i));
    }

    return latin1.decode(tagData.sublist(start, end));
  }

  @override
  Mp3Metadata parse(RandomAccessFile reader) {
    final tagData = reader.readSync(128);
    metadata.songName = _extract(tagData, 3, 33);
    metadata.leadPerformer = _extract(tagData, 33, 63);
    metadata.album = _extract(tagData, 63, 93);
    final yearAsString =
        latin1.decode(tagData.sublist(93, 97)).replaceAll('\x00', '').trim();
    metadata.year = int.tryParse(yearAsString);
    metadata.comments = [
      Comment("", _extract(tagData, 97, 127)),
    ];
    final genre = id3GenreName(tagData[127]);
    metadata.genres = genre == null ? [] : [genre];

    return metadata;
  }
}
