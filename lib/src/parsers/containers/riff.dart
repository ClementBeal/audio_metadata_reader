import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

/// Parser for RIFF/WAVE containers.
class RiffParser extends TagParser<RiffMetadata> {
  /// Parsed metadata collected from `fmt `, `LIST/INFO`, and optional `ID3 ` chunks.
  final metadata = RiffMetadata();

  /// Reader helper bound to the current file.
  late final Buffer buffer;

  /// Possible size of the `data` chunck
  int? dataSize;

  /// Create a RIFF parser.
  ///
  /// Set [fetchImage] to `true` to keep embedded images from optional ID3 data.
  RiffParser({super.fetchImage = false});

  @override
  RiffMetadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    buffer = Buffer(randomAccessFile: reader);

    // Skip RIFF word, total size and WAVE
    buffer.skip(12);

    // Read chunks after the RIFF header (starting with WAVE header)
    _parseChunks();

    if (metadata.bitrate != null && dataSize != null) {
      final durationSeconds = dataSize! / metadata.bitrate!;
      metadata.duration =
          Duration(microseconds: (durationSeconds * 1000000).round());
    }

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
  void _parseChunks() {
    final fileLength = buffer.randomAccessFile.lengthSync();

    // Need at least 8 bytes to read a chunk header.
    while (buffer.fileCursor + 8 <= fileLength) {
      final chunkId = String.fromCharCodes(buffer.read(4));
      final chunkSize = getUint32LE(buffer.read(4));
      final chunkDataOffset = buffer.fileCursor;

      // Stop gracefully on truncated files.
      if (chunkSize > buffer.remainingBytes) {
        break;
      }

      if (chunkId == "fmt ") {
        _parseFormatChunk(buffer.read(chunkSize));
      } else if (chunkId == "LIST") {
        _parseListChunk(chunkSize);
      } else if (chunkId == "data") {
        dataSize = chunkSize;
        buffer.skip(chunkSize);
      } else if (chunkId == "ID3 " || chunkId == "id3 ") {
        // Some WAV files carry an embedded ID3v2 payload in an `ID3 ` chunk.
        // We parse it with the existing ID3 parser and merge useful fields.
        _parseId3Chunk(chunkDataOffset, chunkSize);
        buffer.setPositionSync(chunkDataOffset + chunkSize);
      } else {
        buffer.skip(chunkSize);
      }

      // RIFF chunks are word-aligned: odd sizes are followed by 1 pad byte.
      if (chunkSize.isOdd && buffer.fileCursor < fileLength) {
        buffer.skip(1);
      }
    }
  }

  /// Parse the `fmt ` chunk for audio properties.
  ///
  /// Byte layout for PCM-like formats:
  /// - 0..1:  audio format
  /// - 2..3:  channel count
  /// - 4..7:  sample rate (Hz)
  /// - 8..11: byte rate (bytes/second)
  void _parseFormatChunk(Uint8List chunkData) {
    if (chunkData.length < 12) {
      return;
    }

    metadata.samplerate = getUint32LE(chunkData.sublist(4, 8));
    metadata.bitrate = getUint32LE(chunkData.sublist(8, 12));
  }

  /// Parse a `LIST` chunk and delegate INFO payload parsing when available.
  void _parseListChunk(int chunkSize) {
    if (chunkSize < 4) {
      buffer.skip(chunkSize);
      return;
    }

    final listType = String.fromCharCodes(buffer.read(4));
    final payloadSize = chunkSize - 4;

    if (listType == 'INFO') {
      _parseInfoChunk(buffer.read(payloadSize));
    } else {
      // LIST can host non-INFO data. We intentionally ignore it.
      buffer.skip(payloadSize);
    }
  }

  /// Parse the INFO chunk for metadata
  void _parseInfoChunk(Uint8List data) {
    int offset = 0;
    final byteData = ByteData.sublistView(data);

    while (offset + 8 <= data.length) {
      final subChunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      offset += 4;
      final subChunkSize = byteData.getUint32(offset, Endian.little);
      offset += 4;

      if (offset + subChunkSize > data.length) {
        break;
      }

      final rawSubChunk = data.sublist(offset, offset + subChunkSize);
      final subChunkData =
          String.fromCharCodes(rawSubChunk).replaceAll('\x00', '').trim();
      offset += subChunkSize;

      if (subChunkSize.isOdd && offset < data.length) {
        offset += 1;
      }

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
        case 'IPUB':
          metadata.publisher = subChunkData;
          break;
        case 'ICOP':
          metadata.copyright = subChunkData;
          break;
        default:
          break;
      }
    }
  }

  /// Parse an `ID3 ` RIFF chunk by delegating to [ID3v2Parser].
  ///
  /// We validate the announced tag size first, so malformed chunks cannot
  /// make the ID3 parser read outside the RIFF chunk boundaries.
  void _parseId3Chunk(int chunkDataOffset, int chunkSize) {
    if (chunkSize < 10) {
      return;
    }

    final reader = buffer.randomAccessFile;
    reader.setPositionSync(chunkDataOffset);
    final header = reader.readSync(10);

    if (header.length < 10 ||
        String.fromCharCodes(header.sublist(0, 3)) != 'ID3') {
      return;
    }

    final tagSize = (header[9] & 0x7F) |
        ((header[8] & 0x7F) << 7) |
        ((header[7] & 0x7F) << 14) |
        ((header[6] & 0x7F) << 21);
    final hasFooter = (header[5] & 0x10) != 0;
    final totalTagSize = 10 + tagSize + (hasFooter ? 10 : 0);

    if (totalTagSize > chunkSize) {
      return;
    }

    reader.setPositionSync(chunkDataOffset);
    final id3Metadata = ID3v2Parser(fetchImage: fetchImage).parse(reader);
    _mergeId3Metadata(id3Metadata);
  }

  /// Merge key ID3v2 fields into the RIFF metadata model.
  ///
  /// LIST/INFO and ID3 can coexist in WAV. When ID3 provides a value, we
  /// prefer it because it usually carries richer tagging.
  void _mergeId3Metadata(Mp3Metadata id3) {
    if (_hasText(id3.songName)) {
      metadata.title = id3.songName;
    }

    final id3Artist =
        id3.bandOrOrchestra ?? id3.leadPerformer ?? id3.originalArtist;
    if (_hasText(id3Artist)) {
      metadata.artist = id3Artist;
    }

    if (_hasText(id3.album)) {
      metadata.album = id3.album;
    }

    if (id3.trackNumber != null) {
      metadata.trackNumber = id3.trackNumber;
    }

    if (_hasText(id3.publisher)) {
      metadata.publisher = id3.publisher;
    }

    if (_hasText(id3.copyrightMessage)) {
      metadata.copyright = id3.copyrightMessage;
    }

    if (_hasText(id3.encoderSoftware)) {
      metadata.encoder = id3.encoderSoftware;
    } else if (_hasText(id3.encodedBy)) {
      metadata.encoder = id3.encodedBy;
    }

    final firstGenre = id3.genres.firstWhere(
      (value) => value.trim().isNotEmpty,
      orElse: () => '',
    );
    if (firstGenre.isNotEmpty) {
      metadata.genre = firstGenre;
    }

    final parsedYear = id3.year ?? id3.originalReleaseYear;
    if (parsedYear != null) {
      metadata.year = DateTime(parsedYear);
    }

    if (id3.pictures.isNotEmpty) {
      metadata.pictures.addAll(id3.pictures);
    }
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  /// Must start with the magic word `RIFF` if it's a wav file
  /// Returns `true` when [reader] looks like a RIFF/WAVE file.
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);
    final vendorName = String.fromCharCodes(reader.readSync(4));

    return vendorName == "RIFF";
  }
}
