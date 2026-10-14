import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    show AudioMetadata, MetadataParserException;
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  // Reuse the checked-in MP3 payload generated with ffmpeg. Only the APEv2
  // metadata is built here, so these tests do not need ffmpeg at runtime.
  for (final int byteLength in <int>[255, 256, 257, 511, 512, 513, 65536]) {
    for (final bool useMultibyteText in <bool>[false, true]) {
      for (final bool titleFirst in <bool>[true, false]) {
        test(
            'preserves a $byteLength-byte ${useMultibyteText ? 'UTF-8' : 'ASCII'} '
            'APE title ${titleFirst ? 'before' : 'after'} another item', () {
          // Each accented character occupies two UTF-8 bytes. An ASCII suffix
          // keeps odd byte lengths exact without truncating a character.
          final String title = useMultibyteText
              ? '${List<String>.filled(byteLength ~/ 2, 'é').join()}'
                  '${byteLength.isOdd ? 'T' : ''}'
              : List<String>.filled(byteLength, 'T').join();
          final File file = _createApeTaggedTrack(textItems: <String, String>{
            if (!titleFirst) 'Album': 'Before title',
            'Title': title,
            'Artist': 'After title',
          });
          addTearDown(() => file.parent.deleteSync(recursive: true));

          final AudioMetadata metadata = readMetadata(file, getImage: false);
          final ApeMetadata allMetadata =
              readAllMetadata(file, getImage: false) as ApeMetadata;

          expect(metadata.title, equals(title));
          expect(metadata.artist, equals('After title'));
          expect(allMetadata.title, equals(title));
          expect(allMetadata.artist, equals('After title'));
          if (!titleFirst) {
            expect(metadata.album, equals('Before title'));
            expect(allMetadata.album, equals('Before title'));
          }
        });
      }
    }
  }

  test('reads the next APE item after an empty title', () {
    final File file = _createApeTaggedTrack(textItems: <String, String>{
      'Title': '',
      'Artist': 'After empty title',
    });
    addTearDown(() => file.parent.deleteSync(recursive: true));

    final AudioMetadata metadata = readMetadata(file, getImage: false);

    expect(metadata.title, isNull);
    expect(metadata.artist, equals('After empty title'));
  });

  test('rejects an APE value extending beyond the footer', () {
    final Uint8List baseAudio =
        File('test/ape/base_no_tag.mp3').readAsBytesSync();
    final Uint8List tag = _buildApeTag(textItems: <String, String>{
      'Title': 'Truncated title',
    });
    // The declared value cannot fit before the footer. Neither exact parsing
    // nor padding recovery may consume the footer as part of the title.
    tag.setRange(0, 4, intToUint32LE(0xFFFFFFFF));
    final File file = createTemporaryFile(
        'ape_truncated.mp3', Uint8List.fromList(<int>[...baseAudio, ...tag]));
    addTearDown(() => file.parent.deleteSync(recursive: true));

    expect(() => readMetadata(file, getImage: false),
        throwsA(isA<MetadataParserException>()));
    expect(() => readAllMetadata(file, getImage: false),
        throwsA(isA<MetadataParserException>()));
  });

  test("Parse APEv2 text metadata from an MP3 payload", () {
    final file = _createApeTaggedTrack(
      textItems: {
        'Title': 'APE title',
        'Artist': 'APE artist',
        'Album': 'APE album',
        'Track': '2/9',
        'TrackTotal': '9',
        'Disc': '1/2',
        'DiscTotal': '2',
        'Genre': 'Rock',
        'Year': '2014',
        'Lyrics': 'Hello from APE',
      },
    );

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.title, equals('APE title'));
    expect(metadata.artist, equals('APE artist'));
    expect(metadata.album, equals('APE album'));
    expect(metadata.trackNumber, equals(2));
    expect(metadata.trackTotal, equals(9));
    expect(metadata.discNumber, equals(1));
    expect(metadata.totalDisc, equals(2));
    expect(metadata.lyrics, equals('Hello from APE'));
    expect(metadata.genres, equals(['Rock']));
    expect(metadata.year, equals(DateTime(2014)));
  });

  test("Parse APEv2 cover item when images are requested", () {
    final coverBytes = File('test/data/cover.png').readAsBytesSync();

    final file = _createApeTaggedTrack(
      textItems: {'Title': 'APE title'},
      coverBytes: coverBytes,
    );

    final metadata = readMetadata(file, getImage: true);

    expect(metadata.pictures.length, equals(1));
    expect(metadata.pictures.first.mimetype, equals('image/png'));
    expect(metadata.pictures.first.pictureType, equals(PictureType.coverFront));
    expect(metadata.pictures.first.bytes, equals(coverBytes));
  });

  test("APEv2 footer can be found before a trailing ID3v1 tag", () {
    final file = _createApeTaggedTrack(
      textItems: {'Title': 'APE title before ID3v1'},
      appendId3v1Trailer: true,
    );

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.title, equals('APE title before ID3v1'));
  });

  test("readAllMetadata returns ApeMetadata for APEv2 tags", () {
    final file = _createApeTaggedTrack(
      textItems: {
        'Artist': 'Artist A',
        'Track': '3',
      },
    );

    final allMetadata = readAllMetadata(file, getImage: false);

    expect(allMetadata, isA<ApeMetadata>());

    final apeMetadata = allMetadata as ApeMetadata;
    expect(apeMetadata.artist, equals('Artist A'));
    expect(apeMetadata.trackNumber, equals(3));
  });

  test("recovers APEv2 items when padding and item count are stale", () {
    final baseAudio = File('test/ape/base_no_tag.mp3').readAsBytesSync();
    final itemChunks = <int>[
      // These bytes model the harmless padding before the first item.
      0x00,
      0x00,
      ..._buildTextItem('Title', 'Padded APE title'),
      // Also exercise recovery inside the tag and before the footer, where
      // the stale count asks the parser to read one more item than exists.
      0x00,
      0x00,
      ..._buildTextItem('Artist', 'Padded APE artist'),
      0x00,
      0x00,
    ];

    final footer = <int>[
      ...ascii.encode('APETAGEX'),
      ...intToUint32LE(2000),
      // Deliberately exclude the two leading padding bytes, as in the
      // affected file.
      ...intToUint32LE(itemChunks.length - 2 + 32),
      // Deliberately stale: only two items are present.
      ...intToUint32LE(3),
      ...intToUint32LE(0x80000000), // header-present flag
      ...List.filled(8, 0),
    ];

    final file = createTemporaryFile(
      'ape_padded.mp3',
      Uint8List.fromList([...baseAudio, ...itemChunks, ...footer]),
    );

    final metadata = readMetadata(file, getImage: false);

    expect(metadata.title, equals('Padded APE title'));
    expect(metadata.artist, equals('Padded APE artist'));
  });
}

File _createApeTaggedTrack({
  required Map<String, String> textItems,
  Uint8List? coverBytes,
  bool appendId3v1Trailer = false,
}) {
  final baseAudio = File('test/ape/base_no_tag.mp3').readAsBytesSync();
  final apeTag = _buildApeTag(textItems: textItems, coverBytes: coverBytes);

  final content = <int>[
    ...baseAudio,
    ...apeTag,
    if (appendId3v1Trailer) ..._buildEmptyId3v1Tag(),
  ];

  return createTemporaryFile('ape_tagged.mp3', Uint8List.fromList(content));
}

Uint8List _buildApeTag({
  required Map<String, String> textItems,
  Uint8List? coverBytes,
}) {
  final itemChunks = <int>[];
  int itemCount = 0;

  for (final entry in textItems.entries) {
    itemChunks.addAll(_buildTextItem(entry.key, entry.value));
    itemCount += 1;
  }

  if (coverBytes != null) {
    itemChunks.addAll(_buildCoverItem(coverBytes));
    itemCount += 1;
  }

  // APEv2 footer only (no header):
  // size = items + footer.
  final footerSize = itemChunks.length + 32;
  final footer = <int>[
    ...ascii.encode('APETAGEX'),
    ...intToUint32LE(2000), // version 2.000
    ...intToUint32LE(footerSize),
    ...intToUint32LE(itemCount),
    ...intToUint32LE(0), // tag flags
    ...List.filled(8, 0), // reserved
  ];

  return Uint8List.fromList([...itemChunks, ...footer]);
}

Uint8List _buildTextItem(String key, String value) {
  final keyBytes = ascii.encode(key);
  final valueBytes = utf8.encode(value);

  return Uint8List.fromList([
    ...intToUint32LE(valueBytes.length),
    ...intToUint32LE(0), // item type = text
    ...keyBytes,
    0x00, // NUL key terminator
    ...valueBytes,
  ]);
}

Uint8List _buildCoverItem(Uint8List imageBytes) {
  final keyBytes = ascii.encode('Cover Art (Front)');
  final descriptor = ascii.encode('cover.png');
  final valueBytes = <int>[...descriptor, 0x00, ...imageBytes];

  return Uint8List.fromList([
    ...intToUint32LE(valueBytes.length),
    ...intToUint32LE(0x00000002), // item type = binary (bits 1..2)
    ...keyBytes,
    0x00,
    ...valueBytes,
  ]);
}

Uint8List _buildEmptyId3v1Tag() {
  return Uint8List.fromList([
    ...ascii.encode('TAG'),
    ...List.filled(125, 0),
  ]);
}
