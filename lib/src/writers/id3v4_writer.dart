import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';

class Id3v4Writer {
  void write(File file, Mp3Metadata metadata) {
    // final writer = file.();

    final builder = BytesBuilder();

    _writeHeader(builder);

    file.writeAsBytesSync(builder.toBytes());
  }

  void _writeHeader(BytesBuilder builder) {
    // ID3
    builder.addByte(0x49);
    builder.addByte(0x44);
    builder.addByte(0x33);

    // the ID3 version For us, only 4
    builder.addByte(4);
    // the version is always followed by a 0x00 byte
    builder.addByte(0);

    // write flags
    builder.addByte(0);

    // write ID3 metadata size
    builder.add(intToUint32(0));
  }
}
