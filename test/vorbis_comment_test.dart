import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';
import 'package:test/test.dart';

void main() {
  final List<int> invalidPicture = <int>[
    ...ascii.encode('METADATA_BLOCK_PICTURE='),
    0xFF,
    0xFE,
    0xC3,
  ];

  for (final bool typed in <bool>[true, false]) {
    final String kind = typed ? 'Uint8List' : 'List<int>';

    List<int> bytes(List<int> value) =>
        typed ? Uint8List.fromList(value) : List<int>.of(value);

    test('skips a non UTF-8 picture value without fetching images ($kind)', () {
      final VorbisMetadata metadata = VorbisMetadata();

      parseVorbisComment(bytes(utf8.encode('TITLE=Été')), metadata,
          fetchImage: false);
      parseVorbisComment(bytes(invalidPicture), metadata, fetchImage: false);
      parseVorbisComment(
          bytes(<int>[...ascii.encode('metadata_block_picture='), 0xFF]),
          metadata,
          fetchImage: false);
      parseVorbisComment(bytes(utf8.encode('ARTIST=Artist=Name')), metadata,
          fetchImage: false);

      expect(metadata.title, <String>['Été']);
      expect(metadata.artist, <String>['Artist=Name']);
      expect(metadata.pictures, isEmpty);
      expect(metadata.unknowns, isEmpty);
    });

    test('still rejects a non UTF-8 picture value when fetching images ($kind)',
        () {
      expect(
        () => parseVorbisComment(bytes(invalidPicture), VorbisMetadata(),
            fetchImage: true),
        throwsFormatException,
      );
    });

    test('throws a RangeError for a comment without a separator ($kind)', () {
      expect(
        () => parseVorbisComment(bytes(ascii.encode('TITLE')), VorbisMetadata(),
            fetchImage: false),
        throwsRangeError,
      );
    });
  }
}
