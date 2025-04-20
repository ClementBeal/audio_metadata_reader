import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';

/// Base class for all the metadata writer
abstract class BaseMetadataWriter<T extends ParserTag> {
  /// Write the [metadata] into the [file]
  void write(File file, T metadata);
}
