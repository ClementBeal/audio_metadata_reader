part of 'base.dart';

// https://xiph.org/vorbis/doc/v-comment.html
// https://exiftool.org/TagNames/Vorbis.html
/// Metadata model for Vorbis comments (used by FLAC, OGG Vorbis, and Opus).
class VorbisMetadata extends ParserTag {
  /// Track title values (`TITLE`).
  List<String> title = []; // TITLE
  /// Version/revision strings (`VERSION`).
  List<String> version = []; // VERSION
  /// Album name values (`ALBUM`).
  List<String> album = []; // ALBUM
  /// Track numbers (`TRACKNUMBER`).
  List<int> trackNumber = []; // TRACKNUMBER
  /// Main artist values (`ARTIST`).
  List<String> artist = []; // ARTIST
  /// Additional performers (`PERFORMER`).
  List<String> performer = []; // PERFORMER
  /// Copyright statements (`COPYRIGHT`).
  List<String> copyright = []; // COPYRIGHT
  /// License strings (`LICENSE`).
  List<String> license = []; // LICENSE
  /// Publishing organization (`ORGANIZATION`).
  List<String> organization = []; // ORGANIZATION
  /// Description/notes (`DESCRIPTION`).
  List<String> description = []; // DESCRIPTION
  /// Genre entries (`GENRE`).
  List<String> genres = []; // GENRE
  /// Release dates (`DATE`).
  List<DateTime> date = []; // DATE
  /// Location fields (`LOCATION`).
  List<String> location = []; // LOCATION
  /// Contact fields (`CONTACT`).
  List<String> contact = []; // CONTACT
  /// ISRC codes (`ISRC`).
  List<String> isrc = []; // ISRC

  // Additional fields
  /// Cast/actors (`ACTOR`).
  List<String> actor = []; // ACTOR
  /// Composer values (`COMPOSER`).
  List<String> composer = []; // COMPOSER
  /// Comment values (`COMMENT`).
  List<String> comment = []; // COMMENT
  /// Language tags (`LANGUAGE`/`LANG`).
  List<String> language = []; // LANGUAGE / LANG
  /// Director values (`DIRECTOR`).
  List<String> director = []; // DIRECTOR
  /// Encoded-by values (`ENCODED_BY`).
  List<String> encodedBy = []; // ENCODED_BY
  /// Encoding tool values (`ENCODED_USING`).
  List<String> encodedUsing = []; // ENCODED_USING
  /// Encoder values (`ENCODER`).
  List<String> encoder = []; // ENCODER
  /// Encoder options (`ENCODER_OPTIONS`).
  List<String> encoderOptions = []; // ENCODER_OPTIONS
  /// Producer values (`PRODUCER`).
  List<String> producer = []; // PRODUCER
  /// ReplayGain album gain values.
  List<String> replayGainAlbumGain = []; // REPLAYGAIN_ALBUM_GAIN
  /// ReplayGain album peak values.
  List<String> replayGainAlbumPeak = []; // REPLAYGAIN_ALBUM_PEAK
  /// ReplayGain track gain values.
  List<String> replayGainTrackGain = []; // REPLAYGAIN_TRACK_GAIN
  /// ReplayGain track peak values.
  List<String> replayGainTrackPeak = []; // REPLAYGAIN_TRACK_PEAK
  /// Vendor string from the comment header.
  List<String> vendor = []; // vendor (from comment header)
  /// Unrecognized key/value pairs preserved as-is.
  Map<String, String> unknowns = HashMap();

  // BONUS
  /// Playback duration when known.
  Duration? duration;

  /// Total track count.
  int? trackTotal;

  /// Disc number.
  int? discNumber;

  /// Total number of discs.
  int? discTotal;

  /// Lyrics text.
  String? lyric;

  /// Attached pictures (for example from FLAC picture blocks).
  List<Picture> pictures = [];

  /// Bitrate in bits per second.
  int? bitrate;

  /// Sample rate in Hz.
  int? sampleRate;

  /// Build an empty Vorbis metadata object.
  VorbisMetadata();

  @override
  String toString() {
    return 'VorbisMetadata(\n'
        '  title: $title,\n'
        '  version: $version,\n'
        '  album: $album,\n'
        '  trackNumber: $trackNumber,\n'
        '  artist: $artist,\n'
        '  performer: $performer,\n'
        '  copyright: $copyright,\n'
        '  license: $license,\n'
        '  organization: $organization,\n'
        '  description: $description,\n'
        '  genre: $genres,\n'
        '  date: $date,\n'
        '  location: $location,\n'
        '  contact: $contact,\n'
        '  isrc: $isrc,\n'
        '  actor: $actor,\n'
        '  composer: $composer,\n'
        '  comment: $comment,\n'
        '  language: $language,\n'
        '  director: $director,\n'
        '  encodedBy: $encodedBy,\n'
        '  encodedUsing: $encodedUsing,\n'
        '  encoder: $encoder,\n'
        '  encoderOptions: $encoderOptions,\n'
        '  producer: $producer,\n'
        '  replayGainAlbumGain: $replayGainAlbumGain,\n'
        '  replayGainAlbumPeak: $replayGainAlbumPeak,\n'
        '  replayGainTrackGain: $replayGainTrackGain,\n'
        '  replayGainTrackPeak: $replayGainTrackPeak,\n'
        '  vendor: $vendor,\n'
        '  duration: $duration,\n'
        '  trackTotal: $trackTotal,\n'
        '  discNumber: $discNumber,\n'
        '  discTotal: $discTotal,\n'
        '  pictures: $pictures,\n'
        '  bitrate: $bitrate,\n'
        '  sampleRate: $sampleRate,\n'
        '  unknown: $unknowns\n'
        ')';
  }
}
