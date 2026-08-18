import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/base.dart';

/// Base class for all the metadata writer
abstract class BaseMetadataWriter<T extends ParserTag> {
  /// Rebuilds [file] atomically with [metadata].
  ///
  /// Every format writer receives the original file as a read-only source and
  /// writes the complete replacement to a sibling `.tmp` file. The temporary
  /// file is renamed only after serialization succeeds, so a failed writer
  /// cannot leave a partially written target behind.
  void write(File file, T metadata) {
    final temporaryFile = File('${file.path}.tmp');

    try {
      writeContents(file, temporaryFile, metadata);
      temporaryFile.renameSync(file.path);
    } finally {
      if (temporaryFile.existsSync()) {
        temporaryFile.deleteSync();
      }
    }
  }

  /// Serializes [metadata] from [source] into the complete [destination]
  /// file. Implementations must never write to [source].
  void writeContents(File source, File destination, T metadata);
}
