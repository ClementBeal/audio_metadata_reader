import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test("Parse OPUS file without the cover", () {
    final track = File('./test/opus/track.opus');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(result.duration, equals(Duration(seconds: 1)));
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
    expect(result.language, isNull);
  });
  test("Parse OPUS file and the cover", () {
    final track = File('./test/opus/track.opus');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Correct duration", () {
    final track = File('./test/opus/real_track_extract.opus');
    final result = readMetadata(track);

    expect(result.duration, Duration(minutes: 3, seconds: 15));
  });

  test("Correct duration of an OPUS file encoded at 16 kHz", () {
    final File track = File('./test/opus/track_16khz.opus');
    final AudioMetadata result = readMetadata(track);

    expect(result.duration, equals(const Duration(milliseconds: 1375)));
  });

  test("LENGTH comment does not overwrite the OPUS duration", () {
    final File track = File('./test/opus/track_length_tag.opus');
    final AudioMetadata result = readMetadata(track);

    expect(result.duration, equals(const Duration(milliseconds: 1375)));
  });
}
