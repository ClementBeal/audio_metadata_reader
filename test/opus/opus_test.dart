import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

import '../ogg/ogg_page_helpers.dart';

void main() {
  tearDown(deleteTemporaryOggFiles);

  test("Parse OPUS file without the cover", () {
    final track = File('./test/opus/track.opus');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(result.duration, equals(Duration(seconds: 1)));
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
    expect(result.language, isNull);
  });
  test("Parse OPUS file and the cover", () {
    final track = File('./test/opus/track.opus');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Correct duration", () {
    final track = File('./test/opus/real_track_extract.opus');
    final result = readMetadata(track);

    expect(result.duration, Duration(minutes: 3, seconds: 15));
  });

  test("Correct duration of an OPUS file encoded at 16 kHz", () {
    final File track = File('./test/opus/track_16khz.opus');
    final AudioMetadata result = readMetadata(track);

    expect(result.duration, equals(const Duration(milliseconds: 1375)));
  });

  test("LENGTH comment does not overwrite the OPUS duration", () {
    final File track = File('./test/opus/track_length_tag.opus');
    final AudioMetadata result = readMetadata(track);

    expect(result.duration, equals(const Duration(milliseconds: 1375)));
  });

  test("Durations of the OPUS fixtures are read exactly", () {
    const Map<String, int> expectedMicroseconds = <String, int>{
      'track.opus': 1000000,
      'track_16khz.opus': 1375000,
      'real_track_extract.opus': 195000000,
      'track_length_tag.opus': 1375000,
    };

    for (final MapEntry<String, int> entry in expectedMicroseconds.entries) {
      final AudioMetadata result = readMetadata(File('test/opus/${entry.key}'));
      expect(result.duration?.inMicroseconds, entry.value, reason: entry.key);
    }
  });

  group("OPUS file with cover art split over several pages", () {
    final Uint8List image = Uint8List.fromList(
        List<int>.generate(150000, (int i) => Random(i).nextInt(256)));
    late File track;

    setUp(() {
      track = writeTemporaryOgg('art.opus',
          _opusWithSplitPicture('test/opus/track_16khz.opus', image));
    });

    test("keeps tags and duration without fetching the picture", () {
      final AudioMetadata result = readMetadata(track, getImage: false);

      expect(result.title, 'Before');
      expect(result.artist, 'After');
      expect(result.album, 'Album');
      expect(result.duration, const Duration(milliseconds: 1375));
      expect(result.pictures, isEmpty);
    });

    test("returns the picture bytes and mime when fetching images", () {
      final AudioMetadata result = readMetadata(track, getImage: true);

      expect(result.title, 'Before');
      expect(result.artist, 'After');
      expect(result.album, 'Album');
      expect(result.duration, const Duration(milliseconds: 1375));
      expect(result.pictures, hasLength(1));
      expect(result.pictures.first.mimetype, 'image/jpeg');
      expect(result.pictures.first.pictureType, PictureType.coverFront);
      expect(result.pictures.first.bytes, image);
    });

    test("readAllMetadata gives the same tags with and without the picture",
        () {
      final VorbisMetadata withImage =
          readAllMetadata(track, getImage: true) as VorbisMetadata;
      final VorbisMetadata withoutImage =
          readAllMetadata(track, getImage: false) as VorbisMetadata;

      expect(withoutImage.title, withImage.title);
      expect(withoutImage.artist, withImage.artist);
      expect(withoutImage.album, withImage.album);
      expect(withoutImage.duration, withImage.duration);
      expect(withImage.pictures, hasLength(1));
      expect(withoutImage.pictures, isEmpty);
    });
  });

  test("OPUS cover art ending exactly at a page end keeps the following tags",
      () {
    // 43 bytes of header and TITLE, then 4 + 23 + 129,980 bytes of picture
    // comment: the picture ends exactly at the end of the second tag page
    // (2 * 255 * 255 bytes), and ARTIST starts on the third one.
    final Uint8List image = Uint8List(97443);
    final File track = writeTemporaryOgg('boundary.opus',
        _opusWithSplitPicture('test/opus/track_16khz.opus', image));

    for (final bool getImage in <bool>[false, true]) {
      final AudioMetadata result = readMetadata(track, getImage: getImage);

      expect(result.title, 'Before', reason: 'getImage: $getImage');
      expect(result.artist, 'After', reason: 'getImage: $getImage');
      expect(result.album, 'Album', reason: 'getImage: $getImage');
      expect(result.duration, const Duration(milliseconds: 1375));
      expect(result.pictures, hasLength(getImage ? 1 : 0));
    }
  });

  test(
      "Truncated OPUS file without end of stream reads the duration of its "
      "last complete page (regression: used to throw)", () {
    final Uint8List bytes =
        File('test/opus/real_track_extract.opus').readAsBytesSync();
    final List<OggTestPage> pages = readOggPages(bytes);
    // Cut in the middle of the fifth page from the end.
    final OggTestPage cutPage = pages[pages.length - 5];
    final OggTestPage lastComplete = pages[pages.length - 6];
    final File track = writeTemporaryOgg(
        'truncated.opus', bytes.sublist(0, cutPage.offset + 100));

    final AudioMetadata result = readMetadata(track);

    final int removedSamples = pages.last.granule - lastComplete.granule;
    expect(
      result.duration!.inMicroseconds,
      closeTo(195000000 - removedSamples * 1000000 / 48000, 1),
    );
  });

  test(
      "OPUS file followed by more than 64 KiB of other data keeps its duration",
      () {
    final Uint8List bytes =
        File('test/opus/real_track_extract.opus').readAsBytesSync();
    final File track = writeTemporaryOgg(
        'trailing.opus', <int>[...bytes, ...List<int>.filled(70000, 0x5A)]);

    final AudioMetadata result = readMetadata(track);

    expect(result.duration, const Duration(minutes: 3, seconds: 15));
  });

  test("OPUS pages appended without granule or from another stream are ignored",
      () {
    final Uint8List bytes =
        File('test/opus/real_track_extract.opus').readAsBytesSync();
    final int serial = readOggPages(bytes).first.serial;
    final File track = writeTemporaryOgg('appended.opus', <int>[
      ...bytes,
      ...buildOggPage(
        headerType: 0,
        granule: -1,
        serial: serial,
        sequence: 10000,
        segmentSizes: <int>[100],
        body: List<int>.filled(100, 1),
      ),
      ...buildOggPage(
        headerType: 0x06,
        granule: 99999999,
        serial: serial + 1,
        sequence: 0,
        segmentSizes: <int>[100],
        body: List<int>.filled(100, 2),
      ),
    ]);

    final AudioMetadata result = readMetadata(track);

    expect(result.duration, const Duration(minutes: 3, seconds: 15));
  });
}

/// Copy of the Opus file at [path] whose OpusTags packet holds a TITLE, a
/// METADATA_BLOCK_PICTURE with [image] laced over several pages, then an
/// ARTIST and an ALBUM.
Uint8List _opusWithSplitPicture(String path, Uint8List image) {
  final List<OggTestPage> pages = readOggPages(File(path).readAsBytesSync());
  expect(String.fromCharCodes(pages[1].body, 0, 8), 'OpusTags');
  expect(pages[2].headerType & 0x01, 0, reason: 'tags fit on one page');

  const String mime = 'image/jpeg';
  final ByteData pictureHeader = ByteData(8 + mime.length + 4 + 16 + 4);
  int offset = 0;
  pictureHeader.setUint32(offset, 3); // front cover
  pictureHeader.setUint32(offset += 4, mime.length);
  offset += 4;
  for (final int unit in mime.codeUnits) {
    pictureHeader.setUint8(offset++, unit);
  }
  pictureHeader.setUint32(offset, 0); // empty description
  offset += 4 + 16; // width, height, depth, colors
  pictureHeader.setUint32(offset, image.length);
  final String picture =
      base64Encode(<int>[...pictureHeader.buffer.asUint8List(), ...image]);

  final List<String> comments = <String>[
    'TITLE=Before',
    'METADATA_BLOCK_PICTURE=$picture',
    'ARTIST=After',
    'ALBUM=Album',
  ];
  final BytesBuilder tags = BytesBuilder()..add(ascii.encode('OpusTags'));
  void addString(String value) {
    final List<int> encoded = utf8.encode(value);
    tags
      ..add((ByteData(4)..setUint32(0, encoded.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(encoded);
  }

  addString('test vendor');
  tags.add((ByteData(4)..setUint32(0, comments.length, Endian.little))
      .buffer
      .asUint8List());
  comments.forEach(addString);

  final List<Uint8List> tagPages = buildPacketPages(
      packet: tags.takeBytes(), serial: pages.first.serial, firstSequence: 1);
  expect(tagPages.length, greaterThan(2));

  return Uint8List.fromList(<int>[
    ...renumberOggPage(pages[0], 0),
    for (final Uint8List page in tagPages) ...page,
    for (int i = 2; i < pages.length; i++)
      ...renumberOggPage(pages[i], tagPages.length + i - 1),
  ]);
}
