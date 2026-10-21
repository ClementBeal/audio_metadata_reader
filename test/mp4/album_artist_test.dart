// Tests for the `albumArtist` field on M4A/MP4 files (aART atom).
//
// `album_artist.m4a` is generated with ffmpeg, so the tests never depend on an
// external audio file. It stores:
//   title        = "Generated Title"
//   artist       = "Track Artist"  -> `©ART`
//   album_artist = "Album Artist"  -> `aART`
//   album        = "Generated Album"
//
// Regenerate it with:
//
//   ffmpeg -y -f lavfi -i "sine=frequency=440:duration=0.5" -c:a aac -b:a 64k \
//     -metadata title="Generated Title" -metadata artist="Track Artist" \
//     -metadata album_artist="Album Artist" -metadata album="Generated Album" \
//     -movflags +faststart test/mp4/album_artist.m4a
//
// Truncated and empty atoms are covered in `truncated_atoms_test.dart`.
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:test/test.dart';

const _fixture = 'test/mp4/album_artist.m4a';

void main() {
  test('M4A: albumArtist comes from the aART atom', () {
    final all = readAllMetadata(File(_fixture), getImage: false) as Mp4Metadata;

    expect(all.artist, equals('Track Artist'));
    expect(all.albumArtist, equals('Album Artist'));
  });

  test('M4A: albumArtist is mapped into the generic view', () {
    final metadata = readMetadata(File(_fixture), getImage: false);

    expect(metadata.artist, equals('Track Artist'));
    expect(metadata.albumArtist, equals('Album Artist'));
  });
}
