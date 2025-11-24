import 'dart:io' show File, RandomAccessFile;
import 'dart:typed_data';

import 'io_source.dart';

/// IOSource implementation backed by dart:io File.
/// This implementation is only available on platforms that support dart:io.
class FileIOSource implements IOSource {
  final RandomAccessFile _file;
  int _position = 0;

  FileIOSource(this._file);

  /// Create an IOSource from a File
  static Future<FileIOSource> fromFile(File file) async {
    final raf = await file.open();
    return FileIOSource(raf);
  }

  @override
  Future<int> get length async => await _file.length();

  @override
  int get position => _position;

  @override
  Future<void> setPosition(int position) async {
    _position = position;
    await _file.setPosition(position);
  }

  @override
  Future<Uint8List> read(int length) async {
    final bytes = await _file.read(length);
    _position += bytes.length;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) async {
    final bytesRead = await _file.readInto(buffer, start, end);
    _position += bytesRead;
    return bytesRead;
  }

  @override
  Future<void> close() async {
    await _file.close();
  }

  /// Get access to the underlying RandomAccessFile for direct operations
  RandomAccessFile get file => _file;
}

/// IOSource implementation backed by Uint8List.
/// This implementation is platform-agnostic and works on all platforms.
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
