import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:test/test.dart';

void main() {
  test("Parse MP4 file without the cover", () {
    final track = File('./test/mp4/track.m4a');
    final result = readMetadata(track, getImage: false);

    expect(result.album, equals("Album"));
    expect(result.artist, equals("Artist"));
    expect(result.discNumber, equals(1));
    expect(result.sampleRate, equals(48000));
    expect(result.title, equals("Title"));
    expect(result.trackNumber, equals(1));
    expect(
      result.duration!.inMicroseconds -
          Duration(microseconds: 1021333).inMicroseconds,
      lessThanOrEqualTo(1000000),
    );
    expect(result.totalDisc, equals(1));
    expect(result.lyrics, equals("Lyrics"));
    expect(result.trackTotal, equals(10));
    expect(result.genres.length, equals(1));
    expect(result.genres.first, equals("Rock"));
  });
  test("Parse MP4 file and the cover", () {
    final track = File('./test/mp4/track.m4a');
    final result = readMetadata(track, getImage: true);

    expect(result.pictures.length, 1);
    expect(result.pictures.first.mimetype, "image/png");
    expect(result.pictures.first.pictureType, PictureType.coverFront);
    expect(result.pictures.first.bytes,
        File("test/data/cover.png").readAsBytesSync());
  });

  test("Complex date", () {
    final track = File('./test/mp4/ahah.m4a');
    final result = readMetadata(track, getImage: true);

    expect(result.title, "Sexy Ladies (Remix) [feat. 50 Cent]");
    expect(result.album, "FutureSex/LoveSounds (Deluxe Edition)");
    expect(result.artist, "Justin Timberlake");
    expect(result.year, DateTime.utc(2006, 9, 12));
    expect(result.trackNumber, 15);
    expect(result.trackTotal, 15);
  });

  test("Should work with .mov file", () {
    final track = File('./test/mp4/track.mov');
    final result = readMetadata(track, getImage: false);

    expect(result.title, "Blue Test Pattern");
    expect(result.artist, "FFmpeg Generator");
    expect(result.year, (DateTime(2023, 10, 27)));
  });

  test("Parse chapters from chpl atom", () {
    final track = _createMp4WithChplChapters();
    addTearDown(() {
      if (track.existsSync()) {
        track.deleteSync();
      }
    });

    final allMetadata = readAllMetadata(track, getImage: false) as Mp4Metadata;

    expect(allMetadata.chapters.length, 3);
    expect(allMetadata.chapters[0].title, "Intro");
    expect(allMetadata.chapters[0].start, Duration.zero);
    expect(allMetadata.chapters[1].title, "Part 1");
    expect(allMetadata.chapters[1].start, Duration(seconds: 2));
    expect(allMetadata.chapters[2].title, "Outro");
    expect(allMetadata.chapters[2].start, Duration(seconds: 4));

    final metadata = readMetadata(track, getImage: false);
    expect(metadata.chapters.length, 3);
    expect(metadata.chapters[0].title, "Intro");
    expect(metadata.chapters[0].start, Duration.zero);
  });
}

File _createMp4WithChplChapters() {
  final bytes = BytesBuilder();

  // Minimal MP4 layout for this parser:
  // root -> ftyp + moov, and moov -> udta -> chpl.
  bytes.add(_makeBox("ftyp", [
    ...ascii.encode("M4A "),
    ..._u32(0),
    ...ascii.encode("isom"),
    ...ascii.encode("M4A "),
  ]));

  final chapters = [
    (start: Duration.zero, title: "Intro"),
    (start: Duration(seconds: 2), title: "Part 1"),
    (start: Duration(seconds: 4), title: "Outro"),
  ];

  final chplPayload = BytesBuilder();
  chplPayload.add(_u32(0)); // version + flags
  chplPayload.add(_u32(0)); // reserved bytes found in common `chpl` layout
  chplPayload.addByte(chapters.length);

  for (final chapter in chapters) {
    // chpl timestamps are stored in 100ns units.
    chplPayload.add(_u64(chapter.start.inMicroseconds * 10));
    final titleBytes = utf8.encode(chapter.title);
    chplPayload.addByte(titleBytes.length);
    chplPayload.add(titleBytes);
  }

  final udta = _makeBox("udta", _makeBox("chpl", chplPayload.toBytes()));
  final moov = _makeBox("moov", udta);
  bytes.add(moov);

  // Temporary file to keep tests hermetic and avoid static binary fixtures.
  final file = File(
      "${Directory.systemTemp.path}/audio_metadata_reader_chpl_test_${DateTime.now().microsecondsSinceEpoch}.m4a");
  file.writeAsBytesSync(bytes.toBytes(), flush: true);

  return file;
}

Uint8List _makeBox(String type, List<int> payload) {
  final builder = BytesBuilder();
  builder.add(_u32(payload.length + 8));
  builder.add(ascii.encode(type));
  builder.add(payload);

  return builder.toBytes();
}

Uint8List _u32(int value) {
  final data = ByteData(4);
  data.setUint32(0, value);

  return data.buffer.asUint8List();
}

Uint8List _u64(int value) {
  final data = ByteData(8);
  data.setUint64(0, value);

  return data.buffer.asUint8List();
}
