# Audio Metadata Reader

A pure Dart package for reading and writing metadata in various audio formats.

| File Format | Metadata Format(s)    | Read | Write |
|-------------|------------------------|------|-------|
| MP3         | `ID3v1`, `ID3v2`        | ✅   | ✅    |
| MP4         | `iTunes-style ilst`     | ✅   | ✅    |
| FLAC        | `Vorbis Comments`       | ✅   | ✅    |
| OGG         | `Vorbis Comments`       | ✅   | ❌    |
| Opus        | `Vorbis Comments`       | ✅   | ❌    |
| WAV         | `RIFF`                  | ✅   | ✅    |

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

### Write

```dart
void main() {
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

## Performance

On my laptop with an SSD, the library can process metadata from **3,392 tracks in under 200ms** — assuming covers aren't fetched. With covers, it's around **400ms**.

```dart
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final folder = Directory(r"music folder")
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) =>
          file.path.endsWith(".mp4") ||
          file.path.endsWith(".m4a") ||
          file.path.endsWith(".mp3") ||
          file.path.endsWith(".flac"))
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


## Anonymize a Music Track

If you need to report an issue or test the library without sharing private audio, you can anonymize a track by replacing its audio with white noise using `ffmpeg`:

```bash
ffmpeg -i <your_track> -f lavfi -t 5 -i "anoisesrc=color=white:duration=5" -map_metadata 0 -map 1:a -t 5 <output_track>
```
