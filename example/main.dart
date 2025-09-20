import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final track = File("Carpenters - Yesterday Once More.mp3");

  // Returns a condensate
  // Getting the image of a track can be heavy and slow the reading
  AudioMetadata metadata = readMetadata(track, getImage: true);
// print(metadata);
  // print(metadata);

}


