import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
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

    final metadata = AudioMetadata(
      title: 'Test Title',
      artist: 'Test Artist',
      album: 'Test Album',
      year: DateTime(2023),
      file: File(""),
    );

    Id3v1Writer().write(writer, metadata);

    final fileBytes = tempFile.readAsBytesSync();
    final id3v1Bytes = fileBytes.sublist(fileBytes.length - 128);

    // 7. Assert that the written bytes match the expected bytes
    expect(id3v1Bytes.sublist(0, 3), equals("TAG".codeUnits));
    expect(id3v1Bytes.sublist(3, 33),
        equals(metadata.title!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(33, 63),
        equals(metadata.artist!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(63, 93),
        equals(metadata.album!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(93, 97),
        equals(metadata.year!.year.toString().codeUnits));
    expect(id3v1Bytes.sublist(97, 127), equals(List.filled(30, 0)));
    expect(id3v1Bytes[127], equals(255));

    tempFile.deleteSync();
  });
}
