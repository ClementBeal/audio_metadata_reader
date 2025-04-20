import 'dart:io';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/pad_bit.dart';
import 'package:audio_metadata_reader/src/writers/id3v1_writer.dart';
import 'package:test/test.dart';

void main() {
  test('Id3v1Writer writes ID3v1 tag correctly', () {
    final dir = Directory.systemTemp.createTempSync();

    final tempFile = File('${dir.path}/test_audio.mp3');
    tempFile.createSync();
    final writer = tempFile.openSync(mode: FileMode.write);

    writer.writeFromSync([1, 2, 3, 4, 5]);
    writer.closeSync();

    final metadata = Mp3Metadata()
      ..songName = 'Test Title'
      ..bandOrOrchestra = 'Test Artist'
      ..album = 'Test Album'
      ..year = 2023;

    ID3v1Writer().write(tempFile, metadata);

    final fileBytes = tempFile.readAsBytesSync();
    final id3v1Bytes = fileBytes.sublist(fileBytes.length - 128);

    // 7. Assert that the written bytes match the expected bytes
    expect(id3v1Bytes.sublist(0, 3), equals("TAG".codeUnits));
    expect(id3v1Bytes.sublist(3, 33),
        equals(metadata.songName!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(33, 63),
        equals(metadata.bandOrOrchestra!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(63, 93),
        equals(metadata.album!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(93, 97),
        equals(metadata.year!.toString().codeUnits));
    expect(id3v1Bytes.sublist(97, 127), equals(List.filled(30, 0)));
    expect(id3v1Bytes[127], equals(255));

    tempFile.deleteSync();
  });
}
