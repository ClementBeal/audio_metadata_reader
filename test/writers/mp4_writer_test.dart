import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('updates chunk offsets when metadata grows before mdat', () {
    final Directory directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));

    final File target = File('${directory.path}/writer_source.m4a');
    target
        .writeAsBytesSync(File('test/mp4/writer_source.m4a').readAsBytesSync());

    final Uint8List before = target.readAsBytesSync();
    final List<_TestBox> beforeTopLevel = _readTopLevelBoxes(before);
    final _TestBox beforeMoov =
        beforeTopLevel.singleWhere((_TestBox box) => box.type == 'moov');
    final _TestBox beforeMdat =
        beforeTopLevel.singleWhere((_TestBox box) => box.type == 'mdat');
    final List<int> beforeChunkOffsets =
        _findChunkOffsets(before, beforeMoov.payloadStart, beforeMoov.end);
    final Uint8List audioPayload =
        before.sublist(beforeMdat.payloadStart, beforeMdat.end);

    expect(beforeMoov.start, lessThan(beforeMdat.start));
    expect(beforeChunkOffsets, isNotEmpty);

    Mp4Writer().write(
      target,
      Mp4Metadata(
        title:
            'A deliberately much longer title which changes the size of moov',
        artist: 'Generated artist with a longer value',
      ),
    );

    final Uint8List after = target.readAsBytesSync();
    final List<_TestBox> afterTopLevel = _readTopLevelBoxes(after);
    final _TestBox afterMoov =
        afterTopLevel.singleWhere((_TestBox box) => box.type == 'moov');
    final _TestBox afterMdat =
        afterTopLevel.singleWhere((_TestBox box) => box.type == 'mdat');
    final List<int> afterChunkOffsets =
        _findChunkOffsets(after, afterMoov.payloadStart, afterMoov.end);
    final int moovDelta = afterMoov.size - beforeMoov.size;

    expect(moovDelta, greaterThan(0));
    expect(afterMdat.start - beforeMdat.start, equals(moovDelta));
    expect(afterChunkOffsets,
        equals(beforeChunkOffsets.map((int offset) => offset + moovDelta)));
    expect(after.sublist(afterMdat.payloadStart, afterMdat.end),
        equals(audioPayload));
    expect(readMetadata(target, getImage: false).title,
        contains('deliberately much longer'));
  });

  test('keeps siblings after a full-box meta atom aligned', () {
    final Directory directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));

    final Uint8List meta = _makeBox('meta', <int>[
      ..._u32(0),
      ..._makeBox('hdlr', <int>[]),
      ..._makeBox('ilst', <int>[]),
      ..._makeBox('free', <int>[1, 2, 3, 4]),
    ]);
    final Uint8List sourceBytes = Uint8List.fromList(<int>[
      ..._makeBox('ftyp', <int>[...ascii.encode('M4A '), ..._u32(0)]),
      ..._makeBox('moov', meta),
    ]);
    final File target = File('${directory.path}/meta_sibling.m4a');
    target.writeAsBytesSync(sourceBytes);

    Mp4Writer().write(target, Mp4Metadata(title: 'Updated title'));

    final Uint8List output = target.readAsBytesSync();
    final List<_TestBox> boxes = _readTopLevelBoxes(output);
    final _TestBox moov =
        boxes.singleWhere((_TestBox box) => box.type == 'moov');
    final List<_TestBox> freeBoxes =
        _findBoxes(output, moov.payloadStart, moov.end, 'free');

    expect(freeBoxes.length, equals(1));
    expect(output.sublist(freeBoxes.single.payloadStart, freeBoxes.single.end),
        equals(<int>[1, 2, 3, 4]));
  });

  test('updates 64-bit chunk offsets when moov grows before mdat', () {
    final Directory directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));

    final Uint8List sourceBytes = _makeCo64Fixture();
    final File source = File('${directory.path}/co64_source.m4a');
    source.writeAsBytesSync(sourceBytes);

    final List<_TestBox> beforeTopLevel = _readTopLevelBoxes(sourceBytes);
    final _TestBox beforeMoov =
        beforeTopLevel.singleWhere((_TestBox box) => box.type == 'moov');
    final _TestBox beforeMdat =
        beforeTopLevel.singleWhere((_TestBox box) => box.type == 'mdat');
    final List<int> beforeChunkOffsets =
        _findChunkOffsets(sourceBytes, beforeMoov.payloadStart, beforeMoov.end);

    Mp4Writer().write(
      source,
      Mp4Metadata(title: 'A longer title for the co64 regression test'),
    );

    final Uint8List output = source.readAsBytesSync();
    final List<_TestBox> afterTopLevel = _readTopLevelBoxes(output);
    final _TestBox afterMoov =
        afterTopLevel.singleWhere((_TestBox box) => box.type == 'moov');
    final _TestBox afterMdat =
        afterTopLevel.singleWhere((_TestBox box) => box.type == 'mdat');
    final int moovDelta = afterMoov.size - beforeMoov.size;
    final List<int> afterChunkOffsets =
        _findChunkOffsets(output, afterMoov.payloadStart, afterMoov.end);

    expect(beforeMdat.start, greaterThan(beforeMoov.start));
    expect(afterMdat.start - beforeMdat.start, equals(moovDelta));
    expect(afterChunkOffsets,
        equals(beforeChunkOffsets.map((int offset) => offset + moovDelta)));
  });
}

class _TestBox {
  final int start;
  final int size;
  final String type;

  _TestBox(this.start, this.size, this.type);

  int get payloadStart => start + 8;

  int get end => start + size;
}

List<_TestBox> _readTopLevelBoxes(Uint8List data) {
  return _readBoxes(data, 0, data.length);
}

List<_TestBox> _readBoxes(Uint8List data, int start, int end,
    [String? typeFilter]) {
  final List<_TestBox> boxes = <_TestBox>[];
  int offset = start;

  while (offset < end) {
    final int size = _readU32(data, offset);
    final String type =
        String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    final _TestBox box = _TestBox(offset, size, type);
    if (typeFilter == null || type == typeFilter) {
      boxes.add(box);
    }

    if (_containerTypes.contains(type)) {
      final int childrenStart = type == 'meta' ? offset + 12 : offset + 8;
      boxes.addAll(_readBoxes(data, childrenStart, box.end, typeFilter));
    }
    offset = box.end;
  }

  return boxes;
}

List<_TestBox> _findBoxes(
    Uint8List data, int start, int end, String typeFilter) {
  return _readBoxes(data, start, end, typeFilter);
}

List<int> _findChunkOffsets(Uint8List data, int start, int end) {
  final List<_TestBox> chunkTables = <_TestBox>[];
  chunkTables.addAll(_readBoxes(data, start, end, 'stco'));
  chunkTables.addAll(_readBoxes(data, start, end, 'co64'));

  final List<int> offsets = <int>[];
  for (final _TestBox box in chunkTables) {
    final int entryCount = _readU32(data, box.payloadStart + 4);
    final int entryWidth = box.type == 'stco' ? 4 : 8;
    for (int index = 0; index < entryCount; index++) {
      final int entryOffset = box.payloadStart + 8 + index * entryWidth;
      offsets.add(entryWidth == 4
          ? _readU32(data, entryOffset)
          : ByteData.sublistView(data).getUint64(entryOffset, Endian.big));
    }
  }
  return offsets;
}

Uint8List _makeBox(String type, List<int> payload) {
  final BytesBuilder builder = BytesBuilder();
  builder.add(_u32(payload.length + 8));
  builder.add(ascii.encode(type));
  builder.add(payload);
  return builder.toBytes();
}

Uint8List _makeCo64Fixture() {
  final Uint8List chunkTable = _makeBox('co64', <int>[
    ..._u32(0),
    ..._u32(1),
    ..._u64(0),
  ]);
  final Uint8List stbl = _makeBox('stbl', chunkTable);
  final Uint8List minf = _makeBox('minf', stbl);
  final Uint8List mdia = _makeBox('mdia', minf);
  final Uint8List trak = _makeBox('trak', mdia);
  final Uint8List meta = _makeBox('meta', <int>[
    ..._u32(0),
    ..._makeBox('hdlr', <int>[]),
    ..._makeBox('ilst', <int>[]),
  ]);
  final Uint8List moov = _makeBox('moov', <int>[...trak, ...meta]);
  final Uint8List mdat = _makeBox('mdat', <int>[9, 8, 7, 6]);
  final Uint8List file = Uint8List.fromList(<int>[
    ..._makeBox('ftyp', <int>[...ascii.encode('M4A '), ..._u32(0)]),
    ...moov,
    ...mdat,
  ]);

  final List<_TestBox> boxes = _readTopLevelBoxes(file);
  final _TestBox mdatBox =
      boxes.singleWhere((_TestBox box) => box.type == 'mdat');
  final _TestBox co64Box = _findBoxes(file, 0, file.length, 'co64').single;
  ByteData.sublistView(file)
      .setUint64(co64Box.payloadStart + 8, mdatBox.payloadStart, Endian.big);
  return file;
}

Uint8List _u32(int value) {
  final ByteData data = ByteData(4);
  data.setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _u64(int value) {
  final ByteData data = ByteData(8);
  data.setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _readU32(Uint8List data, int offset) {
  return ByteData.sublistView(data).getUint32(offset, Endian.big);
}

const Set<String> _containerTypes = <String>{
  'moov',
  'trak',
  'mdia',
  'minf',
  'stbl',
  'udta',
  'meta',
  'ilst',
};
