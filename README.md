# Audio Metadata Reader

A pure Dart package for reading and writing metadata in various audio formats.

| File Format | Metadata Format(s)    | Read | Write |
|-------------|------------------------|------|-------|
| MP3         | `ID3v1`, `ID3v2`        | ✅   | ✅    |
| MP4         | `iTunes-style ilst`     | ✅   | ✅    |
| FLAC        | `Vorbis Comments`       | ✅   | ✅    |
| OGG         | `Vorbis Comments`       | ✅   | ❌    |
| Opus        | `Vorbis Comments`       | ✅   | ❌    |
| WebM/Matroska | `Tags` / Opus          | ✅   | ❌    |
| WAV         | `RIFF`                  | ✅   | ✅    |
| AIFF/AIFC   | `IFF chunks`            | ✅   | ❌    |
| APE         | `APEv2`                 | ✅   | ✅    |

This package is still under active development. If there's a metadata format you'd like to see supported or specific information you’d like the library to expose, feel free to open an issue.

## Usage

### Read

```dart
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final track = File("Pieces.mp3");

  // Fetching images can slow down metadata reading
  final metadata = readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);
}
```

`readMetadata` returns the common `AudioMetadata` view shared by all supported
formats. Use `readAllMetadata` when you need the format-specific metadata
object, such as `Mp3Metadata`, `Mp4Metadata`, `VorbisMetadata`, `RiffMetadata`
or `ApeMetadata`.

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

final track = File("Pieces.mp3");
final metadata = readAllMetadata(track, getImage: false);
print(metadata);
```

### Supported File Extensions

The package currently recognizes these extensions:

`.mp3`, `.flac`, `.mp4`, `.m4a`, `.ape`, `.ogg`, `.opus`, `.wav`, `.webm`,
`.mkv`, `.aif`, `.aiff`, `.aifc` and `.mov`.

Use `supportedFileExtensions` when filtering files before parsing:

```dart
final isSupported = supportedFileExtensions.any(
  (ext) => file.path.toLowerCase().endsWith(ext),
);
```

### Write

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final track = File("Pieces.mp3");

  // Use a switch if you want to update metadata based on the file type
  updateMetadata(
    track,
    (metadata) {
      switch (metadata) {
        case Mp3Metadata m:
          m.songName = "New title";
          break;
        case Mp4Metadata m:
          m.title = "New title";
          break;
        case VorbisMetadata m:
          m.title = ["New title"];
          break;
        case RiffMetadata m:
          m.title = "New title";
          break;
        case ApeMetadata m:
          m.title = "New title";
      }
    },
  );

  // Or use extension methods for common metadata updates
  updateMetadata(
    track,
    (metadata) {
      metadata.setTitle("New title");
      metadata.setArtist("New artist");
      metadata.setAlbum("New album");
      metadata.setTrackNumber(1);
      metadata.setYear(DateTime(2014));
      metadata.setLyrics("I'm singing");
      metadata.setGenres(["Rock", "Metal", "Salsa"]);
      metadata.setPictures([
        Picture(Uint8List.fromList([]), "image/png", PictureType.coverFront)
      ]);
    },
  );
}
```

`updateMetadata` reads the existing format-specific metadata, applies the
callback, then writes it back to the same file while retaining metadata that
the callback does not change. For an already constructed metadata object, use
`replaceMetadata` directly:

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

final metadata = Mp3Metadata()..songName = "New title";
replaceMetadata(File("Pieces.mp3"), metadata);
```

`replaceMetadata` reconstructs the supported metadata from the object you
provide. It is destructive: tags that are not represented by that object may
be removed. `writeMetadata` is deprecated and behaves the same way; use
`updateMetadata` when you need to preserve existing metadata that you are not
editing.

The common setter extension also provides `setTrackTotal` and `setCD`. Some
formats do not support every field; unsupported setters are intentionally
ignored for those formats.

MP4 metadata can also contain `Chapter` markers. OGG, Opus and AIFF/AIFC are
currently read-only; metadata writing is supported for MP3, MP4, FLAC, WAV and
APE files.

## Performance

On my laptop with an SSD, the library can process metadata from **3,392 tracks in under 200ms** — assuming covers aren't fetched. With covers, it's around **400ms**.

```dart
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final folder = Directory(r"music folder")
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) => supportedFileExtensions.any(
          (ext) => file.path.toLowerCase().endsWith(ext),
        ),
      )
      .toList();

  print("Number of tracks: ${folder.length}");

  final start = DateTime.now();

  for (final file in folder) {
    readMetadata(file, getImage: false);
  }

  final end = DateTime.now();
  print("Duration: ${end.difference(start)}");
}
```

### Compare with FFmpeg/libavformat

The repository includes a standalone benchmark that recursively scans a music
directory and reads metadata without loading cover images:

```bash
dart run tool/benchmark_metadata.dart --backend both --runs 3
```

It defaults to `~/Music`. Use `--music PATH` for another directory and
`--backend library` to measure only this package. The `ffprobe` comparison uses
FFmpeg/libavformat through the `ffprobe` executable and requests only
`format_tags`; its timing includes one process launch per file.

To list the files that fail to parse, run the diagnostic script:

```bash
dart run tool/find_metadata_errors.dart --music ~/Music
```

It prints each failing path, the exception message, and an error summary. Add
`--stack-traces` when investigating a parser failure in detail.


## Anonymize a Music Track

If you need to report an issue or test the library without sharing private audio, you can anonymize a track by replacing its audio with white noise using `ffmpeg`:

```bash
ffmpeg -i <your_track> -f lavfi -t 5 -i "anoisesrc=color=white:duration=5" -map_metadata 0 -map 1:a -t 5 <output_track>
```
