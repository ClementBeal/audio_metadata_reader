import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  test("Parse MP3 file without the cover", () {
    final track = File('./test/mp3/track.mp3');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(result.duration!.inMilliseconds, closeTo(1130, 10));
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
  });

  test("Parse MP3 file and the cover", () {
    final track = File('./test/mp3/track.mp3');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Check if we skip correctly the images", () {
    final track = File("./test/mp3/caress-your-soul-cleaned.mp3");
    final result = readMetadata(track, getImage: false);

    expect(result.pictures.length, 0);
    expect(result.album, "Caress Your Soul");
    expect(result.title, "How to Fly");
    expect(result.artist, "Sticky Fingers");
    expect(result.year, DateTime(2013));
    expect(
        result.duration, Duration(minutes: 3, seconds: 22, milliseconds: 240));
    expect(result.sampleRate, 44100);
  });

  test("Parses from truncated mp3 file", () {
    // The caress-your-soul-truncated-cleaned.mp3 file is truncated
    // immediately before the Xing header. We should still be able
    // to read the ID3 tag data.
    final track = File("./test/mp3/caress-your-soul-cleaned-truncated.mp3");
    final result = readMetadata(track, getImage: false);
    expect(result.pictures.length, 0);
    expect(result.album, "Caress Your Soul");
    expect(result.title, "How to Fly");
    expect(result.artist, "Sticky Fingers");
    expect(result.year, DateTime(2013));
    expect(result.sampleRate, 44100);
  });

  test("Round duration to microseconds", () {
    final track = File("./test/mp3/generated_under_one_second.mp3");
    final result = readMetadata(track, getImage: false);
    expect(result.pictures.length, 0);
    expect(result.duration, isNotNull);
    expect(result.duration!.inMilliseconds, closeTo(310, 5));
  });

  test("Parse an MP3 without ID3 metadata", () {
    final track = File('./test/mp3/no_metadata.mp3');
    final result = readMetadata(track, getImage: false);

    expect(result.title, isNull);
    expect(result.artist, isNull);
    expect(result.sampleRate, equals(44100));
    expect(result.bitrate, equals(64000));
    expect(result.duration, isNotNull);
  });

  test("Parse MP3 sample rate from MPEG frame header", () {
    final track = File('./test/mp3/no_metadata_48k.mp3');
    final result = readMetadata(track, getImage: false);

    expect(result.sampleRate, equals(48000));
  });

  test("Reads audio after consecutive ID3v2 tags", () {
    // The second tag starts with bytes that resemble a valid MPEG header. The
    // observable result must still describe the real MPEG stream after both
    // tags, rather than the tag payload.
    final bytes = BytesBuilder(copy: false)
      ..add(_id3v2Header(size: 0))
      ..add(_id3v2Header(size: 4))
      ..add([0xFF, 0xFB, 0xE4, 0x00])
      ..add(File('./test/mp3/generated_stacked_id3v2_audio.mp3')
          .readAsBytesSync());
    final track = createTemporaryFile('consecutive-id3v2.mp3', bytes.toBytes());

    final result = readMetadata(track, getImage: false);

    expect(result.sampleRate, equals(44100));
    expect(result.bitrate, equals(64000));
    expect(result.duration, isNotNull);
  });
}

Uint8List _id3v2Header({required int size}) {
  return Uint8List.fromList([
    0x49, 0x44, 0x33, // "ID3"
    0x04, 0x00, 0x00, // ID3v2.4, revision 0, no flags
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ]);
}
