class MetadataParserException implements Exception {
  final String message;

  const MetadataParserException({
    required this.message,
  });

  @override
  String toString() =>
      'MetadataParserException: error during the parsing of audio data\n${message}';
}

class NoMetadataParserException implements Exception {
  final String message;

  const NoMetadataParserException({
    required this.message,
  });

  @override
  String toString() =>
      'NoMetadataParserException: $message';
}
