import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('reads WebM audio metadata without loading cover images', () {
    final track = File('test/webm/track.webm');

    final result = readMetadata(track, getImage: false);

    expect(result.title, equals('WebM test title'));
    expect(result.artist, equals('WebM test artist'));
    expect(result.album, equals('WebM test album'));
    expect(result.genres, equals(['Electronic']));
    expect(result.language, equals('fra'));
    expect(result.trackNumber, equals(2));
    expect(result.trackTotal, equals(9));
    expect(result.discNumber, equals(1));
    expect(result.totalDisc, equals(2));
    expect(result.year, equals(DateTime(2024)));
    expect(result.sampleRate, equals(48000));
    expect(result.duration?.inMilliseconds, closeTo(1258, 10));
    expect(result.pictures, isEmpty);
  });

  test('detects WebM content when a media manager named it .mp4', () {
    final directory = Directory.systemTemp.createTempSync('webm_mp4_test_');
    addTearDown(() => directory.deleteSync(recursive: true));

    final mislabeled = File('${directory.path}/track.mp4')
      ..writeAsBytesSync(File('test/webm/track.webm').readAsBytesSync());

    final result = readMetadata(mislabeled, getImage: false);

    expect(result.title, equals('WebM test title'));
    expect(result.artist, equals('WebM test artist'));
    expect(result.sampleRate, equals(48000));
  });

  test('returns format-specific Matroska tags as VorbisMetadata', () {
    final metadata = readAllMetadata(
      File('test/webm/track.webm'),
      getImage: false,
    );

    expect(metadata, isA<VorbisMetadata>());
    final vorbis = metadata as VorbisMetadata;
    expect(vorbis.title, equals(['WebM test title']));
    expect(vorbis.artist, equals(['WebM test artist']));
    expect(vorbis.trackNumber, equals([2]));
    expect(vorbis.trackTotal, equals(9));
    expect(vorbis.discNumber, equals(1));
    expect(vorbis.discTotal, equals(2));
  });

  test('skips Matroska cover bytes unless images are requested', () {
    final track = File('test/webm/track_with_cover.mkv');

    final withoutImage = readMetadata(track, getImage: false);
    expect(withoutImage.pictures, isEmpty);

    final withImage = readMetadata(track, getImage: true);
    expect(withImage.pictures, hasLength(1));
    expect(withImage.pictures.single.mimetype, equals('image/png'));
    expect(
      withImage.pictures.single.bytes,
      equals(File('test/data/cover.png').readAsBytesSync()),
    );
  });

  test('throws a metadata error for truncated EBML content', () {
    final directory = Directory.systemTemp.createTempSync('webm_invalid_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final truncated = File('${directory.path}/truncated.webm')
      ..writeAsBytesSync(
        Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x81, 0x00]),
      );

    expect(
      () => readMetadata(truncated, getImage: false),
      throwsA(isA<MetadataParserException>()),
    );
  });
}
