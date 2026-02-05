import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:math' as math;
import '../../audio_metadata_reader.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

int ceilDivInt(int a, int b) => (a + b - 1) ~/ b;



abstract class  MyRandomAccessFile{
  Future<int> position();
  Future<void> setPosition(int position);
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]);
  Future<int> length();
  Future<void> close();
  Future<Uint8List> read(int size);

}

class FileRandomAccessFile implements MyRandomAccessFile{
  final RandomAccessFile randomAccessFile;

  FileRandomAccessFile({required this.randomAccessFile});

  @override
  Future<int> length(){
    return randomAccessFile.length();
  }

  @override
  Future<int> position() {
    return randomAccessFile.position();
  }

  @override
  Future<void> setPosition(int position) {
    return randomAccessFile.setPosition(position);
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) {
    return randomAccessFile.readInto(buffer, start, end);
  }

  @override
  Future<void> close() async {
    await randomAccessFile.close();
  }

  @override
  Future<Uint8List> read(int size) async {
    return await randomAccessFile.read(size);
  }
}

class Uint8ListRandomAccessFile implements MyRandomAccessFile {
  final Uint8List _data;
  int _position = 0;

  Uint8ListRandomAccessFile({required Uint8List data}) : _data = data;

  @override
  Future<int> position() async {
    return _position;
  }

  @override
  Future<void> setPosition(int position) async {
    if (position < 0) {
      throw RangeError('Position cannot be negative');
    }
    _position = position;
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) async {
    end ??= buffer.length;
    
    if (start < 0 || end > buffer.length || start > end) {
      throw RangeError('Invalid buffer range');
    }
    
    if (_position >= _data.length) {
      return 0; // EOF
    }
    
    final availableBytes = _data.length - _position;
    final requestedBytes = end - start;
    final bytesToRead = math.min(availableBytes, requestedBytes);
    
    buffer.setRange(
      start, 
      start + bytesToRead, 
      _data, 
      _position
    );
    
    _position += bytesToRead;
    return bytesToRead;
  }

  @override
  Future<int> length() async {
    return _data.length;
  }

  @override
  Future<void> close() async {
    // 内存数据无需关闭操作
  }

  @override
  Future<Uint8List> read(int size) async {
    if (size < 0) {
      throw ArgumentError('Size cannot be negative');
    }
    
    if (_position >= _data.length) {
      return Uint8List(0); // EOF
    }
    
    final availableBytes = _data.length - _position;
    final bytesToRead = math.min(availableBytes, size);
    
    final result = Uint8List.sublistView(
      _data, 
      _position, 
      _position + bytesToRead
    );
    
    _position += bytesToRead;
    return result;
  }
}



class WebDavRandomAccessFile implements MyRandomAccessFile{
  final webdav.Client client;
  final String path;
  int _position = 0;
  int? _length;

  WebDavRandomAccessFile({required this.client, required this.path});

  @override
  Future<int> length() async {
    if(_length == null){
      _length = await client.readContentLength(path);
    }
    return _length!;
  }

  @override
  Future<int> position() async {
    return _position;
  }

  @override
  Future<void> setPosition(int position) async {
    _position = position;
  }

  @override
  Future<int> readInto(Uint8List buffer, [int start = 0, int? end]) async {
    final toRead = (end ?? buffer.length) - start;
    final rangeEnd = min(_position + toRead -1, await length() -1);
    if(rangeEnd < _position){
      return 0;
    }
    final data = await client.read(path, range: webdav.Range(start: _position, end: rangeEnd));
    buffer.setRange(start, start + data.length, data);
    _position += data.length;
    return data.length;
  }

  @override
  Future<void> close() async {
    
  }
  @override
  Future<Uint8List> read(int size) async {
    final rangeEnd = min(_position + size -1, await length() -1);
    if(rangeEnd < _position){
      return Uint8List(0);
    }
    final data = await client.read(path, range: webdav.Range(start: _position, end: rangeEnd));
    _position += data.length;
    return data;
  }
}





class Buffer {
  final MyRandomAccessFile randomAccessFile;
  final Uint8List _buffer;

  /// It's like positionSync() but adapted with the buffer
  int fileCursor = 0;

  /// Position of the cursor in the buffer of size [_bufferSize]
  int _cursor = 0;

  /// Track how many bytes are actually in the buffer
  int _bufferedBytes = 0;

  /// The buffer size is always a power of 2.
  /// To reach good performance, we need at least 4096
  static final int _bufferSize = 16384;

  /// The number of bytes remaining to be read from the file.
  Future<int> remainingBytes()async {
    return (_bufferedBytes - _cursor) +
      (await randomAccessFile.length() - await randomAccessFile.position());
  }

  Buffer._({required this.randomAccessFile}) : _buffer = Uint8List(_bufferSize);
  
  static Future<Buffer> create({required MyRandomAccessFile randomAccessFile}) async {
    final buffer = Buffer._(randomAccessFile: randomAccessFile);
    await buffer._fill();
    return buffer;
  }

  Future<void> _fill() async {
    _bufferedBytes = await randomAccessFile.readInto(_buffer);
    _cursor = 0;
  }

  /// Throws a [MetadataParserException] if a previous call to [_fill]
  /// was unable to read any data from the file.
  ///
  /// Once the end of the file is reached, subsequent reads from
  /// [RandomAccessFile] will read 0 bytes without failing. This
  /// can cause [read] below to infinite loop.
  void _throwOnNoData() {
    if (_bufferedBytes == 0) {
      throw MetadataParserException(
          track: randomAccessFile, message: "Expected more data in file");
    }
  }

  Future<Uint8List> read(int size) async {
    fileCursor += size;

    // if we read something big (~100kb), we can read it directly from file
    // it makes the read faster
    // no need to use the buffer
    if (size > _bufferSize) {
      final result = Uint8List(size);
      final remaining = _bufferedBytes - _cursor;
      if (remaining > 0) {
        result.setRange(0, remaining, _buffer, _cursor);
      }
      await randomAccessFile.readInto(result, remaining);
      await _fill();
      return result;
    }

    if (size <= _bufferedBytes - _cursor) {
      // Data fits within the current buffer
      final result = _buffer.sublist(_cursor, _cursor + size);
      _cursor += size;
      return result;
    } else {
      // Data exceeds remaining buffer, needs refill
      final result = Uint8List(size);
      int remaining = _bufferedBytes - _cursor;
      // Copy remaining data from the buffer
      result.setRange(0, remaining, _buffer, _cursor);

      // Refill the buffer and adjust the cursor
      _fill();
      int filled = remaining;

      // Continue filling `result` with new buffer data
      while (filled < size) {
        int toCopy = size - filled;
        if (toCopy > _bufferedBytes) {
          toCopy = _bufferedBytes;
        }
        result.setRange(filled, filled + toCopy, _buffer, 0);
        filled += toCopy;
        _cursor = toCopy;

        // Fill buffer again if more data is needed
        if (filled < size) {
          _fill();
          // Avoid infinite loops if we are trying to read
          // more data than there is left in the file.
          _throwOnNoData();
        }
      }
      return result;
    }
  }

  /// Reads at most [size] bytes from the file.
  ///
  /// May return a smaller list if [remainingBytes] is
  /// less than [size].
  Future<Uint8List> readAtMost(int size) async {
    final readSize = min(size, await remainingBytes());
    return await read(readSize);
  }

  Future<void> setPosition(int position)async {
    fileCursor = position;
    await randomAccessFile.setPosition(position);
    await _fill();
  }

  Future<void> skip(int length) async{
    // Calculate how many bytes we can skip in the current buffer
    final remainingInBuffer = _bufferedBytes - _cursor;

    if (length <= remainingInBuffer) {
      fileCursor += length;

      // If we can skip within the current buffer, just move the cursor
      _cursor += length;
    } else {
      // Calculate the actual file position we need to skip to
      int currentPosition = (await randomAccessFile.position()) - remainingInBuffer;
      fileCursor += currentPosition;
      // Skip to the new position
      await randomAccessFile.setPosition(currentPosition + length);
      // Refill the buffer at the new position
      await _fill();
    }
  }

  Future<int> lengthSync() async{
    return randomAccessFile.length();
  }

  Future<void> closeSync() async {
    await randomAccessFile.close();
  }
}

extension BufferRead on Buffer {
  Future<int> readUint32() async {
    final bytes = await read(4);
    // MP4 box 是 big-endian
    return (bytes[0] << 24) |
           (bytes[1] << 16) |
           (bytes[2] << 8)  |
            bytes[3];
  }
}