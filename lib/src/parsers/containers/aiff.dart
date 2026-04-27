import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:audio_metadata_reader/src/utils/metadata_parser_exception.dart';

/// Parser for AIFF / AIFC containers.
///
/// AIFF is an IFF-family container, so the file layout is:
/// - 4 bytes: `FORM`
/// - 4 bytes: FORM chunk size (big-endian)
/// - 4 bytes: form type (`AIFF` or `AIFC`)
/// - then N child chunks
///
/// Each child chunk uses the same pattern:
/// - 4 bytes: chunk id (ASCII)
/// - 4 bytes: chunk data size (big-endian)
/// - `size` bytes: payload
/// - optional 1 pad byte if `size` is odd (IFF alignment rule)
class AiffParser extends TagParser<RiffMetadata> {
  final metadata = RiffMetadata();
  late final Buffer buffer;

  AiffParser({super.fetchImage = false});

  @override
  RiffMetadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);
    buffer = Buffer(randomAccessFile: reader);

    final formId = String.fromCharCodes(buffer.read(4));
    if (formId != 'FORM') {
      throw MetadataParserException(
          track: File(''), message: 'Invalid AIFF file');
    }

    // The FORM size is not required for our scan because we already know the
    // file length from RandomAccessFile. We still consume it to keep the cursor
    // aligned to the form type.
    buffer.skip(4);

    final formType = String.fromCharCodes(buffer.read(4));
    if (formType != 'AIFF' && formType != 'AIFC') {
      throw MetadataParserException(
        track: File(''),
        message: 'Unsupported FORM type: $formType',
      );
    }

    _parseChunks();

    reader.closeSync();
    return metadata;
  }

  /// Iterate through all top-level chunks in the AIFF FORM.
  void _parseChunks() {
    final fileLength = buffer.randomAccessFile.lengthSync();

    // Need at least 8 bytes for another chunk header.
    while (buffer.fileCursor + 8 <= fileLength) {
      final chunkId = String.fromCharCodes(buffer.read(4));
      final chunkSize = getUint32(buffer.read(4));
      final chunkDataOffset = buffer.fileCursor;

      // File is truncated: stop parsing instead of reading invalid offsets.
      if (chunkSize > buffer.remainingBytes) {
        break;
      }

      switch (chunkId) {
        case 'COMM':
          _parseCommonChunk(buffer.read(chunkSize));
          break;
        case 'NAME':
          metadata.title = _parseTextChunk(buffer.read(chunkSize));
          break;
        case 'AUTH':
          metadata.artist = _parseTextChunk(buffer.read(chunkSize));
          break;
        case 'ANNO':
          metadata.comment = _parseTextChunk(buffer.read(chunkSize));
          break;
        case '(c) ':
          metadata.copyright = _parseTextChunk(buffer.read(chunkSize));
          break;
        case 'ID3 ':
          // Some AIFF files store rich metadata in an embedded ID3v2 tag.
          // We parse it using the existing ID3 parser used for MP3 tags.
          _parseId3Chunk(chunkDataOffset, chunkSize);
          buffer.setPositionSync(chunkDataOffset + chunkSize);
          break;
        default:
          // Unknown chunks are valid in AIFF. We intentionally ignore them.
          buffer.skip(chunkSize);
          break;
      }

      // IFF chunks are word-aligned: odd payload sizes are followed by 1 pad byte.
      if (chunkSize.isOdd && buffer.fileCursor < fileLength) {
        buffer.skip(1);
      }
    }
  }

  /// Parse `COMM` (Common) chunk.
  ///
  /// For AIFF, the first 18 bytes are:
  /// - 2 bytes: channel count
  /// - 4 bytes: number of sample frames
  /// - 2 bytes: sample size in bits
  /// - 10 bytes: sample rate as 80-bit IEEE extended float
  ///
  /// AIFC may append compression information after those 18 bytes. We keep this
  /// parser simple and only consume the shared 18-byte prefix.
  void _parseCommonChunk(Uint8List chunkData) {
    if (chunkData.length < 18) {
      return;
    }

    final channels = getUint16(chunkData.sublist(0, 2));
    final totalSampleFrames = getUint32(chunkData.sublist(2, 6));
    final bitsPerSample = getUint16(chunkData.sublist(6, 8));
    final sampleRate = _decodeExtended80(chunkData.sublist(8, 18));

    if (sampleRate <= 0) {
      return;
    }

    metadata.samplerate = sampleRate.round();

    // For PCM-style AIFF files, bitrate (bytes/sec) is:
    // sampleRate * channels * bytesPerSample
    final bytesPerSample = (bitsPerSample / 8).ceil();
    metadata.bitrate = (sampleRate * channels * bytesPerSample).round();

    final durationSeconds = totalSampleFrames / sampleRate;
    metadata.duration = Duration(
      microseconds: (durationSeconds * 1000000).round(),
    );
  }

  String _parseTextChunk(Uint8List chunkData) {
    return String.fromCharCodes(chunkData).replaceAll('\x00', '').trim();
  }

  /// Parse an `ID3 ` AIFF chunk by delegating to [ID3v2Parser].
  ///
  /// We validate the announced ID3 payload size before parsing so malformed
  /// chunks cannot make the ID3 parser read outside this chunk.
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

  /// Merge the most useful ID3 fields into the AIFF metadata model.
  ///
  /// AIFF text chunks (`NAME`, `AUTH`, ...) and ID3 may coexist.
  /// When ID3 provides a value, we prefer it because it is usually richer.
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

  /// Decode the AIFF 80-bit extended float used for sample rate.
  ///
  /// Layout:
  /// - bit 79: sign
  /// - bits 78..64: exponent (bias 16383)
  /// - bits 63..0: mantissa (includes explicit integer bit)
  ///
  /// Numerical value:
  ///   mantissa * 2^(exponent - 16383 - 63)
  ///
  /// This is enough for sample-rate values typically found in audio files
  /// (44_100, 48_000, 96_000, ...).
  double _decodeExtended80(Uint8List bytes) {
    if (bytes.length != 10) {
      return 0;
    }

    final sign = (bytes[0] & 0x80) != 0 ? -1.0 : 1.0;
    final exponent = ((bytes[0] & 0x7F) << 8) | bytes[1];

    // Use floating-point accumulation instead of bitwise shifts.
    // Dart bitwise operators are 64-bit signed operations, so left-shifting
    // an unsigned 64-bit mantissa can flip the sign bit and corrupt values.
    double mantissa = 0;
    for (int i = 2; i < 10; i++) {
      mantissa = (mantissa * 256) + bytes[i];
    }

    if (exponent == 0 && mantissa == 0) {
      return 0;
    }

    // Exponent 0x7FFF is reserved for Inf/NaN in this representation.
    if (exponent == 0x7FFF) {
      return 0;
    }

    final value = mantissa * pow(2, exponent - 16383 - 63);
    return sign * value;
  }

  /// An AIFF parser is valid for `FORM` files whose form type is `AIFF`/`AIFC`.
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final formId = String.fromCharCodes(reader.readSync(4));
    if (formId != 'FORM') {
      return false;
    }

    // Skip FORM size and inspect form type.
    reader.setPositionSync(8);
    final formType = String.fromCharCodes(reader.readSync(4));
    return formType == 'AIFF' || formType == 'AIFC';
  }
}
