part of 'base.dart';

class RiffMetadata extends ParserTag {
  String? title;
  String? artist;
  String? album;
  DateTime? year;
  String? comment;
  String? lyric;
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
    this.lyric,
    this.genre,
    this.trackNumber,
    this.encoder,
    this.publisher,
    this.copyright,
    this.bitrate,
    this.duration,
    this.samplerate,
  });

  @override
  String toString() {
    return 'RiffMetadata(\n'
        '  title: $title,\n'
        '  artist: $artist,\n'
        '  album: $album,\n'
        '  year: $year,\n'
        '  comment: $comment,\n'
        '  lyrics: $lyric,\n'
        '  genre: $genre,\n'
        '  trackNumber: $trackNumber,\n'
        '  encoder: $encoder,\n'
        '  publisher: $publisher,\n'
        '  copyright: $copyright,\n'
        '  bitrate: $bitrate,\n'
        '  samplerate: $samplerate,\n'
        '  duration: $duration,\n'
        '  pictures: $pictures\n'
        ')';
  }
}
