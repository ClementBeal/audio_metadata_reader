import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('readAllMetadata supports WAV/RIFF files', () {
    final track = File('./test/wav/track.wav');
    final metadata = readAllMetadata(track, getImage: false);

    expect(metadata, isA<RiffMetadata>());

    final riffMetadata = metadata as RiffMetadata;
    expect(riffMetadata.title, equals('Le Crou ne mourra jamais (intro)'));
    expect(riffMetadata.artist, equals('Stupeflip'));
  });

  test('updateMetadata works on WAV files through readAllMetadata', () {
    final tempDir = Directory.systemTemp.createTempSync();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final target = File('${tempDir.path}/track.wav');
    target.writeAsBytesSync(File('test/wav/track.wav').readAsBytesSync());

    updateMetadata(target, (metadata) {
      (metadata as RiffMetadata).title = 'Updated via updateMetadata';
    });

    final updated = readAllMetadata(target, getImage: false) as RiffMetadata;
    expect(updated.title, equals('Updated via updateMetadata'));
  });

  test('readAllMetadata exposes WAV ID3 chunk values in RiffMetadata', () {
    final track = File('test/wav/track_id3.wav');
    expect(track.existsSync(), isTrue);

    final metadata = readAllMetadata(track, getImage: false);
    expect(metadata, isA<RiffMetadata>());

    final riffMetadata = metadata as RiffMetadata;
    expect(riffMetadata.title, equals('WAV ID3 Chunk Title'));
    expect(riffMetadata.artist, equals('WAV ID3 Chunk Artist'));
    expect(riffMetadata.album, equals('WAV ID3 Chunk Album'));
    expect(riffMetadata.trackNumber, equals(7));
    expect(riffMetadata.year, equals(DateTime(2014)));
    expect(riffMetadata.genre, equals('Rock'));
    expect(riffMetadata.publisher, equals('WAV ID3 Chunk Publisher'));
    expect(riffMetadata.copyright, equals('WAV ID3 Chunk Copyright'));
  });

  test('readAllMetadata preserves unknown RIFF chunks and INFO fields', () {
    final tempDir = Directory.systemTemp.createTempSync();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final original = File('test/wav/track.wav').readAsBytesSync();
    final unknownChunk = _riffChunk('JUNK', <int>[0x10, 0x20, 0x30]);
    final unknownInfo = _riffListInfoChunk('ICUS', 'Vendor value');
    final target = File('${tempDir.path}/track-with-unknowns.wav')
      ..writeAsBytesSync(<int>[...original, ...unknownChunk, ...unknownInfo]);

    final metadata = readAllMetadata(target, getImage: false) as RiffMetadata;

    expect(metadata.unknowns['ICUS'], equals('Vendor value'));
    expect(metadata.unknownChunks, hasLength(1));
    expect(metadata.unknownChunks.single.id, equals('JUNK'));
    expect(metadata.unknownChunks.single.data,
        equals(Uint8List.fromList(<int>[0x10, 0x20, 0x30])));
  });

  test('rewriting WAV metadata keeps unknown INFO fields', () {
    final tempDir = Directory.systemTemp.createTempSync();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final unknownInfo = _riffListInfoChunk('ICUS', 'Vendor value');
    final target = File('${tempDir.path}/track-with-unknown-info.wav')
      ..writeAsBytesSync(_minimalRiffFile(unknownInfo));

    updateMetadata(target, (metadata) {
      (metadata as RiffMetadata).title = 'Updated title';
    });

    final updated = readAllMetadata(target, getImage: false) as RiffMetadata;
    expect(updated.title, equals('Updated title'));
    expect(updated.unknowns['ICUS'], equals('Vendor value'));
  });
}

List<int> _riffChunk(String id, List<int> data) {
  final payload = List<int>.from(data);
  final declaredSize = payload.length;
  if (payload.length.isOdd) {
    payload.add(0);
  }

  return <int>[
    ...id.codeUnits,
    ..._littleEndianUint32(declaredSize),
    ...payload,
  ];
}

List<int> _riffListInfoChunk(String id, String value) {
  final infoEntry = _riffChunk(id, <int>[...value.codeUnits, 0]);
  final payload = <int>[...'INFO'.codeUnits, ...infoEntry];
  return _riffChunk('LIST', payload);
}

List<int> _minimalRiffFile(List<int> additionalChunk) {
  final format = _riffChunk('fmt ', <int>[
    1,
    0,
    1,
    0,
    0x44,
    0xAC,
    0,
    0,
    0x88,
    0x58,
    1,
    0,
    2,
    0,
    16,
    0,
  ]);
  final audio = _riffChunk('data', <int>[0, 0]);
  final payload = <int>[
    ...'WAVE'.codeUnits,
    ...format,
    ...additionalChunk,
    ...audio,
  ];

  return <int>[
    ...'RIFF'.codeUnits,
    ..._littleEndianUint32(payload.length),
    ...payload,
  ];
}

List<int> _littleEndianUint32(int value) {
  return <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}
