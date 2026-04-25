import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:audio_metadata_reader/src/writers/riff_writer.dart';
import 'package:test/test.dart';

void main() {
  test('RiffWriter writes to the target file instead of a fixed filename', () {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));

    final target = File('${dir.path}/track.wav');
    target.writeAsBytesSync(File('test/wav/track.wav').readAsBytesSync());

    final fixedOutput = File('a_new.wav');
    if (fixedOutput.existsSync()) {
      fixedOutput.deleteSync();
    }

    final metadata = RiffMetadata(
      title: 'Updated WAV title',
    );

    RiffWriter().write(target, metadata);

    expect(target.existsSync(), isTrue);
    expect(fixedOutput.existsSync(), isFalse);

    final parsedMetadata = readMetadata(target, getImage: false);
    expect(parsedMetadata.title, equals('Updated WAV title'));
  });
}
