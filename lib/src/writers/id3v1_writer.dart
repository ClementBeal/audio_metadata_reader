import 'dart:io';
import 'dart:convert';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'; // For encoding strings to bytes

class Id3v1Writer {
  void write(RandomAccessFile writer, AudioMetadata metadata) {
    // 1. Seek to the ID3v1 tag position (128 bytes from the end)
    writer.setPositionSync(writer.lengthSync());

    // 2. Write "TAG" identifier
    writer.writeStringSync("TAG");

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
      writer.writeFromSync(bytes);
    }

    // 4. Write title, artist, album (fixed-length 30)
    writeFixedString(metadata.title ?? "", 30);
    writeFixedString(metadata.artist ?? "", 30);
    writeFixedString(metadata.album ?? "", 30);

    // 5. Write year (fixed-length 4)
    String yearString = (metadata.year?.year ?? 0)
        .toString()
        .padLeft(4, '0'); // Pad with leading zeros
    writeFixedString(yearString, 4);

    // 6. Write comment (fixed-length 30, using a placeholder)
    writeFixedString(
        "", 30); // You can replace this with a comment if you have one

    // 7. Write genre byte (default to 255 if not provided)
    writer.writeByteSync(255);

    writer.closeSync();
  }
}
