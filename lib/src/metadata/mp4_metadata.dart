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

  @override
  String toString() {
    return 'Mp4Metadata(\n'
        '  title: $title,\n'
        '  artist: $artist,\n'
        '  album: $album,\n'
        '  year: $year,\n'
        '  trackNumber: $trackNumber,\n'
        '  duration: $duration,\n'
        '  picture: $picture,\n'
        '  bitrate: $bitrate,\n'
        '  discNumber: $discNumber,\n'
        '  lyrics: $lyrics,\n'
        '  genre: $genre,\n'
        '  sampleRate: $sampleRate,\n'
        '  totalTracks: $totalTracks,\n'
        '  totalDiscs: $totalDiscs\n'
        ')';
  }
}
