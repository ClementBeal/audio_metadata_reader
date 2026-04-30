part of 'base.dart';

/// Dedicated metadata model for APEv2 tags.
///
/// We intentionally keep this model close to the public [AudioMetadata] shape
/// so mappings stay explicit and maintainers can reason about each field
/// without knowing Vorbis internals.
class ApeMetadata extends ParserTag {
  /// Track title (`TITLE`).
  String? title; // TITLE
  /// Main artist (`ARTIST`).
  String? artist; // ARTIST
  /// Album name (`ALBUM`).
  String? album; // ALBUM
  /// Album artist (`ALBUMARTIST` / `ALBUM ARTIST`).
  String? albumArtist; // ALBUMARTIST / ALBUM ARTIST
  /// Lyrics (`LYRICS` / `LYRIC`).
  String? lyric; // LYRICS / LYRIC
  /// Comment field (`COMMENT`).
  String? comment; // COMMENT
  /// Composer (`COMPOSER`).
  String? composer; // COMPOSER
  /// Copyright text (`COPYRIGHT`).
  String? copyright; // COPYRIGHT
  /// Encoder information (`ENCODEDBY` / `ENCODED_BY`).
  String? encodedBy; // ENCODEDBY / ENCODED_BY

  /// Date or year (`DATE` / `YEAR`).
  DateTime? date; // DATE / YEAR
  /// Track number (`TRACK` / `TRACKNUMBER`).
  int? trackNumber; // TRACK / TRACKNUMBER
  /// Total track count (`TRACKTOTAL` / `TOTALTRACKS`).
  int? trackTotal; // TRACKTOTAL / TOTALTRACKS
  /// Disc number (`DISC` / `DISCNUMBER`).
  int? discNumber; // DISC / DISCNUMBER
  /// Total disc count (`DISCTOTAL` / `TOTALDISCS`).
  int? discTotal; // DISCTOTAL / TOTALDISCS

  /// Genre values (`GENRE`).
  List<String> genres = []; // GENRE
  /// Language values (`LANGUAGE` / `LANG`).
  List<String> language = []; // LANGUAGE / LANG
  /// Performer values (`PERFORMER`).
  List<String> performer = []; // PERFORMER
  /// Embedded pictures (for example Cover Art Front/Back).
  List<Picture> pictures = []; // Cover Art (Front/Back)

  /// Optional stream duration when available from companion sources.
  Duration? duration;

  /// Optional stream bitrate in bits per second.
  int? bitrate;

  /// Optional stream sample rate in Hz.
  int? sampleRate;

  /// Any unrecognized or non-mapped text item is preserved here.
  Map<String, String> unknowns = HashMap();

  ApeMetadata();

  @override
  String toString() {
    return 'ApeMetadata(\n'
        '  title: $title,\n'
        '  artist: $artist,\n'
        '  album: $album,\n'
        '  albumArtist: $albumArtist,\n'
        '  lyric: $lyric,\n'
        '  comment: $comment,\n'
        '  composer: $composer,\n'
        '  copyright: $copyright,\n'
        '  encodedBy: $encodedBy,\n'
        '  date: $date,\n'
        '  trackNumber: $trackNumber,\n'
        '  trackTotal: $trackTotal,\n'
        '  discNumber: $discNumber,\n'
        '  discTotal: $discTotal,\n'
        '  genres: $genres,\n'
        '  language: $language,\n'
        '  performer: $performer,\n'
        '  pictures: $pictures,\n'
        '  duration: $duration,\n'
        '  bitrate: $bitrate,\n'
        '  sampleRate: $sampleRate,\n'
        '  unknowns: $unknowns\n'
        ')';
  }
}
