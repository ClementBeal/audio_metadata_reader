import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:test/test.dart';

import 'ogg_page_helpers.dart';

void main() {
  tearDown(deleteTemporaryOggFiles);

  test("Parse OGG file without the cover", () {
    final track = File('./test/ogg/track.ogg');
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
  test("Parse FLAC file and the cover", () {
    final track = File('./test/ogg/track.ogg');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Duration of the Vorbis fixture is read exactly", () {
    final AudioMetadata result = readMetadata(File('test/ogg/track.ogg'));

    expect(result.duration?.inMicroseconds, 1000000);
  });

  test(
      "Truncated Vorbis file without end of stream reads the duration of its "
      "last complete page (regression: used to throw)", () {
    final Uint8List bytes = File('test/ogg/track.ogg').readAsBytesSync();
    final List<OggTestPage> pages = readOggPages(bytes);
    final File track = writeTemporaryOgg(
        'truncated.ogg', bytes.sublist(0, pages.last.offset + 100));

    final AudioMetadata result = readMetadata(track);

    final int lastCompleteGranule = pages[pages.length - 2].granule;
    expect(
      result.duration!.inMicroseconds,
      closeTo(lastCompleteGranule * 1000000 / 48000, 1),
    );
    expect(result.title, "Title");
  });

  test(
      "Vorbis file followed by more than 64 KiB of other data keeps its "
      "duration", () {
    final Uint8List bytes = File('test/ogg/track.ogg').readAsBytesSync();
    final File track = writeTemporaryOgg(
        'trailing.ogg', <int>[...bytes, ...List<int>.filled(70000, 0x5A)]);

    final AudioMetadata result = readMetadata(track);

    expect(result.duration, const Duration(seconds: 1));
  });
}
