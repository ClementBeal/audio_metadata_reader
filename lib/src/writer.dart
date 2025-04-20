import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/riff.dart';

/// Reads the metadata, allows modification via [updater], and writes it back.
///
/// The [updater] receives the specific metadata object (e.g Mp3Metadata).
/// You can modify this object directly within the callback.
void updateMetadata(File track, void Function(ParserTag metadata) updater) {
  final metadata = readAllMetadata(track);

  updater(metadata);

  writeMetadata(track, metadata);
}

/// Write the [metadata] into the [track]
void writeMetadata(File track, ParserTag metadata) {
  final reader = track.openSync();

  if (ID3v2Parser.canUserParser(reader)) {
    Id3v4Writer().write(track, metadata as Mp3Metadata);
  } else if (MP4Parser.canUserParser(reader)) {
    Mp4Writer().write(track, metadata as Mp4Metadata);
  } else if (FlacParser.canUserParser(reader)) {
    FlacWriter().write(track, metadata as VorbisMetadata);
  } else if (RiffParser.canUserParser(reader)) {
    RiffWriter().write(track, metadata as RiffMetadata);
  } else if (ID3v1Parser.canUserParser(reader)) {
    ID3v1Writer().write(track, metadata as Mp3Metadata);
  }
}
