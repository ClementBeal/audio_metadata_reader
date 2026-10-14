import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('returns embedded WAV artwork when getImage is true', () {
    final File track = File('test/wav/track_id3_cover.wav');
    final AudioMetadata metadata = readMetadata(track, getImage: true);

    expect(metadata.title, equals('WAV cover fixture'));
    expect(metadata.sampleRate, equals(44100));
    expect(metadata.bitrate, equals(705600));
    expect(metadata.duration, equals(const Duration(milliseconds: 100)));
    expect(metadata.pictures, hasLength(1));
    final Picture picture = metadata.pictures.single;
    expect(
        picture.bytes, equals(File('test/data/cover.png').readAsBytesSync()));
    expect(picture.mimetype, equals('image/png'));
    expect(picture.pictureType, equals(PictureType.coverFront));
  });

  test('returns no pictures for a WAV without artwork when getImage is true',
      () {
    final AudioMetadata metadata =
        readMetadata(File('test/wav/track.wav'), getImage: true);

    expect(metadata.pictures, isEmpty);
    expect(metadata.title, equals('Le Crou ne mourra jamais (intro)'));
  });

  test("Parse WAV file without the cover", () {
    final track = File('./test/wav/track.wav');
    final result = readMetadata(track, getImage: false);

    expect(result.sampleRate, equals(48000));
    expect(result.bitrate, equals(768000));
    expect(result.album, equals("Stupeflip"));
    expect(result.artist, equals("Stupeflip"));
    expect(result.discNumber, isNull);
    expect(result.title, equals("Le Crou ne mourra jamais (intro)"));
    expect(result.trackNumber, isNull);
    expect(result.year, equals(DateTime(2003, 1, 8)));
    expect(result.duration!.inSeconds, closeTo(5, 0.1));
    expect(result.totalDisc, isNull);
    expect(result.lyrics, isNull);
    expect(result.trackTotal, isNull);
    expect(result.genres.length, equals(1));
    expect(result.genres[0], equals("Lol"));
  });

  test("Parse WAV file with embedded ID3 chunk", () {
    final track = File('./test/wav/track_id3.wav');
    expect(track.existsSync(), isTrue);

    final result = readMetadata(track, getImage: false);

    // This fixture contains both LIST/INFO and ID3 metadata.
    // We expect ID3 to win when both define the same field.
    expect(result.title, equals("WAV ID3 Chunk Title"));
    expect(result.artist, equals("WAV ID3 Chunk Artist"));
    expect(result.album, equals("WAV ID3 Chunk Album"));
    expect(result.trackNumber, equals(7));
    expect(result.year, equals(DateTime(2014)));
    expect(result.genres, contains("Rock"));
    expect(result.sampleRate, equals(44100));
    expect(result.bitrate, equals(1411200));
    expect(result.duration?.inSeconds, closeTo(1, 0.1));
  });
}
