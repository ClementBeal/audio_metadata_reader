import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:audio_metadata_reader/src/writers/id3v4_writer.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group(
    "Write ID3v4 header",
    () {
      test("Empty body, the most basic header", () {
        final writer = Id3v4Writer();

        final file = createTemporaryFile("test.mp3");

        writer.write(file, Mp3Metadata());

        final readResult = ByteData.sublistView(file.openSync().readSync(10));

        expect(readResult.getUint8(0), equals(0x49));
        expect(readResult.getUint8(1), equals(0x44));
        expect(readResult.getUint8(2), equals(0x33));

        expect(readResult.getUint8(3), equals(4));
        expect(readResult.getUint8(4), equals(0));
        expect(readResult.getUint8(5), equals(0));
        expect(readResult.getUint32(6), equals(0));
      });
    },
  );
}
