import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse MP4 file without the cover", () {
    final track = File('./test/mp4/track.m4a');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(
      result.duration!.inMicroseconds -
          Duration(microseconds: 1021333).inMicroseconds,
      lessThanOrEqualTo(1000000),
    );
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
  });
  test("Parse MP4 file and the cover", () {
    final track = File('./test/mp4/track.m4a');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Complex date", () {
    final track = File('./test/mp4/ahah.m4a');
    final result = readMetadata(track, getImage: true);

    expect(result.title, "Sexy Ladies (Remix) [feat. 50 Cent]");
    expect(result.album, "FutureSex/LoveSounds (Deluxe Edition)");
    expect(result.artist, "Justin Timberlake");
    expect(result.year, DateTime.utc(2006, 9, 12));
    expect(result.trackNumber, 15);
    expect(result.trackTotal, 15);
  });

  test("Should work with .mov file", () {
    final track = File('./test/mp4/track.mov');
    final result = readMetadata(track, getImage: false);

    expect(result.title, "Blue Test Pattern");
    expect(result.artist, "FFmpeg Generator");
    expect(result.year, (DateTime(2023, 10, 27)));
  });
}
