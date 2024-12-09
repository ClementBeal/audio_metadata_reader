import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/writer.dart';

void main() {
  final track = File("Pieces.mp3");

  // Getting the image of a track can be heavy and slow the reading
  final metadata = readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);
  print(metadata.duration);
  // etc...

  print("Now we are going to rewrite the metadata");

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
