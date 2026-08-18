import 'dart:io';

import 'package:audio_metadata_reader/src/constants/id3_genres.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/pad_bit.dart';
import 'package:audio_metadata_reader/src/writer.dart';
import 'package:audio_metadata_reader/src/writers/id3v1_writer.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  test('Id3v1Writer writes ID3v1 tag correctly', () {
    final dir = Directory.systemTemp.createTempSync();

    final tempFile = File('${dir.path}/test_audio.mp3');
    tempFile.createSync();
    final writer = tempFile.openSync(mode: FileMode.write);

    writer.writeFromSync(mp3FrameHeaderCBR());
    writer.closeSync();

    final metadata = Mp3Metadata()
      ..songName = 'Test Title'
      ..bandOrOrchestra = 'Test Artist'
      ..album = 'Test Album'
      ..genres = ['Rock']
      ..year = 2023;

    ID3v1Writer().write(tempFile, metadata);

    final fileBytes = tempFile.readAsBytesSync();
    final id3v1Bytes = fileBytes.sublist(fileBytes.length - 128);

    // 7. Assert that the written bytes match the expected bytes
    expect(id3v1Bytes.sublist(0, 3), equals("TAG".codeUnits));
    expect(id3v1Bytes.sublist(3, 33),
        equals(metadata.songName!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(33, 63),
        equals(metadata.bandOrOrchestra!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(63, 93),
        equals(metadata.album!.codeUnits.padBitRight(30, 0)));
    expect(id3v1Bytes.sublist(93, 97),
        equals(metadata.year!.toString().codeUnits));
    expect(id3v1Bytes.sublist(97, 127), equals(List.filled(30, 0)));
    expect(id3v1Bytes[127], equals(17)); // ID3v1 code for Rock.

    tempFile.deleteSync();
  });

  test('ID3v1 year is parsed from ASCII text', () {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));

    final tempFile = File('${dir.path}/test_audio.mp3');
    tempFile.writeAsBytesSync(mp3FrameHeaderCBR());

    final metadata = Mp3Metadata()
      ..songName = 'Test Title'
      ..bandOrOrchestra = 'Test Artist'
      ..album = 'Test Album'
      ..year = 2023;

    ID3v1Writer().write(tempFile, metadata);

    final parsed = readAllMetadata(tempFile) as Mp3Metadata;
    expect(parsed.year, equals(2023));
    expect(parsed.genres, isEmpty);
  });

  test('Id3v1Writer writes 255 for an unknown genre', () {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));

    final tempFile = File('${dir.path}/test_audio.mp3');
    tempFile.writeAsBytesSync(mp3FrameHeaderCBR());

    ID3v1Writer().write(
      tempFile,
      Mp3Metadata()..genres = ['Not an ID3v1 genre'],
    );

    final fileBytes = tempFile.readAsBytesSync();
    expect(fileBytes.last, equals(255));
  });

  test('Id3v1Writer replaces an existing trailing tag', () {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));

    final tempFile = File('${dir.path}/test_audio.mp3');
    final originalAudio =
        File('test/mp3/generated_under_one_second.mp3').readAsBytesSync();
    tempFile.writeAsBytesSync(originalAudio);

    ID3v1Writer().write(
      tempFile,
      Mp3Metadata()
        ..songName = 'First title'
        ..bandOrOrchestra = 'First artist'
        ..album = 'First album'
        ..year = 2023,
    );
    final lengthAfterFirstWrite = tempFile.lengthSync();

    ID3v1Writer().write(
      tempFile,
      Mp3Metadata()
        ..songName = 'Second title'
        ..bandOrOrchestra = 'Second artist'
        ..album = 'Second album'
        ..year = 2024,
    );

    final finalBytes = tempFile.readAsBytesSync();
    expect(finalBytes.length, equals(lengthAfterFirstWrite));
    expect(finalBytes.length, equals(originalAudio.length + 128));
    expect(finalBytes.sublist(0, originalAudio.length), equals(originalAudio));
    expect(
      finalBytes.sublist(finalBytes.length - 125, finalBytes.length - 95),
      equals('Second title'.codeUnits.padBitRight(30, 0)),
    );
  });

  test('setArtist writes the ID3v1 artist field', () {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));

    final tempFile = File('${dir.path}/test_audio.mp3');
    tempFile.writeAsBytesSync(
      File('test/mp3/generated_under_one_second.mp3').readAsBytesSync(),
    );

    ID3v1Writer().write(
      tempFile,
      Mp3Metadata()
        ..songName = 'Original title'
        ..leadPerformer = 'Original artist'
        ..album = 'Original album'
        ..year = 2023,
    );

    updateMetadata(tempFile, (metadata) {
      metadata.setArtist('Updated artist');
    });

    final updatedMetadata = readAllMetadata(tempFile) as Mp3Metadata;
    expect(updatedMetadata.leadPerformer, equals('Updated artist'));
  });

  test('ID3 genre helpers convert names and codes', () {
    expect(id3GenreCode(' rock '), equals(17));
    expect(id3GenreCode('17'), equals(17));
    expect(id3GenreCode('Unknown genre'), isNull);
    expect(id3GenreName(17), equals('Rock'));
    expect(id3GenreName(255), isNull);
  });
}
