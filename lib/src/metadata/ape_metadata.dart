part of 'base.dart';

/// Dedicated metadata model for APEv2 tags.
///
/// We intentionally keep this model close to the public [AudioMetadata] shape
/// so mappings stay explicit and maintainers can reason about each field
/// without knowing Vorbis internals.
class ApeMetadata extends ParserTag {
  String? title; // TITLE
  String? artist; // ARTIST
  String? album; // ALBUM
  String? albumArtist; // ALBUMARTIST / ALBUM ARTIST
  String? lyric; // LYRICS / LYRIC
  String? comment; // COMMENT
  String? composer; // COMPOSER
  String? copyright; // COPYRIGHT
  String? encodedBy; // ENCODEDBY / ENCODED_BY

  DateTime? date; // DATE / YEAR
  int? trackNumber; // TRACK / TRACKNUMBER
  int? trackTotal; // TRACKTOTAL / TOTALTRACKS
  int? discNumber; // DISC / DISCNUMBER
  int? discTotal; // DISCTOTAL / TOTALDISCS

  List<String> genres = []; // GENRE
  List<String> language = []; // LANGUAGE / LANG
  List<String> performer = []; // PERFORMER
  List<Picture> pictures = []; // Cover Art (Front/Back)

  // Optional stream-level information when available from companion sources.
  Duration? duration;
  int? bitrate;
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
