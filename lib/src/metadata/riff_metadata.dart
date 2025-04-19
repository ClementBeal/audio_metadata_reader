import '../parsers/tag_parser.dart';

class RiffMetadata extends ParserTag {
  String? title;
  String? artist;
  String? album;
  DateTime? year;
  String? comment;
  String? genre;
  int? trackNumber;
  String? encoder;
  String? publisher;
  String? copyright;
  int? bitrate;
  int? samplerate;
  Duration? duration;
  List<Picture> pictures = [];

  RiffMetadata({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.comment,
    this.genre,
    this.trackNumber,
    this.encoder,
    this.publisher,
    this.copyright,
    this.bitrate,
    this.duration,
    this.samplerate,
  });
}
