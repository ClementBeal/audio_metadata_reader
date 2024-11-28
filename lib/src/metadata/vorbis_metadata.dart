import 'dart:collection';

import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

// https://xiph.org/vorbis/doc/v-comment.html
// https://exiftool.org/TagNames/Vorbis.html
class VorbisMetadata extends ParserTag {
  List<String> title = []; // TITLE
  List<String> version = []; // VERSION
  List<String> album = []; // ALBUM
  List<int> trackNumber = []; // TRACKNUMBER
  List<String> artist = []; // ARTIST
  List<String> performer = []; // PERFORMER
  List<String> copyright = []; // COPYRIGHT
  List<String> license = []; // LICENSE
  List<String> organization = []; // ORGANIZATION
  List<String> description = []; // DESCRIPTION
  List<String> genres = []; // GENRE
  List<DateTime> date = []; // DATE
  List<String> location = []; // LOCATION
  List<String> contact = []; // CONTACT
  List<String> isrc = []; // ISRC

  // Additional fields
  List<String> actor = []; // ACTOR
  List<String> composer = []; // COMPOSER
  List<String> comment = []; // COMMENT
  List<String> director = []; // DIRECTOR
  List<String> encodedBy = []; // ENCODED_BY
  List<String> encodedUsing = []; // ENCODED_USING
  List<String> encoder = []; // ENCODER
  List<String> encoderOptions = []; // ENCODER_OPTIONS
  List<String> producer = []; // PRODUCER
  List<String> replayGainAlbumGain = []; // REPLAYGAIN_ALBUM_GAIN
  List<String> replayGainAlbumPeak = []; // REPLAYGAIN_ALBUM_PEAK
  List<String> replayGainTrackGain = []; // REPLAYGAIN_TRACK_GAIN
  List<String> replayGainTrackPeak = []; // REPLAYGAIN_TRACK_PEAK
  List<String> vendor = []; // vendor (from comment header)
  Map<String, String> unknowns = HashMap();

  // BONUS

  Duration? duration;
  int? trackTotal;
  int? discNumber;
  int? discTotal;
  String? lyric;
  List<Picture> pictures = [];
  int? bitrate;
  int? sampleRate;

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
        '  vendor: $vendor\n'
        '  duration: $duration\n'
        '  trackTotal: $trackTotal\n'
        '  discNumber: $discNumber\n'
        '  discTotal: $discTotal\n'
        '  pictures: $pictures\n'
        '  bitrate: $bitrate\n'
        '  sampleRate: $sampleRate\n'
        '  unknown: $unknowns\n'
        ')';
  }
}
