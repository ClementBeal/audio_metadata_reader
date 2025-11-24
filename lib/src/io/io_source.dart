import 'dart:typed_data';

// Conditionally export platform-specific implementations
export 'io_source_io.dart'
    if (dart.library.html) 'io_source_web.dart';

/// Abstract interface for reading audio file data.
/// Provides a platform-agnostic way to access audio file bytes.
abstract class IOSource {
  /// Get the total length of the data source in bytes
  Future<int> get length;

  /// Get the current position in the data source
  int get position;

  /// Set the position in the data source
  Future<void> setPosition(int position);

  /// Read bytes from the current position
  Future<Uint8List> read(int length);

  /// Read bytes into an existing buffer
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]);

  /// Close the data source and release resources
  Future<void> close();
}
