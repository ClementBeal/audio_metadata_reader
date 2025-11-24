import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/riff.dart';
import 'package:audio_metadata_reader/src/io/io_source.dart';

/// Reads the metadata, allows modification via [updater], and writes it back.
///
/// Accepts an [IOSource] (e.g. `FileIOSource.fromFile` on native or
/// `ByteDataIOSource.fromBytes` on any platform). If backed by a
/// [FileIOSource], the file is modified in place and `null` is returned;
/// otherwise the updated audio bytes are returned.
Future<Uint8List?> updateMetadata(IOSource input, void Function(ParserTag metadata) updater) async {
  final metadata = await readAllMetadata(input);

  updater(metadata);

  return await writeMetadata(input, metadata);
}

/// Write the [metadata] into the audio data.
///
/// Accepts an [IOSource] (e.g. `FileIOSource.fromFile` on native or
/// `ByteDataIOSource.fromBytes` on any platform). If the source is backed by a
/// [FileIOSource], the file is modified in place and `null` is returned;
/// otherwise the updated audio bytes are returned.
Future<Uint8List?> writeMetadata(IOSource input, ParserTag metadata) async {
  final originalBytes = await _readAllBytes(input);

  // Use fresh readers for parser detection to avoid position side effects.
  Uint8List? result;
  if (await ID3v2Parser.canUserParser(ByteDataIOSource.fromBytes(originalBytes))) {
    result = await Id3v4Writer().writeToBytes(originalBytes, metadata as Mp3Metadata);
  } else if (await MP4Parser.canUserParser(ByteDataIOSource.fromBytes(originalBytes))) {
    result = await Mp4Writer().writeToBytes(originalBytes, metadata as Mp4Metadata);
  } else if (await FlacParser.canUserParser(ByteDataIOSource.fromBytes(originalBytes))) {
    result = await FlacWriter().writeToBytes(originalBytes, metadata as VorbisMetadata);
  } else if (await RiffParser.canUserParser(ByteDataIOSource.fromBytes(originalBytes))) {
    result = await RiffWriter().writeToBytes(originalBytes, metadata as RiffMetadata);
  } else if (await ID3v1Parser.canUserParser(ByteDataIOSource.fromBytes(originalBytes))) {
    result = await ID3v1Writer().writeToBytes(originalBytes, metadata as Mp3Metadata);
  }

  // Nothing matched; propagate close and surface null.
  if (result == null) {
    await input.close();
    return null;
  }

  if (input is FileIOSource) {
    final file = input.file;
    await file.setPosition(0);
    await file.truncate(0);
    await file.writeFrom(result);
    await file.flush();
    await input.close();
    return null;
  }

  await input.close();
  return result;
}

Future<Uint8List> _readAllBytes(IOSource source) async {
  final length = await source.length;
  await source.setPosition(0);
  final data = await source.read(length);
  await source.setPosition(0);
  return data;
}
