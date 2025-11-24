import 'dart:typed_data';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/pad_bit.dart';
import 'package:audio_metadata_reader/src/writers/id3v1_writer.dart';
import 'package:test/test.dart';

void main() {
  test('Id3v1Writer writes ID3v1 tag correctly', () async {
    final originalBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final metadata = Mp3Metadata()
      ..songName = 'Test Title'
      ..bandOrOrchestra = 'Test Artist'
      ..album = 'Test Album'
      ..year = 2023;

    final fileBytes = await ID3v1Writer().writeToBytes(originalBytes, metadata);
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
  });
}
