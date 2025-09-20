import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart';

class RiffWriter extends BaseMetadataWriter<RiffMetadata> {
  late RiffMetadata metadata;
  late final Buffer buffer;

  @override
  void write(File file, RiffMetadata metadata) {
    this.metadata = metadata;
    print('fuck:${metadata}');
    final builder = BytesBuilder();

    final reader = file.openSync();
    buffer = Buffer(randomAccessFile: reader);
    reader.setPositionSync(0);

    buffer.skip(12);
    final newData = _parseChunks();

    builder.add("RIFF".codeUnits);
    builder.add(intToUint32LE(newData.length));
    builder.add("WAVE".codeUnits);
    builder.add(newData);

    reader.closeSync();
    file.writeAsBytesSync(builder.toBytes());
  }

  Uint8List _parseChunks() {
    final builder = BytesBuilder();

    while (buffer.fileCursor < buffer.randomAccessFile.lengthSync() - 8) {
      final chunkIdBytes = buffer.read(4);
      final chunkId = String.fromCharCodes(chunkIdBytes);
      final chunkSizeBytes = buffer.read(4);
      final chunkSize = getUint32LE(chunkSizeBytes);

      builder.add(chunkIdBytes);

      if (chunkId == "LIST") {
        // Peek at the next 4 bytes to check the LIST type
        final listTypeBytes = buffer.read(4);
        final listType = String.fromCharCodes(listTypeBytes);

        if (listType == "INFO") {
          // Skip old INFO data
          buffer.skip(chunkSize - 4);

          // Write new LIST chunk with updated INFO
          final infoBuilder = BytesBuilder();

          if (metadata.title != null) {
            infoBuilder.add(_writeChunk("INAM", metadata.title!));
          }
          if (metadata.artist != null) {
            infoBuilder.add(_writeChunk("IART", metadata.artist!));
          }
          if (metadata.album != null) {
            infoBuilder.add(_writeChunk("IPRD", metadata.album!));
          }
          if (metadata.year != null) {
            infoBuilder
                .add(_writeChunk("ICRD", metadata.year!.year.toString()));
          }
          if (metadata.comment != null) {
            infoBuilder.add(_writeChunk("ICMT", metadata.comment!));
          }
          if (metadata.trackNumber != null) {
            infoBuilder
                .add(_writeChunk("ITRK", metadata.trackNumber!.toString()));
          }
          if (metadata.encoder != null) {
            infoBuilder.add(_writeChunk("ISFT", metadata.encoder!));
          }
          if (metadata.genre != null) {
            infoBuilder.add(_writeChunk("IGNR", metadata.genre!));
          }
          if (metadata.copyright != null) {
            infoBuilder.add(_writeChunk("ICOP", metadata.copyright!));
          }
          print(metadata.lyric);
          if (metadata.lyric != null) {
            infoBuilder.add(_writeChunk("ICMT", metadata.lyric!));
          }

          final infoData = infoBuilder.toBytes();
          // 4 bytes for "INFO" + INFO subchunks
          final newChunkSize = 4 + infoData.length;

          builder.add(intToUint32LE(newChunkSize));
          builder.add(ascii.encode("INFO"));
          builder.add(infoData);
        } else {
          // Keep the LIST chunk as-is
          builder.add(chunkSizeBytes);
          builder.add(listTypeBytes);
          builder.add(buffer.read(chunkSize - 4));
        }
      } else {
        builder.add(chunkSizeBytes);
        builder.add(buffer.read(chunkSize));
      }

      // Handle padding if chunkSize is odd (WAV chunks are aligned to even sizes)
      if (chunkSize.isOdd) {
        buffer.skip(1);
        builder.addByte(0);
      }
    }

    return builder.toBytes();
  }

  Uint8List _writeChunk(String id, String value) {
    final builder = BytesBuilder();

    final idBytes = ascii.encode(id);
    final valueBytes = ascii.encode(value);
    int size = valueBytes.length;

    // Add padding byte if size is odd (WAV format requires even chunk sizes)
    final needsPadding = size.isOdd;
    if (needsPadding) {
      size += 1;
    }

    builder.add(idBytes); // 4 bytes: chunk ID (e.g., "INAM")
    builder.add(intToUint32LE(size)); // 4 bytes: chunk size (padded if needed)
    builder.add(valueBytes); // chunk data
    if (needsPadding) {
      builder.addByte(0); // padding
    }

    return builder.toBytes();
  }
}
