import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/containers/riff.dart';

/// Reads the metadata, allows modification via [updater], and writes it back.
///
/// The [updater] receives the specific metadata object (e.g Mp3Metadata).
/// You can modify this object directly within the callback.
void updateMetadata(File track, void Function(ParserTag metadata) updater) {
  final metadata = readAllMetadata(track);

  updater(metadata);

  replaceMetadata(track, metadata);
}

/// Replaces the metadata in [track] with [metadata] using the matching
/// container writer.
///
/// This reconstructs the supported metadata blocks from [metadata]. Tags that
/// are not represented by the metadata object can therefore be discarded.
/// Use [updateMetadata] when existing metadata that is not being edited must
/// be preserved.
///
/// The runtime type of [metadata] must match the detected writer.
void replaceMetadata(File track, ParserTag metadata) {
  final reader = track.openSync();

  try {
    // Test APEv2 before MP3: a tag-only APEv2 file may contain MPEG audio but
    // has no ID3 tag, and its metadata model must be written by ApeWriter.
    if (ApeParser.canUserParser(reader) && metadata is ApeMetadata) {
      ApeWriter().write(track, metadata);
    } else if (MP3Parser.hasID3v2Tag(reader)) {
      Id3v4Writer().write(track, metadata as Mp3Metadata);
    } else if (MP4Parser.canUserParser(reader)) {
      Mp4Writer().write(track, metadata as Mp4Metadata);
    } else if (FlacParser.canUserParser(reader)) {
      FlacWriter().write(track, metadata as VorbisMetadata);
    } else if (RiffParser.canUserParser(reader)) {
      RiffWriter().write(track, metadata as RiffMetadata);
    } else if (MP3Parser.hasID3v1Tag(reader)) {
      ID3v1Writer().write(track, metadata as Mp3Metadata);
    }
  } finally {
    // Always close the file handle opened by this function.
    reader.closeSync();
  }
}

/// Writes metadata using the matching container writer.
///
/// Deprecated because the name does not make the destructive replacement
/// behavior explicit. This function has the same behavior as
/// [replaceMetadata], including the possibility of discarding tags that are
/// not represented by [metadata]. Use [updateMetadata] when those existing
/// tags must be preserved.
@Deprecated(
  'Use replaceMetadata for a full metadata replacement. '
  'Use updateMetadata to preserve existing metadata fields.',
)
void writeMetadata(File track, ParserTag metadata) {
  replaceMetadata(track, metadata);
}
