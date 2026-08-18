import 'dart:io';
import 'dart:convert';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart'; // For encoding strings to bytes

/// ID3v1 writer and its fixed 128-byte trailer format.
///
/// Protocol section: ID3v1 trailer
/// Bytes: 0..127 of the final tag
/// Layout:
/// TAG | title[30] | artist[30] | album[30] | year[4] | comment[30] | genre[1]
/// Meaning:
/// - `TAG`: three-byte ASCII identifier.
/// - `title`, `artist`, `album`: fixed-width 30-byte text fields.
/// - `year`: fixed-width four-byte text field.
/// - `comment`: fixed-width 30-byte text field.
/// - `genre`: one byte; this writer uses 255 when no genre is provided.
/// Constraints:
/// - A valid ID3v1 tag is exactly 128 bytes and starts with `TAG`.
/// - The tag is stored at the end of the file, after the audio bytes.
class ID3v1Writer extends BaseMetadataWriter<Mp3Metadata> {
  @override
  void writeContents(File source, File destination, Mp3Metadata metadata) {
    final sourceReader = source.openSync(mode: FileMode.read);
    final destinationWriter = destination.openSync(mode: FileMode.write);

    try {
      final sourceLength = sourceReader.lengthSync();
      const existingTagLength = 128;
      var audioLength = sourceLength;

      // ID3v1 is a trailer, so replace an existing final trailer instead of
      // copying it and appending another one. Checking the identifier at the
      // exact 128-byte boundary avoids removing arbitrary audio bytes from a
      // file that merely happens to contain the text "TAG" elsewhere.
      if (sourceLength >= existingTagLength) {
        sourceReader.setPositionSync(sourceLength - existingTagLength);
        final identifier = sourceReader.readSync(3);
        final hasExistingId3v1Tag = identifier.length == 3 &&
            identifier[0] == 0x54 &&
            identifier[1] == 0x41 &&
            identifier[2] == 0x47;

        if (hasExistingId3v1Tag) {
          audioLength -= existingTagLength;
        }
      }

      // Copy only the audio portion in bounded chunks. This keeps replacement
      // streaming-friendly for large tracks and leaves the destination ready
      // for the one new 128-byte ID3v1 trailer below.
      sourceReader.setPositionSync(0);
      var remaining = audioLength;
      const chunkSize = 64 * 1024;
      while (remaining > 0) {
        final bytesToRead = remaining < chunkSize ? remaining : chunkSize;
        destinationWriter.writeFromSync(sourceReader.readSync(bytesToRead));
        remaining -= bytesToRead;
      }

      // Write the new ID3v1 trailer immediately after the audio bytes.
      destinationWriter.writeStringSync("TAG");

      void writeFixedString(String str, int length) {
        List<int> bytes;
        if (str.length > length) {
          bytes = utf8.encode(str.substring(0, length)); // Truncate if too long
        } else {
          bytes = utf8.encode(str);
          bytes += List.filled(
              length - bytes.length, 0); // Pad with null bytes if too short
        }
        destinationWriter.writeFromSync(bytes);
      }

      // Write title, artist, album (fixed-length 30).
      writeFixedString(metadata.songName ?? "", 30);
      // ID3v1 has one artist slot. It corresponds to the lead performer
      // (`TPE1`), which is also the field written by the common `setArtist`
      // setter. Keep the band/orchestra fallback for callers that construct
      // Mp3Metadata directly using the older field.
      writeFixedString(
          metadata.leadPerformer ?? metadata.bandOrOrchestra ?? "", 30);
      writeFixedString(metadata.album ?? "", 30);

      // Write year (fixed-length 4).
      String yearString = (metadata.year ?? 0)
          .toString()
          .padLeft(4, '0'); // Pad with leading zeros
      writeFixedString(yearString, 4);

      // Write comment (fixed-length 30, using a placeholder).
      writeFixedString(
          "", 30); // You can replace this with a comment if you have one

      // Write genre byte (default to 255 if not provided).
      destinationWriter.writeByteSync(255);
    } finally {
      sourceReader.closeSync();
      destinationWriter.closeSync();
    }
  }
}
