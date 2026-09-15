import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  test('read rejects a large exact read from a truncated file', () {
    final File file = createTemporaryFile(
      'truncated-binary-data',
      Uint8List.fromList([0x01, 0x02, 0x03]),
    );
    final RandomAccessFile reader = file.openSync();
    final Buffer buffer = Buffer(randomAccessFile: reader);

    try {
      expect(
        () => buffer.read(20000),
        throwsA(isA<MetadataParserException>()),
      );
      expect(buffer.fileCursor, equals(0));
    } finally {
      reader.closeSync();
    }
  });

  test('readAtMost returns only the bytes available from a truncated file', () {
    final File file = createTemporaryFile(
      'partial-binary-data',
      Uint8List.fromList([0x01, 0x02, 0x03]),
    );
    final RandomAccessFile reader = file.openSync();
    final Buffer buffer = Buffer(randomAccessFile: reader);

    try {
      expect(buffer.readAtMost(20000), orderedEquals([0x01, 0x02, 0x03]));
      expect(buffer.fileCursor, equals(3));
    } finally {
      reader.closeSync();
    }
  });

  test('read returns a complete large byte range', () {
    final Uint8List expected = Uint8List.fromList(
      List<int>.generate(20000, (int index) => index % 256),
    );
    final File file = createTemporaryFile('large-binary-data', expected);
    final RandomAccessFile reader = file.openSync();
    final Buffer buffer = Buffer(randomAccessFile: reader);

    try {
      expect(buffer.read(20000), orderedEquals(expected));
      expect(buffer.fileCursor, equals(20000));
    } finally {
      reader.closeSync();
    }
  });

  test('read methods reject negative sizes', () {
    final File file = createTemporaryFile(
      'binary-data',
      Uint8List.fromList([0x01]),
    );
    final RandomAccessFile reader = file.openSync();
    final Buffer buffer = Buffer(randomAccessFile: reader);

    try {
      expect(() => buffer.read(-1), throwsArgumentError);
      expect(() => buffer.readAtMost(-1), throwsArgumentError);
    } finally {
      reader.closeSync();
    }
  });
}
