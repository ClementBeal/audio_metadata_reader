part of 'base.dart';

/// Metadata model for RIFF/WAVE files.
class RiffMetadata extends ParserTag {
  /// Track title.
  String? title;

  /// Main artist/author.
  String? artist;

  /// Album or source collection.
  String? album;

  /// Release year/date.
  DateTime? year;

  /// Free-form comment.
  String? comment;

  /// Genre text value.
  String? genre;

  /// Track number.
  int? trackNumber;

  /// Encoder or software used.
  String? encoder;

  /// Publisher label.
  String? publisher;

  /// Copyright notice.
  String? copyright;

  /// Bitrate in bits per second.
  int? bitrate;

  /// Sample rate in Hz.
  int? samplerate;

  /// Playback duration.
  Duration? duration;

  /// Embedded pictures collected from RIFF/ID3 data.
  List<Picture> pictures = [];

  /// Build a RIFF metadata object.
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

  @override
  String toString() {
    return 'RiffMetadata(\n'
        '  title: $title,\n'
        '  artist: $artist,\n'
        '  album: $album,\n'
        '  year: $year,\n'
        '  comment: $comment,\n'
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
