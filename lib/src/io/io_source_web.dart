import 'dart:typed_data';

import 'io_source.dart';

/// Stub for FileIOSource on web platform.
/// File operations are not supported on web.
class FileIOSource implements IOSource {
  FileIOSource._();

  /// Create an IOSource from a File
  /// This will throw an error on web as File is not supported
  static Future<FileIOSource> fromFile(dynamic file) async {
    throw UnsupportedError(
      'File operations are not supported on web platform. '
      'Please use ByteDataIOSource.fromBytes() with Uint8List instead.'
    );
  }

  @override
  Future<int> get length => throw UnsupportedError('Not available on web');

  @override
  int get position => throw UnsupportedError('Not available on web');

  @override
  Future<void> setPosition(int position) {
    throw UnsupportedError('Not available on web');
  }

  @override
  Future<Uint8List> read(int length) {
    throw UnsupportedError('Not available on web');
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) {
    throw UnsupportedError('Not available on web');
  }

  @override
  Future<void> close() {
    throw UnsupportedError('Not available on web');
  }

  /// Placeholder for API parity with the IO implementation.
  dynamic get file => throw UnsupportedError('Not available on web');
}

/// IOSource implementation backed by Uint8List.
/// This implementation is platform-agnostic and works on all platforms including web.
class ByteDataIOSource implements IOSource {
  final Uint8List _data;
  int _position = 0;

  ByteDataIOSource(this._data);

  /// Create an IOSource from Uint8List
  static ByteDataIOSource fromBytes(Uint8List bytes) {
    return ByteDataIOSource(bytes);
  }

  @override
  Future<int> get length async => _data.length;

  @override
  int get position => _position;

  @override
  Future<void> setPosition(int position) async {
    if (position < 0 || position > _data.length) {
      throw RangeError('Position $position is out of range [0, ${_data.length}]');
    }
    _position = position;
  }

  @override
  Future<Uint8List> read(int length) async {
    if (_position + length > _data.length) {
      length = _data.length - _position;
    }

    final result = Uint8List.fromList(
      _data.sublist(_position, _position + length)
    );
    _position += length;
    return result;
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) async {
    end ??= buffer.length;
    final length = end - start;
    final available = _data.length - _position;
    final toRead = length < available ? length : available;

    buffer.setRange(start, start + toRead, _data, _position);
    _position += toRead;
    return toRead;
  }

  @override
  Future<void> close() async {
    // No resources to release for in-memory data
  }

  /// Get the underlying byte data
  Uint8List get data => _data;
}
