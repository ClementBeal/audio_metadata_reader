import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

typedef _Header = ({bool isLast, int type, int length});

List<_Header> _readBlocks(File file) {
  final bytes = file.readAsBytesSync();
  expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('fLaC'));

  final headers = <_Header>[];
  var pos = 4;
  while (true) {
    final isLast = bytes[pos] >> 7 == 1;
    final type = bytes[pos] & 0x7F;
    final length = bytes[pos + 3] | bytes[pos + 2] << 8 | bytes[pos + 1] << 16;
    headers.add((isLast: isLast, type: type, length: length));
    pos += 4 + length;
    if (isLast) break;
    expect(pos, lessThan(bytes.length), reason: 'ran past end of file');
  }
  return headers;
}

void main() {
  for (final fixture in ['no_picture.flac', 'picture_last.flac']) {
    group(fixture, () {
      late File target;

      setUp(() {
        final dir = Directory.systemTemp.createTempSync();
        addTearDown(() => dir.deleteSync(recursive: true));
        target = File('${dir.path}/track.flac');
        target.writeAsBytesSync(File('test/flac/$fixture').readAsBytesSync());
      });

      test('every block header carries a valid type', () {
        updateMetadata(target, (m) => m.setTitle('Updated title'));

        for (final block in _readBlocks(target)) {
          expect(block.type, lessThan(7),
              reason: 'type ${block.type} is reserved');
          expect(block.type, isNot(equals(127)));
        }
      });

      test('exactly one last block flag and it is on the final block', () {
        updateMetadata(target, (m) => m.setTitle('Updated title'));

        final blocks = _readBlocks(target);
        expect(blocks.where((b) => b.isLast).length, equals(1));
        expect(blocks.last.isLast, isTrue);
      });

      test('repeated writes stay valid', () {
        for (var i = 0; i < 3; i++) {
          updateMetadata(target, (m) => m.setTitle('Pass $i'));
        }
        expect(readMetadata(target, getImage: false).title, equals('Pass 2'));
        expect(_readBlocks(target).last.isLast, isTrue);
      });

      test('date is written as ISO 8601', () {
        updateMetadata(target, (m) => m.setYear(DateTime(2012, 8, 22)));

        final bytes = target.readAsBytesSync();
        expect(String.fromCharCodes(bytes).contains('DATE=2012-08-22'), isTrue);
        expect(
            String.fromCharCodes(bytes).contains('DATE=2012/08/22'), isFalse);
      });

      test('blocks other than comment and picture survive', () {
        final before =
            _readBlocks(target).where((b) => b.type != 4 && b.type != 6);
        updateMetadata(target, (m) => m.setTitle('Updated title'));
        final after =
            _readBlocks(target).where((b) => b.type != 4 && b.type != 6);

        expect(after.map((b) => b.type).toList(),
            equals(before.map((b) => b.type).toList()));
      });
    });
  }
}
