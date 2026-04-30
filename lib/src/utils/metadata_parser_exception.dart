import 'dart:io';

/// Base exception used when metadata parsing fails.
class MetadataParserException implements Exception {
  /// Audio file involved in the parsing failure.
  final File track;

  /// Human-readable details about the failure.
  final String message;

  /// Build a parsing exception.
  const MetadataParserException({
    required this.track,
    required this.message,
  });

  @override
  String toString() =>
      'MetadataParserException : error during the parsing of "${track.path}"\n${message}';
}

/// Exception thrown when the package has no parser for a file.
class NoMetadataParserException implements Exception {
  /// File that could not be parsed.
  final File track;

  /// Build a "no parser found" exception.
  const NoMetadataParserException({
    required this.track,
  });

  @override
  String toString() =>
      'NoMetadataParserException : no parser for "${track.path}"';
}
