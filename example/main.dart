import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main() {
  final track = File("Pieces.mp3");

  // Returns a condensate
  // Getting the image of a track can be heavy and slow the reading
  final metadata = readMetadata(track, getImage: false);

  print(metadata.title);
  print(metadata.album);
  print(metadata.duration);
  // etc...

  // If you need ALL the metadata of a file (eg. MP3 has bpm)
  // Later you need to check the type of the metadata with a switch
  // ignore: unused_local_variable
  final allMetadata = readAllMetadata(track, getImage: true);

  print("Now we are going to rewrite the metadata");

  // Use the switch if you want to update metadata for a
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

  // Or use the extension methods to update common properties
  updateMetadata(
    track,
    (metadata) {
      metadata.setTitle("New title");
      metadata.setArtist("New artist");
      metadata.setAlbum("New artist");
      metadata.setTrackNumber(1);
      metadata.setTrackNumber(12);
      metadata.setYear(DateTime(2014));
      metadata.setLyrics("I'm singing");
      metadata.setGenres(["Rock", "Metal", "Salsa"]);
      metadata.setPictures([
        Picture(Uint8List.fromList([]), "image/png", PictureType.coverFront)
      ]);
    },
  );
}
