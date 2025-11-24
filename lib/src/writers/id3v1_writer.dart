import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart'; // For encoding strings to bytes

class ID3v1Writer extends BaseMetadataWriter<Mp3Metadata> {
  @override
  Future<Uint8List> writeToBytes(Uint8List inputBytes, Mp3Metadata metadata) async {
    final outputBytes = <int>[...inputBytes];

    // 1. Seek to the ID3v1 tag position (128 bytes from the end)
    // ID3v1 tag is appended to the end of the file

    // 2. Write "TAG" identifier
    outputBytes.addAll(utf8.encode("TAG"));

    // 3. Helper function for writing fixed-length strings
    List<int> encodeFixedString(String str, int length) {
      List<int> bytes;
      if (str.length > length) {
        bytes = utf8.encode(str.substring(0, length)); // Truncate if too long
      } else {
        bytes = utf8.encode(str);
        bytes += List.filled(
            length - bytes.length, 0); // Pad with null bytes if too short
      }
      return bytes;
    }

    // 4. Write title, artist, album (fixed-length 30)
    outputBytes.addAll(encodeFixedString(metadata.songName ?? "", 30));
    outputBytes.addAll(encodeFixedString(metadata.bandOrOrchestra ?? "", 30));
    outputBytes.addAll(encodeFixedString(metadata.album ?? "", 30));

    // 5. Write year (fixed-length 4)
    String yearString = (metadata.year ?? 0)
        .toString()
        .padLeft(4, '0'); // Pad with leading zeros
    outputBytes.addAll(encodeFixedString(yearString, 4));

    // 6. Write comment (fixed-length 30, using a placeholder)
    outputBytes.addAll(encodeFixedString("", 30)); // You can replace this with a comment if you have one

    // 7. Write genre byte (default to 255 if not provided)
    outputBytes.add(255);

    return Uint8List.fromList(outputBytes);
  }
}
