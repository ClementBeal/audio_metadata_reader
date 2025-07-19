import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse APE file that does not contain a cover", () {
    final track = File('./test/ape/track.ape');
    final result = readMetadata(track, getImage: true);
    print(result.toString());
    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    // expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(12));
    // expect(result.duration, equals(Duration(seconds: 0)));
    expect(result.totalDisc, equals(0));
    expect(result.lyrics, equals("this is lyric"));
    expect(result.trackTotal, equals(0));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Pop"));
    expect(result.pictures.length, 1);
    expect(result.pictures.first.pictureType, PictureType.coverFront);
  });
}
