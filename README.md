A pure-Dart package for reading and writing metadata for different audio format

| File Format | Metadata Format(s)  | Read | Write |
| ----------- | ------------------- | ---- | ----- |
| MP3         | `ID3v1` `ID3v2`     | ✅   | ❌    |
| MP4         | `iTunes-style ilst` | ✅   | ❌    |
| FLAC        | `Vorbis Comments`   | ✅   | ❌    |
| OGG         | `Vorbis Comments`   | ✅   | ❌    |
| Opus        | `Vorbis Comments`   | ✅   | ❌    |
| WAV         | `RIFF`              | ✅   | ❌    |

It's still in development and there's some metadat format that I could implement or some information the library could return. Just open an issue for that.

## Usage

### Read

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final track = File("Pieces.mp3");

  // Getting the image of a track can be heavy and slow the reading
  final metadata = readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);
}
```

### Write

This use case is a bit more complicated. You have to manipulate the raw metadata and update the good field.

```dart
void main() {
  final fullMetadata = readAllMetadata(track);

  switch (fullMetadata) {
    case Mp3Metadata m:
      m.songName = "New title";
      break;
    case Mp4Metadata m:
      m.title = "New title";
      break;
    case VorbisMetadata m:
      m.title = ["New title"];
      break;
  }

  writeMetadata(track, fullMetadata);
}
```

Also, all the ID3v2 metadata will be written in the minor version 4.

## Performance

By running the following code on my laptop with a SSD, it ables to get the metadata of 3392 tracks in less than 200ms (if we don't fetch the covers). With the covers, about 400ms.

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final folder = Directory(r"music folder")
      .listSync(recursive: true)
      .whereType<File>()
      .where((element) =>
          element.path.contains("mp4") ||
          element.path.contains("m4a") ||
          element.path.contains("mp3") ||
          element.path.contains("flac"))
      .toList();

  print("Number of tracks: ${folder.length}");

  final init = DateTime.now();

  for(final file in folder) {
    readMetadata(file, getImage: false);
  }

  final end = DateTime.now();

  print(end.difference(init));
}
```

## Anonymize a Music Track

If you need to send a track for issue reporting or testing, you should anonymize it. This means converting the actual track into random noise. You can use `ffmpeg` for this purpose.

```bash
ffmpeg -i <your_track> -f lavfi -t 5 -i "anoisesrc=color=white:duration=5" -map_metadata 0 -map 1:a -t 5 <output_track>
```