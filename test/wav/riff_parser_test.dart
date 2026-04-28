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
    expect(result.bitrate, equals(176400));
    expect(result.duration?.inSeconds, closeTo(1, 0.1));
  });
}
