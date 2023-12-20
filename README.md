A pure-Dart package for reading and writing metadata for different audio format

| File Format | Metadata Format(s)      |
| ----------- | ----------------------- |
| MP3         | `ID3v2` `ID3v3` `ID3v4` |
| MP4         | `iTunes-style ilst`     |
| FLAC        | `Vorbis Comments`       |

It's still in development and there's some metadat format that I could implement or some information the library could return. Just open an issue for that.

## Usage

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

Future<void> main() async {
  final track = File("Pieces.mp3");

  // Getting the image of a track can be heavy and slow the reading
  final metadata = await readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);

  final newMetadata = AudioMetadata(
    title: "Pieces",
    album: "Chuck",
    artist: "Sum 41",
    discNumber: 1,
    duration: Duration(minutes: 3, seconds: 23),
    language: "English",
    lyrics: "My super lyrics",
    totalDisc: 1,
    trackNumber: 11,
    trackTotal: 13,
    year: DateTime(2004),
  );

  newMetadata.pictures.add(
    Picture(
      File("newCover.jpg").readAsBytesSync(),
      "image/jpg",
      PictureType.coverFront,
    ),
  );

  newMetadata.genres.addAll(["Rock", "Punk"]);

  await writeMetadata(track, newMetadata);
}
```

## Performance

By running the following code on my laptop with a SSD, it ables to get the metadata of 2100 tracks in less than 1 second (if we don't fetch the covers). With the covers, it slightly more.

```dart
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

Future<void> main() async {
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
  await Future.wait(folder.map((e) => readMetadata(e, getImage: false)));
  final end = DateTime.now();

  print(end.difference(init));
}
```

```
Number of tracks: 2094
0:00:00.969653
```
