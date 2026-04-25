import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v1.dart';
import 'package:audio_metadata_reader/src/parsers/tags/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';

/// Container-level parser for MP3 files.
///
/// MP3 metadata is usually stored in ID3 tags, but finding those tags is a
/// responsibility of the MP3 container, not of the individual tag parsers:
/// - ID3v2, when present, starts at the beginning of the file.
/// - ID3v1, when present, occupies the last 128 bytes of the file.
///
/// The tag parsers receive the same [RandomAccessFile] positioned at the start
/// of the tag they must parse. This avoids loading the whole tag in memory,
/// which matters for large ID3v2 tags containing embedded pictures.
class MP3Parser extends TagParser {
  MP3Parser({super.fetchImage = false});

  @override
  ParserTag parse(RandomAccessFile reader) {
    try {
      if (hasID3v2Tag(reader)) {
        reader.setPositionSync(0);
        return ID3v2Parser(fetchImage: fetchImage).parse(reader);
      }

      if (hasID3v1Tag(reader)) {
        reader.setPositionSync(reader.lengthSync() - 128);
        return ID3v1Parser(fetchImage: fetchImage).parse(reader);
      }

      throw StateError("No ID3 tag found in this MP3 file");
    } finally {
      reader.closeSync();
    }
  }

  /// Returns true when this file has an ID3 tag that this MP3 parser can use.
  static bool canUserParser(RandomAccessFile reader) {
    return hasID3v2Tag(reader) || hasID3v1Tag(reader);
  }

  /// ID3v2 tags are identified by the "ID3" marker in the first 3 bytes.
  static bool hasID3v2Tag(RandomAccessFile reader) {
    if (reader.lengthSync() < 10) {
      return false;
    }

    reader.setPositionSync(0);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "ID3";
  }

  /// ID3v1 tags are identified by the "TAG" marker 128 bytes before EOF.
  static bool hasID3v1Tag(RandomAccessFile reader) {
    if (reader.lengthSync() < 128) {
      return false;
    }

    reader.setPositionSync(reader.lengthSync() - 128);
    final headerBytes = reader.readSync(3);
    final tagIdentity = String.fromCharCodes(headerBytes);

    return tagIdentity == "TAG";
  }
}
