import 'dart:io';

import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse WAV file without the cover", () {
    final track = File('./test/wav/track.wav');
    final result = readMetadata(track, getImage: false);

    expect(result.sampleRate, equals(48000));
    expect(result.bitrate, equals(96000));
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
}
