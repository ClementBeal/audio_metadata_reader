import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse FLAC file that does not contain a cover", () {
    final track = File('./test/flac/no_picture.flac');
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
  });
  test("Parse FLAC file that contains a cover", () {
    final track = File('./test/flac/no_picture.flac');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });
}
