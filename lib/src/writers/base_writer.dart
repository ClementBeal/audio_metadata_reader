import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';

/// Base class for all the metadata writer
abstract class BaseMetadataWriter<T extends ParserTag> {
  /// Process audio data bytes and return new bytes with updated metadata
  /// This is the core method that works on all platforms including web
  Future<Uint8List> writeToBytes(Uint8List inputBytes, T metadata);
}
