import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

// Fixtures are generated once with ffmpeg; tests do not require ffmpeg.
// Run from the repository root:
// ffmpeg -f lavfi -i anullsrc=r=48000:cl=mono -t 1 -c:a flac
//   -metadata DATE=unknown/2019 -metadata TITLE=Title -metadata ARTIST=Artist
//   -metadata ALBUM=Album test/flac/malformed_date.flac
// ffmpeg -f lavfi -i anullsrc=r=48000:cl=stereo -t 1 -c:a vorbis -strict -2
//   -metadata DATE=unknown/2019 -metadata TITLE=Title -metadata ARTIST=Artist
//   -metadata ALBUM=Album test/ogg/malformed_date.ogg
void main() {
  for (final String extension in ['flac', 'ogg']) {
    test('readMetadata keeps other $extension metadata with a malformed DATE',
        () {
      final File track = File('test/$extension/malformed_date.$extension');

      final AudioMetadata metadata = readMetadata(track);

      expect(metadata.year, isNull);
      expect(metadata.title, equals('Title'));
      expect(metadata.artist, equals('Artist'));
      expect(metadata.album, equals('Album'));
      expect(metadata.duration, equals(const Duration(seconds: 1)));
    });

    test(
        'readAllMetadata keeps other $extension metadata with a malformed DATE',
        () {
      final File track = File('test/$extension/malformed_date.$extension');

      final VorbisMetadata metadata = readAllMetadata(track) as VorbisMetadata;

      expect(metadata.date, isEmpty);
      expect(metadata.title, equals(['Title']));
      expect(metadata.artist, equals(['Artist']));
      expect(metadata.album, equals(['Album']));
      expect(metadata.duration, equals(const Duration(seconds: 1)));
    });
  }
}
