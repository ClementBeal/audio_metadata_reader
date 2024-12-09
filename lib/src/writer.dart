import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';

void writeMetadata(File track, ParserTag metadata) {
  final reader = track.openSync();

  if (ID3v2Parser.canUserParser(reader)) {
    Id3v4Writer().write(track, metadata as Mp3Metadata);
  }
}
