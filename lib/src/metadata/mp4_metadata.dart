part of 'base.dart';

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
  String? lyrics;
  String? genre;
  int? sampleRate;
  int? totalTracks;
  int? totalDiscs;

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
    this.lyrics,
    this.genre,
    this.sampleRate,
    this.totalTracks,
    this.totalDiscs,
  });
}
