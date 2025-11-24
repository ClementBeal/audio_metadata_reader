import 'dart:typed_data';

import 'package:audio_metadata_reader/src/io/io_source.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

class RiffParser extends TagParser {
  final metadata = RiffMetadata();
  late final Buffer buffer;

  /// Possible size of the `data` chunck
  int? dataSize;

  RiffParser({super.fetchImage = false});

  @override
  Future<ParserTag> parse(IOSource reader) async {
    await reader.setPosition(0);

    buffer = Buffer(ioSource: reader);
    await buffer.init();

    // Skip RIFF word, total size and WAVE
    await buffer.skip(12);

    // Read chunks after the RIFF header (starting with WAVE header)
    await _parseChunks();

    if (metadata.bitrate != null && dataSize != null) {
      final durationSeconds = dataSize! / metadata.bitrate!;
      metadata.duration =
          Duration(microseconds: (durationSeconds * 1000000).round());
    }

    await reader.close();

    return metadata;
  }

  /// Parses the chunks within the RIFF file
  /// A chunk has the following format :
  /// - 4 bytes: chunk Id
  /// - 4 bytes: chunk size in unsigned integer 32-LE
  ///
  /// The `fmt ` chunk contains the bitrate and the samplerate.
  /// The `LIST` contains a sub chunk called `INFO` and this later one
  /// contains the metadata.
  /// `data` chunk contains the number of audio bytes. Useful to calculate
  /// the track duration.
  Future<void> _parseChunks() async {
    // we substract 8
    while (buffer.fileCursor < await buffer.ioSource.length - 12) {
      final chunkId = String.fromCharCodes(await buffer.read(4));
      final chunkSize = getUint32LE(await buffer.read(4));

      if (chunkId == "fmt ") {
        await buffer.skip(4);
        metadata.samplerate = getUint32LE(await buffer.read(4));
        metadata.bitrate = getUint32LE(await buffer.read(4));

        await buffer.skip(4);
      } else if (chunkId == "LIST") {
        final listType = String.fromCharCodes(await buffer.read(4));
        if (listType == 'INFO') {
          _parseInfoChunk(await buffer.read(chunkSize - 4));
        }
      } else if (chunkId == "data") {
        dataSize = chunkSize;
        await buffer.read(chunkSize);
      } else {
        await buffer.read(chunkSize);
      }
    }
  }

  /// Parse the INFO chunk for metadata
  void _parseInfoChunk(Uint8List data) {
    int offset = 0;
    final byteData = ByteData.sublistView(data);

    while (offset < data.length) {
      final subChunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      offset += 4;
      int subChunkSize = byteData.getUint32(offset, Endian.little);

      offset += 4;
      final rawSubChunk = data.sublist(offset, offset + subChunkSize);
      final subChunkData =
          String.fromCharCodes(rawSubChunk).replaceAll('\x00', '').trim();

      if (subChunkSize % 2 == 1) subChunkSize++;
      offset += subChunkSize;

      switch (subChunkId) {
        case 'INAM':
          metadata.title = subChunkData;
          break;
        case 'IART':
          metadata.artist = subChunkData;
          break;
        case 'IPRD':
          metadata.album = subChunkData;
          break;
        case 'ICRD':
          metadata.year = DateTime.tryParse(subChunkData);
          break;
        case 'ICMT':
          metadata.comment = subChunkData;
          break;
        case 'ITRK':
          metadata.trackNumber = int.tryParse(subChunkData);
          break;
        case 'ISFT':
          metadata.encoder = subChunkData;
          break;
        case 'IGNR':
          metadata.genre = subChunkData;
          break;
        default:
          break;
      }
    }
  }

  /// Must start with the magic word `RIFF` if it's a wav file
  static Future<bool> canUserParser(IOSource reader) async {
    await reader.setPosition(0);
    final vendorName = String.fromCharCodes(await reader.read(4));

    return vendorName == "RIFF";
  }
}
