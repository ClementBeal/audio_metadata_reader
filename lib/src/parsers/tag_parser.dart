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
  }) {
    genres = [];
    pictures = [];
  }
}

class InvalidTag extends AudioMetadata {}

abstract class TagParser {
  Future<ParserTag> parse(RandomAccessFile reader);
}
