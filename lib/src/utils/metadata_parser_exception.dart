import 'dart:io';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

class MetadataParserException implements Exception {
  final MyRandomAccessFile? track;
  final String message;

  const MetadataParserException({
    this.track,
    required this.message,
  });

  @override
  String toString() {
    final trackInfo = track != null ? '"$track"' : 'unknown track';
    return 'MetadataParserException : error during the parsing of $trackInfo\n$message';
  }
}

class NoMetadataParserException implements Exception {
  final MyRandomAccessFile? track;

  const NoMetadataParserException({
    this.track,
  });

  @override
  String toString() {
    final trackInfo = track != null ? '"$track"' : 'unknown track';
    return 'NoMetadataParserException : no parser for $trackInfo';
  }
}
