import 'dart:io';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/riff.dart';

/// Reads the metadata, allows modification via [updater], and writes it back.
///
/// The [updater] receives the specific metadata object (e.g Mp3Metadata).
/// You can modify this object directly within the callback.
Future<void> updateMetadata(File track, void Function(ParserTag metadata) updater) async{
  // final metadata = await readAllMetadata(track);

  // updater(metadata);

  // writeMetadata(track, metadata);
}

/// Write the [metadata] into the [track]
Future<void> writeMetadata(File track, ParserTag metadata) async{
  final reader = FileRandomAccessFile(randomAccessFile: track.openSync());

  if (await ID3v2Parser.canUserParser(reader)) {
    Id3v4Writer().write(track, metadata as Mp3Metadata);
  } else if (await MP4Parser.canUserParser(reader)) {
    Mp4Writer().write(track, metadata as Mp4Metadata);
  } else if (await FlacParser.canUserParser(reader)) {
    FlacWriter().write(track, metadata as VorbisMetadata);
  } else if (await RiffParser.canUserParser(reader)) {
    RiffWriter().write(track, metadata as RiffMetadata);
  } else if (await ID3v1Parser.canUserParser(reader)) {
    ID3v1Writer().write(track, metadata as Mp3Metadata);
  }
}
