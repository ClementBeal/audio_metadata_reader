import 'dart:collection';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

part 'mp3_metadata.dart';
part 'mp4_metadata.dart';
part 'vorbis_metadata.dart';
part 'riff_metadata.dart';

sealed class ParserTag {}

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
