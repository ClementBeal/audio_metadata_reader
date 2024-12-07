import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';

/// Picture is a representation of the images we can find in an ID3 tag
/// It's also used by Flac and OGG
class Picture {
  /// The data of the picture/cover
  final Uint8List bytes;

  /// The mimetype of the picture/cover
  final String mimetype;

  /// Additional information when available
  /// It can be the front cover, back cover, artist's picture...
  final PictureType pictureType;

  Picture(this.bytes, this.mimetype, this.pictureType);

  @override
  String toString() {
    return 'Picture{'
        'bytes: ${bytes.length} bytes, '
        'mimetype: $mimetype, '
        'pictureType: $pictureType}';
  }
}

/// An abstract class to represent the result of a parser
abstract class ParserTag {}

/// A generic class to gather the metadata. To make it universal, some format-specific metadata
/// are dropped.
///
/// To use more precise metadata information related to a format, please
/// use the parser of the format.
class AudioMetadata {
  /// The name of the album
  String? album;

  /// The year of when the album/track has been released
  DateTime? year;

  /// The language of the track
  String? language;

  /// The main artist of the track
  /// For classical music, it would be the composer
  /// In popular music this is usually the performing band or singer
  String? artist;

  /// The artists that are on a track but are not consired as the main artist
  /// For instance with `Dr. Dre - Still D.R.E. ft. Snoop Dogg`, Snoop Dogg is
  /// a performer
  final List<String> performers = [];

  /// The track's title
  String? title;

  /// The track order in the album
  int? trackNumber;

  /// The total number of tracks in the album
  int? trackTotal;

  /// The duration of the track
  Duration? duration;

  late List<String> genres;

  /// The disc number containing this track
  int? discNumber;

  /// The number of disc for the album
  int? totalDisc;

  /// The lyric of the track. Can be nornal text or LRC
  String? lyrics;

  /// The bitrate
  int? bitrate;

  /// The samplerate
  int? sampleRate;

  /// The pictures containing in the track
  late List<Picture> pictures;

  /// A reference to the file that contains the metadata
  File file;

  AudioMetadata({
    this.album,
    this.year,
    this.language,
    this.artist,
    this.title,
    this.trackNumber,
    this.trackTotal,
    this.duration,
    this.discNumber,
    this.totalDisc,
    this.lyrics,
    this.bitrate,
    this.sampleRate,
    required this.file,
  }) {
    genres = [];
    pictures = [];
  }
}

abstract class TagParser {
  final bool fetchImage;

  TagParser({required this.fetchImage});
  ParserTag parse(RandomAccessFile reader);
}
