import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('readAllMetadata supports WAV/RIFF files', () {
    final track = File('./test/wav/track.wav');
    final metadata = readAllMetadata(track, getImage: false);

    expect(metadata, isA<RiffMetadata>());

    final riffMetadata = metadata as RiffMetadata;
    expect(riffMetadata.title, equals('Le Crou ne mourra jamais (intro)'));
    expect(riffMetadata.artist, equals('Stupeflip'));
  });

  test('updateMetadata works on WAV files through readAllMetadata', () {
    final tempDir = Directory.systemTemp.createTempSync();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final target = File('${tempDir.path}/track.wav');
    target.writeAsBytesSync(File('test/wav/track.wav').readAsBytesSync());

    updateMetadata(target, (metadata) {
      (metadata as RiffMetadata).title = 'Updated via updateMetadata';
    });

    final updated = readAllMetadata(target, getImage: false) as RiffMetadata;
    expect(updated.title, equals('Updated via updateMetadata'));
  });
}
