import 'dart:io';
import 'dart:typed_data';

class Buffer {
  final RandomAccessFile randomAccessFile;
  final Uint8List _buffer;
  int _cursor = 0;
  static final int _bufferSize = 16384;

  Buffer({required this.randomAccessFile}) : _buffer = Uint8List(16384) {
    _fill();
  }

  void _fill() {
    randomAccessFile.readIntoSync(_buffer);
    _cursor = 0;
  }

  Uint8List read(int size) {
    // if we read something big (~100kb), we can read it directly from file
    // it makes the read faster
    // no need to use the buffer
    if (size > _bufferSize) {
      final result = Uint8List(size);
      final remaining = _bufferSize - _cursor;

      if (remaining > 0) {
        result.setRange(0, remaining, _buffer, _cursor);
      }

      randomAccessFile.readIntoSync(result, remaining);

      _fill();
      return result;
    }

    if (size <= _bufferSize - _cursor) {
      // Data fits within the current buffer
      final result = _buffer.sublist(_cursor, _cursor + size);
      _cursor += size;
      return result;
    } else {
      // Data exceeds remaining buffer, needs refill
      final result = Uint8List(size);
      int remaining = _bufferSize - _cursor;

      // Copy remaining data from the buffer
      for (int i = 0; i < remaining; i++) {
        result[i] = _buffer[_cursor + i];
      }

      // Refill the buffer and adjust the cursor
      _fill();
      int filled = remaining;

      // Continue filling `result` with new buffer data
      while (filled < size) {
        int toCopy = size - filled;
        if (toCopy > _bufferSize) {
          toCopy = _bufferSize;
        }
        result.setRange(filled, filled + toCopy, _buffer, 0);
        filled += toCopy;
        _cursor = toCopy;

        // Fill buffer again if more data is needed
        if (filled < size) {
          _fill();
        }
      }
      return result;
    }
  }

  void setPositionSync(int position) {
    // Set the file position in the RandomAccessFile
    randomAccessFile.setPositionSync(position);

    // Reset the buffer by filling it with data starting at the new position
    _fill();
  }

  void skip(int length) {
    if (length <= _bufferSize - _cursor) {
      // If we can skip within the current buffer, just move the cursor
      _cursor += length;
    } else {
      // Calculate the actual file position we need to skip to
      int currentPosition =
          randomAccessFile.positionSync() - (_bufferSize - _cursor);
      randomAccessFile.setPositionSync(currentPosition + length);
      _fill();
    }
  }
}
