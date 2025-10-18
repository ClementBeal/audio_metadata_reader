part of 'base.dart';

class ApeMetadata extends ParserTag {
  String? title;
  String? artist;
  String? album;
  Duration? duration;
  DateTime? year;
  int? bitrate;
  int? samplerate;
  int? totalDics;
  int? trackNumber;
  int? trackTotal;
  int? discNumber;
  String? lyric;
  String? languages;
  List<Picture> pictures;
  List<String> genres;
  String? genre;
  int? size;
  String? comment;
  DateTime? lastModified;
  String? version;
  String? fileMD5;
  //
  ApeMetadata({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.year,
    this.bitrate,
    this.samplerate,
    this.totalDics,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.lyric,
    this.languages,
    this.pictures = const [],
    this.genres = const [],
    this.genre,
    this.size,
    this.comment,
    this.lastModified,
    this.version,
    this.fileMD5,
  });
  @override
  String toString() {
    return 'ApeMetadata(\n'
        '  title: $title,\n'
        '  artist: $artist,\n'
        '  album: $album,\n'
        '  duration: $duration,\n'
        '  year: $year,\n'
        '  bitrate: $bitrate,\n'
        '  samplerate: $samplerate,\n'
        '  totalDics: $totalDics,\n'
        '  trackNumber: $trackNumber,\n'
        '  trackTotal: $trackTotal,\n'
        '  discNumber: $discNumber,\n'
        '  lyric: $lyric,\n'
        '  languages: $languages,\n'
        '  pictures: $pictures,\n'
        '  genres: $genres,\n'
        '  genre: $genre,\n'
        '  size: $size,\n'
        '  comment: $comment,\n'
        '  lastModified: $lastModified,\n'
        '  version: $version,\n'
        '  fileMD5: $fileMD5,\n'
        ')';
  }
}
