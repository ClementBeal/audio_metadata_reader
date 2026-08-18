import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

Mp3Metadata parseId3v2Metadata(File file, {bool fetchImage = false}) {
  final reader = file.openSync();
  try {
    return ID3v2Parser(fetchImage: fetchImage).parse(reader);
  } finally {
    reader.closeSync();
  }
}

void main() {
  group(
    "Write ID3v4 header",
    () {
      test("Empty body, the most basic header", () {
        final writer = Id3v4Writer();

        final file = createTemporaryFile("test.mp3");

        writer.write(file, Mp3Metadata());

        final reader = file.openSync();
        final readResult = ByteData.sublistView(reader.readSync(10));
        reader.closeSync();

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

          final resultMetadata = parseId3v2Metadata(file);

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

          final resultMetadata = parseId3v2Metadata(file);

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
        "Write UTF-8 metadata with Chinese characters",
        () {
          final writer = Id3v4Writer();

          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          final metadata = Mp3Metadata();
          metadata.songName = "你好世界";
          metadata.originalArtist = "周杰伦";

          writer.write(file, metadata);

          final resultMetadata = parseId3v2Metadata(file);

          expect(resultMetadata.songName, equals(metadata.songName));
          expect(
              resultMetadata.originalArtist, equals(metadata.originalArtist));
        },
      );

      test(
        "Parse TOWN frame into fileOwner",
        () {
          final writer = Id3v4Writer();
          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          final metadata = Mp3Metadata();
          metadata.fileOwner = "owner@example.com";

          writer.write(file, metadata);

          final resultMetadata = parseId3v2Metadata(file);

          expect(resultMetadata.fileOwner, equals(metadata.fileOwner));
        },
      );

      test(
        "Update metadata should not duplicate TCON frame",
        () {
          final writer = Id3v4Writer();
          final file = createTemporaryFile("test.mp3", mp3FrameHeaderCBR());

          writer.write(
            file,
            Mp3Metadata()..genres = ["Rock"],
          );

          updateMetadata(file, (metadata) {
            metadata.setGenres(["Jazz"]);
          });

          final resultMetadata = parseId3v2Metadata(file);

          expect(resultMetadata.genres, equals(["Jazz"]));
          expect(resultMetadata.contentType, equals("Jazz"));
        },
      );

      test(
        "Repeated metadata updates replace the leading ID3v2 tag",
        () {
          final writer = Id3v4Writer();
          final audioData =
              File("./test/mp3/no_metadata.mp3").readAsBytesSync();
          final file = createTemporaryFile(
            "repeated-id3v2-updates.mp3",
            Uint8List.fromList(audioData),
          );

          writer.write(
            file,
            Mp3Metadata()..genres = ["Rock"],
          );
          final int expectedSize = file.lengthSync();

          for (final String genre in ["Jazz", "Pop!", "Blue"]) {
            writer.write(file, Mp3Metadata()..genres = [genre]);

            // All replacement values have the same byte length. A stacked
            // implementation would grow the file after every iteration.
            expect(file.lengthSync(), equals(expectedSize));
          }

          final Uint8List finalData = file.readAsBytesSync();
          final int leadingTagSize = _leadingId3v2Size(finalData);

          expect(_countLeadingId3v2Tags(finalData), equals(1));
          expect(finalData.length, equals(leadingTagSize + audioData.length));
          expect(
            finalData.sublist(leadingTagSize),
            equals(audioData),
          );
          expect(parseId3v2Metadata(file).genres, equals(["Blue"]));
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

          final resultMetadata = parseId3v2Metadata(file, fetchImage: true);

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

int _countLeadingId3v2Tags(Uint8List data) {
  const int headerSize = 10;
  int offset = 0;
  int count = 0;

  while (data.length - offset >= headerSize &&
      data[offset] == 0x49 &&
      data[offset + 1] == 0x44 &&
      data[offset + 2] == 0x33) {
    final int payloadSize = _readSyncSafeInteger(data, offset);
    final bool hasFooter =
        data[offset + 3] == 4 && (data[offset + 5] & 0x10) != 0;
    final int totalTagSize = headerSize + payloadSize + (hasFooter ? 10 : 0);

    if (totalTagSize > data.length - offset) {
      break;
    }

    offset += totalTagSize;
    count++;
  }

  return count;
}

int _leadingId3v2Size(Uint8List data) {
  const int headerSize = 10;
  final int payloadSize = _readSyncSafeInteger(data, 0);
  final bool hasFooter = data[3] == 4 && (data[5] & 0x10) != 0;
  return headerSize + payloadSize + (hasFooter ? 10 : 0);
}

int _readSyncSafeInteger(Uint8List data, int headerOffset) {
  return (data[headerOffset + 9] & 0x7F) |
      ((data[headerOffset + 8] & 0x7F) << 7) |
      ((data[headerOffset + 7] & 0x7F) << 14) |
      ((data[headerOffset + 6] & 0x7F) << 21);
}
