import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

Future<void> main() async {
  final track = File("Pieces.mp3");

  // Getting the image of a track can be heavy and slow the reading
  final metadata = await readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);
  print(metadata.duration);
  // etc...
}
