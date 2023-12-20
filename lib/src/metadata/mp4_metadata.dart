import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

class Mp4Metadata extends ParserTag {
  String? title;
  String? artist;
  String? album;
  DateTime? year;
  int? trackNumber;
  Duration? duration;
  Picture? picture;
  int? bitrate;
  int? discNumber;

  Mp4Metadata({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.trackNumber,
    this.duration,
    this.picture,
    this.bitrate,
    this.discNumber,
  });
}
