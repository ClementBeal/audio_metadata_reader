// Regression tests for truncated or empty MP4 tag atoms.
//
// A tag atom (`©nam`, `aART`, `trkn`, ...) stores its value in a nested `data`
// box. Encoders that abort a write, or that emit placeholder atoms, can leave
// the box without a value. Slicing such a payload used to throw a `RangeError`
// that surfaced as `MetadataParserException` for the whole file, so a single
// broken atom made the track unreadable.
//
// Every file below is built in code, so these tests need no audio fixture.
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  test('text atom with only a `data` box header is ignored', () {
    // Payload is 8 bytes: the nested `data` box has no version/flags, locale
    // or value, so the atom cannot carry a tag.
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box('aART', mp4Box('data', <int>[])),
      mp4TextAtom('\u00A9nam', 'Title'),
    ]);
    addTearDown(() => file.deleteSync());

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.title, equals('Title'));
    expect(metadata.albumArtist, isNull);
  });

  test('text atom with a `data` box header and version/flags is ignored', () {
    // Payload is 12 bytes: the locale field and the value are missing.
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box('aART', mp4Box('data', mp4Uint32(1))),
    ]);
    addTearDown(() => file.deleteSync());

    expect(readMetadata(file, getImage: false).albumArtist, isNull);
  });

  test('text atom with an empty value stays null instead of becoming empty',
      () {
    // Payload is 16 bytes: the `data` box is complete but holds no value.
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box('aART', mp4Box('data', <int>[...mp4Uint32(1), ...mp4Uint32(0)])),
    ]);
    addTearDown(() => file.deleteSync());

    final metadata = readMetadata(file, getImage: false);

    // `''` would look like a real tag whose value was cleared, so the parser
    // leaves the field null when the atom carries nothing.
    expect(metadata.albumArtist, isNull);
  });

  test('atom payload shorter than a `data` box header is skipped', () {
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box('aART', <int>[1, 2, 3, 4]),
      mp4TextAtom('\u00A9nam', 'Title'),
    ]);
    addTearDown(() => file.deleteSync());

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.title, equals('Title'));
    expect(metadata.albumArtist, isNull);
  });

  test('`trkn` value shorter than a track/total pair is ignored', () {
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box(
          'trkn',
          mp4Box('data', <int>[
            ...mp4Uint32(0),
            ...mp4Uint32(0),
            0x00,
            0x01,
            0x00,
          ])),
    ]);
    addTearDown(() => file.deleteSync());

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.trackNumber, isNull);
    expect(metadata.trackTotal, isNull);
  });

  test('`disk` value shorter than a disc/total pair is ignored', () {
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box(
          'disk',
          mp4Box('data', <int>[
            ...mp4Uint32(0),
            ...mp4Uint32(0),
            0x00,
            0x01,
          ])),
    ]);
    addTearDown(() => file.deleteSync());

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.discNumber, isNull);
    expect(metadata.totalDisc, isNull);
  });

  test('tag atom without a nested `data` box keeps its fallback layout', () {
    // Some encoders store the value after a 4-byte size and no `data` box.
    // The parser must keep reading that layout instead of dropping the atom.
    final file = buildMinimalMp4(<Uint8List>[
      mp4Box('aART', <int>[
        0x00,
        0x00,
        0x00,
        0x08, // size prefix
        ...'ABCD'.codeUnits,
      ]),
    ]);
    addTearDown(() => file.deleteSync());

    expect(readMetadata(file, getImage: false).albumArtist, equals('ABCD'));
  });
}
