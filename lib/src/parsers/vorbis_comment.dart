import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

void parseVorbisComment(
  Uint8List bytes,
  VorbisMetadata metadata,
  bool fetchImage,
) {
  int i = 0;
  final commentBytes = <int>[];

  while (bytes[i] != 0x3D) {
    commentBytes.add(bytes[i]);
    i += 1;
  }
  i += 1;

  final commentName = utf8.decode(commentBytes);

  dynamic value;
  value = utf8.decode(bytes.sublist(i));

  switch (commentName.toUpperCase()) {
    case 'METADATA_BLOCK_PICTURE':
      if (!fetchImage) {
        return;
      }

      final imageValue = value = base64Decode(value);
      final buffer = ByteData.sublistView(imageValue);
      int offset = 0;

      final pictureType = buffer.getUint32(offset);
      offset += 4;
      final mimeLength = buffer.getUint32(offset);
      offset += 4;

      final mime =
          String.fromCharCodes(buffer.buffer.asUint8List(offset, mimeLength));
      offset += mimeLength;

      final descriptionLength = buffer.getUint32(offset);
      offset += 4 + descriptionLength + 16;

      final lengthData = buffer.getUint32(offset);
      offset += 4;

      final data = buffer.buffer.asUint8List(offset, lengthData);

      metadata.pictures
          .add(Picture(data, mime, getPictureTypeEnum(pictureType)));

      break;
    case 'TITLE':
      metadata.title.add(value);
      break;
    case 'VERSION':
      metadata.version.add(value);
      break;
    case 'ALBUM':
      metadata.album.add(value);
      break;
    case 'TRACKNUMBER' || 'ITUNES_CDDB_TRACKNUMBER':
      if (value.contains("/")) {
        metadata.trackNumber.add(int.parse(value.split("/").first));
      } else {
        metadata.trackNumber.add(int.parse(value));
      }
      break;
    case 'ARTIST' || "ALBUMARTIST":
      metadata.artist.add(value);
      break;
    case 'PERFORMER':
      metadata.performer.add(value);
      break;
    case 'COPYRIGHT':
      metadata.copyright.add(value);
      break;
    case 'LICENSE':
      metadata.license.add(value);
      break;
    case 'ORGANIZATION' || "PUBLISHER":
      metadata.organization.add(value);
      break;
    case 'DESCRIPTION':
      metadata.description.add(value);
      break;
    case 'GENRE':
      metadata.genres.add(value);
      break;
    case 'DATE':
      final parsedDatetime = DateTime.tryParse(value);

      if (parsedDatetime != null) {
        metadata.date.add(parsedDatetime);
      } else if (value.contains("/")) {
        metadata.date.add(DateTime(int.parse(value.split("/").first)));
      } else if (int.tryParse(value) != null) {
        metadata.date.add(DateTime(int.parse(value)));
      }
      break;
    case 'LOCATION':
      metadata.location.add(value);
      break;
    case 'CONTACT':
      metadata.contact.add(value);
      break;
    case 'ISRC':
      metadata.isrc.add(value);
      break;
    case 'ACTOR':
      metadata.actor.add(value);
      break;
    case 'COMPOSER':
      metadata.composer.add(value);
      break;
    case 'COMMENT':
      metadata.comment.add(value);
      break;
    case 'DIRECTOR':
      metadata.director.add(value);
      break;
    case 'ENCODED_BY':
      metadata.encodedBy.add(value);
      break;
    case 'ENCODED_USING':
      metadata.encodedUsing.add(value);
      break;
    case 'ENCODER':
      metadata.encoder.add(value);
      break;
    case 'ENCODER_OPTIONS':
      metadata.encoderOptions.add(value);
      break;
    case 'PRODUCER':
      metadata.producer.add(value);
      break;
    case 'REPLAYGAIN_ALBUM_GAIN':
      metadata.replayGainAlbumGain.add(value);
      break;
    case 'REPLAYGAIN_ALBUM_PEAK':
      metadata.replayGainAlbumPeak.add(value);
      break;
    case 'REPLAYGAIN_TRACK_GAIN':
      metadata.replayGainTrackGain.add(value);
      break;
    case 'REPLAYGAIN_TRACK_PEAK':
      metadata.replayGainTrackPeak.add(value);
      break;
    case 'VENDOR':
      metadata.vendor.add(value);
      break;
    case 'TRACKTOTAL' || 'TOTALTRACKS':
      metadata.trackTotal = int.parse(value);
      break;
    case 'DISCNUMBER':
      if (value.contains("/")) {
        metadata.discNumber = int.parse(value.split("/").first);
      } else {
        metadata.discNumber = int.parse(value);
      }
      break;
    case 'DISCTOTAL' || 'TOTALDISCS':
      metadata.discTotal = int.parse(value);
      break;
    case "LYRICS":
      metadata.lyric = value;
      break;
    case "LENGTH":
      final lengthValue = int.parse(value);
      metadata.duration = Duration(milliseconds: lengthValue);
      break;
    default:
      metadata.unknowns[commentName.toUpperCase()] = value;
      break;
  }
}
