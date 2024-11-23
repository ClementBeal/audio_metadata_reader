import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';

class TagHeader {
  final int majorVersion;
  final int minorVersion;
  final int size;
  final bool hasFooter;
  final bool hasExtendedHeader;

  TagHeader(this.majorVersion, this.minorVersion, this.size, this.hasFooter,
      this.hasExtendedHeader);

  int get version => majorVersion * 100 + minorVersion;
}

class Id3v4Writer {
  void write(File file, Mp3Metadata metadata) {
    // check if the file has an ID3 metadata
    final size = file.lengthSync();

    final builder = BytesBuilder();

    if (metadata.songName != null) {
      _writeFrame(builder, "TIT2", metadata.songName!);
    }

    final finalBuilder = BytesBuilder();
    _writeHeader(finalBuilder, builder.length);
    finalBuilder.add(builder.toBytes());

    if (size == 0) {
      file.writeAsBytesSync(finalBuilder.toBytes());
    } else {
      final oldData = file.readAsBytesSync();
      file.writeAsBytesSync([
        ...finalBuilder.toBytes(),
        ...oldData,
      ]);
    }
  }

  void _writeFrame(BytesBuilder builder, String frameId, String data) {
    builder.add(frameId.codeUnits);

    builder.add(_encodeSynchsafeInteger(data.length + 1));
    // flags
    builder.add([0, 0]);

    builder.addByte(0x03);
    builder.add(utf8.encode(data));
  }

  Uint8List _encodeSynchsafeInteger(int value) {
    return Uint8List.fromList([
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ]);
  }

  void _writeHeader(BytesBuilder builder, int dataSize) {
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
    builder.add(_encodeSynchsafeInteger(dataSize));
  }
}
