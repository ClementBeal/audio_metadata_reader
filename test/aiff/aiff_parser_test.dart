import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('Parse AIFF metadata with readMetadata', () {
    final track = File('test/aiff/track.aiff');
    expect(track.existsSync(), isTrue);

    final result = readMetadata(track, getImage: false);

    expect(result.title, equals('Simple title'));
    expect(result.sampleRate, equals(44100));
    expect(result.bitrate, equals(176400));
    expect(result.duration?.inSeconds, equals(1));
    expect(result.lyrics, isNull);
  });

  test('readAllMetadata returns a RIFF-like metadata object for AIFF', () {
    final track = File('test/aiff/track.aiff');
    expect(track.existsSync(), isTrue);

    final metadata = readAllMetadata(track, getImage: false);
    expect(metadata, isA<RiffMetadata>());

    final aiffMetadata = metadata as RiffMetadata;
    expect(aiffMetadata.title, equals('Simple title'));
    expect(aiffMetadata.comment, equals('Test note'));
    expect(aiffMetadata.copyright, equals('2026 Test'));
  });

  test('AiffParser accepts AIFF and AIFC form types', () {
    final aiffReader = File('test/aiff/minimal.aiff').openSync();
    final aifcReader = File('test/aiff/minimal.aifc').openSync();

    expect(AiffParser.canUserParser(aiffReader), isTrue);
    expect(AiffParser.canUserParser(aifcReader), isTrue);

    aiffReader.closeSync();
    aifcReader.closeSync();
  });

  test('Parse AIFF ID3 chunk with readMetadata', () {
    final track = File('test/aiff/track_id3.aiff');
    expect(track.existsSync(), isTrue);

    final result = readMetadata(track, getImage: false);

    expect(result.title, equals('ID3 Chunk Title'));
    expect(result.artist, equals('ID3 Chunk Artist'));
    expect(result.album, equals('ID3 Chunk Album'));
    expect(result.trackNumber, equals(7));
    expect(result.year, equals(DateTime(2014)));
    expect(result.genres, contains('Rock'));
    expect(result.sampleRate, equals(44100));
    expect(result.bitrate, equals(176400));
  });

  test('readAllMetadata exposes AIFF ID3 values in RiffMetadata', () {
    final track = File('test/aiff/track_id3.aiff');
    expect(track.existsSync(), isTrue);

    final metadata = readAllMetadata(track, getImage: false);
    expect(metadata, isA<RiffMetadata>());

    final aiffMetadata = metadata as RiffMetadata;
    expect(aiffMetadata.title, equals('ID3 Chunk Title'));
    expect(aiffMetadata.artist, equals('ID3 Chunk Artist'));
    expect(aiffMetadata.album, equals('ID3 Chunk Album'));
    expect(aiffMetadata.trackNumber, equals(7));
    expect(aiffMetadata.year, equals(DateTime(2014)));
    expect(aiffMetadata.genre, equals('Rock'));
    expect(aiffMetadata.publisher, equals('ID3 Chunk Publisher'));
    expect(aiffMetadata.copyright, equals('ID3 Chunk Copyright'));
  });
}
