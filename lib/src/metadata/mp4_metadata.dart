part of 'base.dart';

/// Metadata model for MP4/M4A files.
class Mp4Metadata extends ParserTag {
  /// Track title (`©nam`).
  String? title;

  /// Main artist (`©ART`/`aART` depending on source).
  String? artist;

  /// Album name (`©alb`).
  String? album;

  /// Release date/year.
  DateTime? year;

  /// Track number inside the album.
  int? trackNumber;

  /// Playback duration when available.
  Duration? duration;

  /// Attached cover image (`covr`).
  Picture? picture;

  /// Bitrate in bits per second.
  int? bitrate;

  /// Disc number inside multi-disc releases.
  int? discNumber;

  /// Unsynchronized lyrics text.
  String? lyrics;

  /// Genre text value.
  String? genre;

  /// Audio sample rate in Hz.
  int? sampleRate;

  /// Total tracks in the album.
  int? totalTracks;

  /// Total discs in the release.
  int? totalDiscs;

  /// Ordered chapter list (when chapter boxes are present).
  List<Chapter> chapters;

  /// Build an MP4 metadata object.
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
    List<Chapter>? chapters,
  }) : chapters = chapters ?? [];

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
        '  totalDiscs: $totalDiscs,\n'
        '  chapters: $chapters\n'
        ')';
  }
}
