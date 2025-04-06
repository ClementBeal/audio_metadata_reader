import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse MP3 file without the cover", () {
    final track = File('./test/mp3/track.mp3');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(44100));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(result.duration!.inMilliseconds, closeTo(1130, 10));
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
  });

  test("Parse MP3 file and the cover", () {
    final track = File('./test/mp3/track.mp3');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Check if we skip correctly the images", () {
    final track = File("./test/mp3/caress-your-soul-cleaned.mp3");
    final result = readMetadata(track, getImage: false);

    expect(result.pictures.length, 0);
    expect(result.album, "Caress Your Soul");
    expect(result.title, "How to Fly");
    expect(result.artist, "Sticky Fingers");
    expect(result.year, DateTime(2013));
    expect(
        result.duration, Duration(minutes: 3, seconds: 22, milliseconds: 240));
    expect(result.sampleRate, 44100);
  });

  test("Parses from truncated mp3 file", () {
    // The caress-your-soul-truncated-cleaned.mp3 file is truncated
    // immediately before the Xing header. We should still be able
    // to read the ID3 tag data.
    final track = File("./test/mp3/caress-your-soul-cleaned-truncated.mp3");
    final result = readMetadata(track, getImage: false);
    expect(result.pictures.length, 0);
    expect(result.album, "Caress Your Soul");
    expect(result.title, "How to Fly");
    expect(result.artist, "Sticky Fingers");
    expect(result.year, DateTime(2013));
    expect(result.sampleRate, 44100);
  });

  test("Round duration to microseconds", () {
    final track = File("./test/mp3/generated_under_one_second.mp3");
    final result = readMetadata(track, getImage: false);
    expect(result.pictures.length, 0);
    expect(result.duration, isNotNull);
    expect(result.duration!.inMilliseconds, closeTo(310, 5));
  });
}
