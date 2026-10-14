import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';
import 'package:test/test.dart';

void main() {
  for (final String value in ['unknown/2019', '/2019', 'circa/1999']) {
    test('ignores malformed DATE=$value and keeps an existing date', () {
      final VorbisMetadata metadata = VorbisMetadata();

      parseVorbisComment('DATE=2018'.codeUnits, metadata, fetchImage: false);
      parseVorbisComment('DATE=$value'.codeUnits, metadata, fetchImage: false);

      expect(metadata.date, equals([DateTime(2018)]));
    });
  }

  final Map<String, DateTime> validDates = {
    '2019': DateTime(2019),
    '2019-04-01': DateTime(2019, 4, 1),
    '2019/2020': DateTime(2019),
  };

  for (final MapEntry<String, DateTime> entry in validDates.entries) {
    test('returns the date for DATE=${entry.key}', () {
      final VorbisMetadata metadata = VorbisMetadata();

      parseVorbisComment('DATE=${entry.key}'.codeUnits, metadata,
          fetchImage: false);

      expect(metadata.date, equals([entry.value]));
    });
  }

  test('Parse LANGUAGE Vorbis comment into dedicated field', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('LANGUAGE=ja'.codeUnits, metadata, fetchImage: false);

    expect(metadata.language, equals(['ja']));
    expect(metadata.unknowns.containsKey('LANGUAGE'), isFalse);
  });

  test('Parse LANG Vorbis comment alias into dedicated field', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('LANG=zh-CN'.codeUnits, metadata, fetchImage: false);

    expect(metadata.language, equals(['zh-CN']));
    expect(metadata.unknowns.containsKey('LANG'), isFalse);
  });

  test('keeps ARTIST and ALBUMARTIST in separate fields', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('ARTIST=Track artist'.codeUnits, metadata,
        fetchImage: false);
    parseVorbisComment('ALBUMARTIST=Album artist'.codeUnits, metadata,
        fetchImage: false);

    expect(metadata.artist, equals(['Track artist']));
    expect(metadata.albumArtist, equals(['Album artist']));
  });

  test('accepts the ALBUM_ARTIST spelling used by some taggers', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('ALBUM_ARTIST=Album artist'.codeUnits, metadata,
        fetchImage: false);

    expect(metadata.albumArtist, equals(['Album artist']));
    expect(metadata.unknowns.containsKey('ALBUM_ARTIST'), isFalse);
  });

  test('LENGTH does not overwrite duration from STREAMINFO', () {
    final metadata = VorbisMetadata()..duration = const Duration(seconds: 236);

    parseVorbisComment('LENGTH=236'.codeUnits, metadata, fetchImage: false);

    expect(metadata.duration, const Duration(seconds: 236));
  });
}
