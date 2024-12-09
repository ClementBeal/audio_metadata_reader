import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/writers/id3v4_writer.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group(
    "Write ID3v4 header",
    () {
      test("Empty body, the most basic header", () {
        final writer = Id3v4Writer();

        final file = createTemporaryFile("test.mp3");

        writer.write(file, Mp3Metadata());

        final readResult = ByteData.sublistView(file.openSync().readSync(10));

        expect(readResult.getUint8(0), equals(0x49));
        expect(readResult.getUint8(1), equals(0x44));
        expect(readResult.getUint8(2), equals(0x33));

        expect(readResult.getUint8(3), equals(4));
        expect(readResult.getUint8(4), equals(0));
        expect(readResult.getUint8(5), equals(0));
        expect(readResult.getUint32(6), equals(0));
      });
      test("Empty ID3 header but with a MP3 frame header", () {
        final writer = Id3v4Writer();
        final frameData = mp3FrameHeaderCBR();
        final file = createTemporaryFile("test.mp3", frameData);

        writer.write(file, Mp3Metadata());

        final fileData = file.readAsBytesSync();
        final readResult = ByteData.sublistView(fileData.sublist(0, 10));

        expect(readResult.getUint8(0), equals(0x49));
        expect(readResult.getUint8(1), equals(0x44));
        expect(readResult.getUint8(2), equals(0x33));

        expect(readResult.getUint8(3), equals(4));
        expect(readResult.getUint8(4), equals(0));
        expect(readResult.getUint8(5), equals(0));
        expect(readResult.getUint32(6), equals(0));
        expect(fileData.length, 10 + frameData.length);
      });

      test(
        "Write basic metadata",
        () {
          final writer = Id3v4Writer();

          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          final metadata = Mp3Metadata();
          metadata.songName = "Only Ones Who Know";

          writer.write(file, metadata);

          final resultMetadata =
              ID3v2Parser().parse(file.openSync()) as Mp3Metadata;

          expect(resultMetadata.songName, equals(metadata.songName));
        },
      );

      test(
        "Write a bit more of metadata",
        () {
          final writer = Id3v4Writer();

          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          final metadata = Mp3Metadata();
          metadata.songName = "Only Ones Who Know";
          metadata.originalArtist = "Arctic Monkeys";
          metadata.album = "Favourite Worst Nightmare";
          metadata.trackNumber = 6;
          metadata.trackTotal = 12;
          metadata.year = 2007;

          writer.write(file, metadata);

          final resultMetadata =
              ID3v2Parser().parse(file.openSync()) as Mp3Metadata;

          expect(resultMetadata.songName, equals(metadata.songName));
          expect(
              resultMetadata.originalArtist, equals(metadata.originalArtist));
          expect(resultMetadata.album, equals(metadata.album));
          expect(resultMetadata.trackNumber, equals(6));
          expect(resultMetadata.trackTotal, equals(12));
          expect(resultMetadata.year, equals(metadata.year));
        },
      );

      test(
        "Write a picture",
        () {
          final writer = Id3v4Writer();

          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          final metadata = Mp3Metadata();
          metadata.pictures = [
            Picture(Uint8List.fromList([0, 1, 2, 3]), "image/jpeg",
                PictureType.coverFront),
          ];

          writer.write(file, metadata);

          final resultMetadata = ID3v2Parser(fetchImage: true)
              .parse(file.openSync()) as Mp3Metadata;

          expect(resultMetadata.pictures, hasLength(1));

          final picture = resultMetadata.pictures[0];
          expect(picture.mimetype, equals("image/jpeg"));
          expect(picture.pictureType, equals(PictureType.coverFront));
          expect(picture.bytes, equals([0, 1, 2, 3]));
        },
      );
    },
  );
}
