import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../audio_metadata_reader.dart';

class Buffer {
  final RandomAccessFile randomAccessFile;
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
  int get remainingBytes =>
      (_bufferedBytes - _cursor) +
      (randomAccessFile.lengthSync() - randomAccessFile.positionSync());

  Buffer({required this.randomAccessFile}) : _buffer = Uint8List(_bufferSize) {
    _fill();
  }

  void _fill() {
    _bufferedBytes = randomAccessFile.readIntoSync(_buffer);
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
          track: File(""), message: "Expected more data in file");
    }
  }

  Uint8List read(int size) {
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
      randomAccessFile.readIntoSync(result, remaining);
      _fill();
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
  Uint8List readAtMost(int size) {
    final readSize = min(size, remainingBytes);
    return read(readSize);
  }

  void setPositionSync(int position) {
    fileCursor = position;
    randomAccessFile.setPositionSync(position);
    _fill();
  }

  void skip(int length) {
    // Calculate how many bytes we can skip in the current buffer
    final remainingInBuffer = _bufferedBytes - _cursor;

    if (length <= remainingInBuffer) {
      fileCursor += length;

      // If we can skip within the current buffer, just move the cursor
      _cursor += length;
    } else {
      // Calculate the actual file position we need to skip to
      int currentPosition = randomAccessFile.positionSync() - remainingInBuffer;
      fileCursor += currentPosition;
      // Skip to the new position
      randomAccessFile.setPositionSync(currentPosition + length);
      // Refill the buffer at the new position
      _fill();
    }
  }
}


extension BufferRead on Buffer {
  int readUint32() {
    final bytes = read(4);
    // MP4 box 是 big-endian
    return (bytes[0] << 24) |
           (bytes[1] << 16) |
           (bytes[2] << 8)  |
            bytes[3];
  }
}