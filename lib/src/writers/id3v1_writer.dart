import 'dart:io';
import 'dart:convert';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart'; // For encoding strings to bytes

class ID3v1Writer extends BaseMetadataWriter<Mp3Metadata> {
  @override
  void write(File file, Mp3Metadata metadata) {
    final reader = file.openSync(mode: FileMode.append);
    // 1. Seek to the ID3v1 tag position (128 bytes from the end)
    reader.setPositionSync(reader.lengthSync());

    // 2. Write "TAG" identifier
    reader.writeStringSync("TAG");

    // 3. Helper function for writing fixed-length strings
    void writeFixedString(String str, int length) {
      List<int> bytes;
      if (str.length > length) {
        bytes = utf8.encode(str.substring(0, length)); // Truncate if too long
      } else {
        bytes = utf8.encode(str);
        bytes += List.filled(
            length - bytes.length, 0); // Pad with null bytes if too short
      }
      reader.writeFromSync(bytes);
    }

    // 4. Write title, artist, album (fixed-length 30)
    writeFixedString(metadata.songName ?? "", 30);
    writeFixedString(metadata.bandOrOrchestra ?? "", 30);
    writeFixedString(metadata.album ?? "", 30);

    // 5. Write year (fixed-length 4)
    String yearString = (metadata.year ?? 0)
        .toString()
        .padLeft(4, '0'); // Pad with leading zeros
    writeFixedString(yearString, 4);

    // 6. Write comment (fixed-length 30, using a placeholder)
    writeFixedString(
        "", 30); // You can replace this with a comment if you have one

    // 7. Write genre byte (default to 255 if not provided)
    reader.writeByteSync(255);

    reader.closeSync();
  }
}
