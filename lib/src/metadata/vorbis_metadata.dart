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

  factory VorbisMetadata.merge(
      VorbisMetadata original, VorbisMetadata newData) {
    original.title = newData.title.isNotEmpty ? newData.title : original.title;
    original.version =
        newData.version.isNotEmpty ? newData.version : original.version;
    original.album = newData.album.isNotEmpty ? newData.album : original.album;
    original.trackNumber = newData.trackNumber.isNotEmpty
        ? newData.trackNumber
        : original.trackNumber;
    original.artist =
        newData.artist.isNotEmpty ? newData.artist : original.artist;
    original.performer =
        newData.performer.isNotEmpty ? newData.performer : original.performer;
    original.copyright =
        newData.copyright.isNotEmpty ? newData.copyright : original.copyright;
    original.license =
        newData.license.isNotEmpty ? newData.license : original.license;
    original.organization = newData.organization.isNotEmpty
        ? newData.organization
        : original.organization;
    original.description = newData.description.isNotEmpty
        ? newData.description
        : original.description;
    original.genres =
        newData.genres.isNotEmpty ? newData.genres : original.genres;
    original.date = newData.date.isNotEmpty ? newData.date : original.date;
    original.location =
        newData.location.isNotEmpty ? newData.location : original.location;
    original.contact =
        newData.contact.isNotEmpty ? newData.contact : original.contact;
    original.isrc = newData.isrc.isNotEmpty ? newData.isrc : original.isrc;

    // Additional fields
    original.actor = newData.actor.isNotEmpty ? newData.actor : original.actor;
    original.composer =
        newData.composer.isNotEmpty ? newData.composer : original.composer;
    original.comment =
        newData.comment.isNotEmpty ? newData.comment : original.comment;

    original.actor = newData.actor.isNotEmpty ? newData.actor : original.actor;
    original.composer =
        newData.composer.isNotEmpty ? newData.composer : original.composer;
    original.comment =
        newData.comment.isNotEmpty ? newData.comment : original.comment;
    original.director =
        newData.director.isNotEmpty ? newData.director : original.director;
    original.encodedBy =
        newData.encodedBy.isNotEmpty ? newData.encodedBy : original.encodedBy;
    original.encodedUsing = newData.encodedUsing.isNotEmpty
        ? newData.encodedUsing
        : original.encodedUsing;
    original.encoder =
        newData.encoder.isNotEmpty ? newData.encoder : original.encoder;
    original.encoderOptions = newData.encoderOptions.isNotEmpty
        ? newData.encoderOptions
        : original.encoderOptions;
    original.producer =
        newData.producer.isNotEmpty ? newData.producer : original.producer;
    original.replayGainAlbumGain = newData.replayGainAlbumGain.isNotEmpty
        ? newData.replayGainAlbumGain
        : original.replayGainAlbumGain;
    original.replayGainAlbumPeak = newData.replayGainAlbumPeak.isNotEmpty
        ? newData.replayGainAlbumPeak
        : original.replayGainAlbumPeak;
    original.replayGainTrackGain = newData.replayGainTrackGain.isNotEmpty
        ? newData.replayGainTrackGain
        : original.replayGainTrackGain;
    original.replayGainTrackPeak = newData.replayGainTrackPeak.isNotEmpty
        ? newData.replayGainTrackPeak
        : original.replayGainTrackPeak;
    original.vendor =
        newData.vendor.isNotEmpty ? newData.vendor : original.vendor;

    // Merge unknowns map
    original.unknowns = {...original.unknowns, ...newData.unknowns};

    return original;
  }
}
