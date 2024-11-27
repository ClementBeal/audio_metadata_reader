import 'dart:io';

class MetadataParserException implements Exception {
  final File track;
  final String message;

  const MetadataParserException({
    required this.track,
    required this.message,
  });

  @override
  String toString() =>
      'MetadataParserException : error during the parsing of "${track.path}"\n${message}';
}

class NoMetadataParserException implements Exception {
  final File track;

  const NoMetadataParserException({
    required this.track,
  });

  @override
  String toString() =>
      'NoMetadataParserException : no parser for "${track.path}"';
}
