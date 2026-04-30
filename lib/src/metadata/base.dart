import 'dart:collection';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

part 'mp3_metadata.dart';
part 'mp4_metadata.dart';
part 'vorbis_metadata.dart';
part 'riff_metadata.dart';
part 'ape_metadata.dart';

/// Base type for every format-specific metadata model.
sealed class ParserTag {}

/// A single chapter marker (for example in podcasts or audiobooks).
class Chapter {
  /// Timestamp where the chapter starts.
  final Duration start;

  /// Human-readable chapter title.
  final String title;

  Chapter({
    required this.start,
    required this.title,
  });

  @override
  String toString() {
    return 'Chapter(start: $start, title: $title)';
  }
}

/// Kind of attached picture based on ID3/APIC-compatible semantics.
enum PictureType {
  other,
  fileIcon32x32,
  otherFileIcon,
  coverFront,
  coverBack,
  leafletPage,
  mediaLabelCD,
  leadArtist,
  artistPerformer,
  conductor,
  bandOrchestra,
  composer,
  lyricistTextWriter,
  recordingLocation,
  duringRecording,
  duringPerformance,
  movieVideoScreenCapture,
  brightColouredFish,
  illustration,
  bandArtistLogotype,
  publisherStudioLogotype,
}

/// Numeric mapping used by formats that store picture type as an integer code.
Map<PictureType, int> pictureTypeValue = {
  PictureType.other: 0,
  PictureType.fileIcon32x32: 1,
  PictureType.otherFileIcon: 2,
  PictureType.coverFront: 3,
  PictureType.coverBack: 4,
  PictureType.leafletPage: 5,
  PictureType.mediaLabelCD: 6,
  PictureType.leadArtist: 7,
  PictureType.artistPerformer: 8,
  PictureType.conductor: 9,
  PictureType.bandOrchestra: 10,
  PictureType.composer: 11,
  PictureType.lyricistTextWriter: 12,
  PictureType.recordingLocation: 13,
  PictureType.duringRecording: 14,
  PictureType.duringPerformance: 15,
  PictureType.movieVideoScreenCapture: 16,
  PictureType.brightColouredFish: 17,
  PictureType.illustration: 18,
  PictureType.bandArtistLogotype: 19,
  PictureType.publisherStudioLogotype: 20,
};

/// Convert a numeric picture type code into [PictureType].
///
/// Unknown values fall back to [PictureType.other].
PictureType getPictureTypeEnum(int value) {
  switch (value) {
    case 0:
      return PictureType.other;
    case 1:
      return PictureType.fileIcon32x32;
    case 2:
      return PictureType.otherFileIcon;
    case 3:
      return PictureType.coverFront;
    case 4:
      return PictureType.coverBack;
    case 5:
      return PictureType.leafletPage;
    case 6:
      return PictureType.mediaLabelCD;
    case 7:
      return PictureType.leadArtist;
    case 8:
      return PictureType.artistPerformer;
    case 9:
      return PictureType.conductor;
    case 10:
      return PictureType.bandOrchestra;
    case 11:
      return PictureType.composer;
    case 12:
      return PictureType.lyricistTextWriter;
    case 13:
      return PictureType.recordingLocation;
    case 14:
      return PictureType.duringRecording;
    case 15:
      return PictureType.duringPerformance;
    case 16:
      return PictureType.movieVideoScreenCapture;
    case 17:
      return PictureType.brightColouredFish;
    case 18:
      return PictureType.illustration;
    case 19:
      return PictureType.bandArtistLogotype;
    case 20:
      return PictureType.publisherStudioLogotype;
    default:
      // Handle any other cases or provide a default value
      return PictureType.other;
  }
}

/// Convenience setters that normalize common metadata writes across formats.
extension CommonMetadataSetters on ParserTag {
  /// Update the track title.
  void setTitle(String? title) {
    switch (this) {
      case Mp3Metadata m:
        m.songName = title;
        break;
      case Mp4Metadata m:
        m.title = title;
        break;
      case VorbisMetadata m:
        m.title = title == null ? [] : [title];
        break;
      case RiffMetadata m:
        m.title = title;
        break;
      case ApeMetadata m:
        m.title = title;
        break;
    }
  }

  /// Update the main artist.
  void setArtist(String? artist) {
    switch (this) {
      case Mp3Metadata m:
        m.leadPerformer = artist;
        break;
      case Mp4Metadata m:
        m.artist = artist;
        break;
      case VorbisMetadata m:
        m.artist = artist == null ? m.artist : [artist];
        break;
      case RiffMetadata m:
        m.artist = artist;
        break;
      case ApeMetadata m:
        m.artist = artist;
        break;
    }
  }

  /// Update the album name.
  void setAlbum(String? album) {
    switch (this) {
      case Mp3Metadata m:
        m.album = album;
        break;
      case Mp4Metadata m:
        m.album = album;
        break;
      case VorbisMetadata m:
        m.album = album == null ? [] : [album];
        break;
      case RiffMetadata m:
        m.album = album;
        break;
      case ApeMetadata m:
        m.album = album;
        break;
    }
  }

  /// Update the release year/date.
  void setYear(DateTime? year) {
    switch (this) {
      case Mp3Metadata m:
        m.year = year?.year;
        break;
      case Mp4Metadata m:
        m.year = year;
        break;
      case VorbisMetadata m:
        m.date = year == null ? [] : [year];
        break;
      case RiffMetadata m:
        m.year = year;
        break;
      case ApeMetadata m:
        m.date = year;
        break;
    }
  }

  /// Replace attached pictures.
  void setPictures(List<Picture> pictures) {
    switch (this) {
      case Mp3Metadata m:
        m.pictures = pictures;
        break;
      case Mp4Metadata m:
        m.picture = pictures.firstOrNull;
        break;
      case VorbisMetadata m:
        m.pictures = pictures;
        break;
      case RiffMetadata m:
        m.pictures = pictures;
        break;
      case ApeMetadata m:
        m.pictures = pictures;
        break;
    }
  }

  /// Update the track number inside the album.
  void setTrackNumber(int? trackNumber) {
    switch (this) {
      case Mp3Metadata m:
        m.trackNumber = trackNumber;
        break;
      case Mp4Metadata m:
        m.trackNumber = trackNumber;
        break;
      case VorbisMetadata m:
        m.trackNumber = trackNumber == null ? [] : [trackNumber];
        break;
      case RiffMetadata m:
        m.trackNumber = trackNumber;
        break;
      case ApeMetadata m:
        m.trackNumber = trackNumber;
        break;
    }
  }

  /// Update the total number of tracks in the album.
  ///
  /// Has no effect on RIFF metadata (`.wav`).
  void setTrackTotal(int? trackTotal) {
    switch (this) {
      case Mp3Metadata m:
        m.trackTotal = trackTotal;
        break;
      case Mp4Metadata m:
        m.totalTracks = trackTotal;
        break;
      case VorbisMetadata m:
        m.trackTotal = trackTotal;
        break;
      case RiffMetadata():
        break;
      case ApeMetadata m:
        m.trackTotal = trackTotal;
        break;
    }
  }

  /// Update lyrics text.
  ///
  /// Has no effect on RIFF metadata (`.wav`).
  void setLyrics(String? lyric) {
    switch (this) {
      case Mp3Metadata m:
        m.lyric = lyric;
        break;
      case Mp4Metadata m:
        m.lyrics = lyric;
        break;
      case VorbisMetadata m:
        m.lyric = lyric;
        break;
      case RiffMetadata():
        break;
      case ApeMetadata m:
        m.lyric = lyric;
        break;
    }
  }

  /// Replace genres.
  void setGenres(List<String> genres) {
    switch (this) {
      case Mp3Metadata m:
        m.genres = genres;
        break;
      case Mp4Metadata m:
        m.genre = genres.firstOrNull;
        break;
      case VorbisMetadata m:
        m.genres = genres;
        break;
      case RiffMetadata m:
        m.genre = genres.firstOrNull;
        break;
      case ApeMetadata m:
        m.genres = genres;
        break;
    }
  }

  /// Update disc number and total disc count.
  ///
  /// Has no effect on RIFF metadata (`.wav`).
  void setCD(int? cdNumber, int? discTotal) {
    switch (this) {
      case Mp3Metadata m:
        if (cdNumber != null && discTotal == null)
          m.partOfSet = "$cdNumber";
        else if (cdNumber != null && discTotal != null)
          m.partOfSet = "$cdNumber/$discTotal";
        break;
      case Mp4Metadata m:
        m.discNumber = cdNumber;
        m.totalDiscs = discTotal;
        break;
      case VorbisMetadata m:
        m.discNumber = cdNumber;
        m.discTotal = discTotal;
        break;
      case RiffMetadata():
        break;
      case ApeMetadata m:
        m.discNumber = cdNumber;
        m.discTotal = discTotal;
        break;
    }
  }
}
