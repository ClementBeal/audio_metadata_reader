import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';

class Picture {
  final Uint8List bytes;
  final String mimetype;
  final PictureType pictureType;

  Picture(this.bytes, this.mimetype, this.pictureType);

  @override
  String toString() {
    return 'Picture{'
        'bytes: ${bytes.length} bytes, '
        'mimetype: $mimetype, '
        'pictureType: $pictureType}';
  }
}

abstract class ParserTag {}

/// A generic class to gather the metadata. To make it universal, some format-specific metadata
/// are dropped.
///
/// To use more precise metadata information related to a format, please
/// use the parser of the format.
class AudioMetadata {
  String? album;
  DateTime? year;
  String? language;
  String? artist;
  String? title;
  int? trackNumber;
  int? trackTotal;
  Duration? duration;
  late List<String> genres;
  int? discNumber;
  int? totalDisc;
  String? lyrics;
  int? bitrate;
  int? sampleRate;
  late List<Picture> pictures;
  File file;

  AudioMetadata({
    this.album,
    this.year,
    this.language,
    this.artist,
    this.title,
    this.trackNumber,
    this.trackTotal,
    this.duration,
    this.discNumber,
    this.totalDisc,
    this.lyrics,
    this.bitrate,
    this.sampleRate,
    required this.file,
  }) {
    genres = [];
    pictures = [];
  }
}

abstract class TagParser {
  final bool fetchImage;

  TagParser({required this.fetchImage});
  ParserTag parse(RandomAccessFile reader);
}
