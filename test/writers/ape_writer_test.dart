import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

void main() {
  test('ApeWriter writes metadata that ApeParser can read back', () {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/track.mp3')
      ..writeAsBytesSync(File('test/ape/base_no_tag.mp3').readAsBytesSync());
    final cover = File('test/data/cover.png').readAsBytesSync();

    final metadata = ApeMetadata()
      ..title = 'A title'
      ..artist = 'An artist'
      ..album = 'An album'
      ..trackNumber = 2
      ..trackTotal = 9
      ..discNumber = 1
      ..discTotal = 2
      ..date = DateTime(2024, 3, 14)
      ..genres = ['Rock', 'Indie']
      ..language = ['en']
      ..performer = ['Guitarist']
      ..unknowns['CATALOGNUMBER'] = 'ABC-123'
      ..pictures = [
        Picture(Uint8List.fromList(cover), 'image/png', PictureType.coverFront)
      ];

    ApeWriter().write(file, metadata);

    final parsed = readAllMetadata(file, getImage: true) as ApeMetadata;
    expect(parsed.title, equals('A title'));
    expect(parsed.trackNumber, equals(2));
    expect(parsed.trackTotal, equals(9));
    expect(parsed.discNumber, equals(1));
    expect(parsed.discTotal, equals(2));
    expect(parsed.date, equals(DateTime(2024, 3, 14)));
    expect(parsed.genres, equals(['Rock', 'Indie']));
    expect(parsed.language, equals(['en']));
    expect(parsed.performer, equals(['Guitarist']));
    expect(parsed.unknowns['CATALOGNUMBER'], equals('ABC-123'));
    expect(parsed.pictures.single.bytes, equals(cover));
  });

  test('replaceMetadata replaces APEv2 in place and preserves trailing ID3v1',
      () {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/track.mp3')
      ..writeAsBytesSync(File('test/ape/base_no_tag.mp3').readAsBytesSync());

    ApeWriter().write(file, ApeMetadata()..title = 'Old title');
    final id3v1 = Uint8List.fromList(
        <int>[...'TAG'.codeUnits, ...List<int>.filled(125, 0)]);
    file.writeAsBytesSync(<int>[...file.readAsBytesSync(), ...id3v1]);

    replaceMetadata(file, ApeMetadata()..title = 'New title');

    final parsed = readAllMetadata(file, getImage: false) as ApeMetadata;
    expect(parsed.title, equals('New title'));
    final bytes = file.readAsBytesSync();
    expect(bytes.sublist(bytes.length - 128, bytes.length - 125),
        equals('TAG'.codeUnits));
  });

  test('ApeWriter removes an optional APEv2 header with the old tag', () {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final baseAudio = File('test/ape/base_no_tag.mp3').readAsBytesSync();
    final file = File('${directory.path}/track.mp3')
      ..writeAsBytesSync(baseAudio);

    ApeWriter().write(file, ApeMetadata()..title = 'Before rewrite');
    final footerOnlyTag = file.readAsBytesSync().sublist(baseAudio.length);
    final header = footerOnlyTag.sublist(footerOnlyTag.length - 32);
    // The APEv2 header has the same fixed binary structure as the footer.
    file.writeAsBytesSync(<int>[...baseAudio, ...header, ...footerOnlyTag]);

    ApeWriter().write(file, ApeMetadata()..title = 'After rewrite');

    expect(
        file.readAsBytesSync().sublist(0, baseAudio.length), equals(baseAudio));
    expect(
        (readAllMetadata(file) as ApeMetadata).title, equals('After rewrite'));
  });

  test('writeMetadata keeps the legacy replacement behavior', () {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/track.mp3')
      ..writeAsBytesSync(File('test/ape/base_no_tag.mp3').readAsBytesSync());

    ApeWriter().write(file, ApeMetadata()..title = 'Before legacy call');
    writeMetadata(file, ApeMetadata()..title = 'Legacy title');

    expect(
        (readAllMetadata(file) as ApeMetadata).title, equals('Legacy title'));
  });
}
