import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

import '../utils/bit_manipulator.dart';

class MetadataBlock {
  final bool isLastBlock;

  MetadataBlock(this.isLastBlock);
}

// Documentation: https://xiph.org/flac/format.html
class FlacParser extends TagParser {
  final metadata = VorbisMetadata();
  final bool fetchImage;

  FlacParser({this.fetchImage = false});

  @override
  Future<ParserTag> parse(RandomAccessFile reader) async {
    reader.setPositionSync(0);

    reader.readSync(4);
    // final vendorName = String.fromCharCodes(reader.readSync(4));

    while (true) {
      final block = await _parseMetadataBlock(reader);

      if (block.isLastBlock) break;
    }

    reader.closeSync();

    return metadata;
  }

  Future<MetadataBlock> _parseMetadataBlock(RandomAccessFile reader) async {
    final bytes = reader.readSync(4);

    final byteNumber = bytes[0];
    final isLastBlock = byteNumber >> 7 == 1;
    final length = bytes[3] | bytes[2] << 8 | bytes[1] << 16;

    if ((byteNumber & 0xFF) == 0) {
      reader.readSync(10);
      // final minBlockSize = getUint16(reader.readSync(2));
      // final maxBlockSize = getUint16(reader.readSync(2));
      // final minFrameSize = getUint24(reader.readSync(3));
      // final maxFrameSize = getUint24(reader.readSync(3));

      final end = ByteData.sublistView(reader.readSync(8).buffer.asByteData())
          .getUint64(0);

      final sampleRate = getIntFromArbitraryBits(end, 0, 20);
      // final nbChannels = getIntFromArbitraryBits(end, 20, 3) + 1;
      final bitPerSample = getIntFromArbitraryBits(end, 23, 5) + 1;
      final totalSamplesInSteam = getIntFromArbitraryBits(end, 28, 36);
      final duration = totalSamplesInSteam / sampleRate * 1000;
      metadata.duration = Duration(milliseconds: duration.toInt());

      metadata.sampleRate = sampleRate;
      metadata.bitrate = (bitPerSample * sampleRate).toInt();

      // final signature = String.fromCharCodes(reader.readSync(16));
    } else if ((byteNumber & 0xFF) == 1) {
    } else if ((byteNumber & 0xFF) == 2) {
    } else if ((byteNumber & 0xFF) == 3) {
      // final seekPoints = [];
      // int seekpoint = ;
      reader.readSync(length);
    } else if ((byteNumber & 0xFF) == 4) {
      final bytes = reader.readSync(length);
      int offset = 0;

      final vendorLength = getUint32LE(bytes.sublist(0, 4));
      offset += 4;
      // final vendorString =
      //     String.fromCharCodes(bytes.sublist(offset, vendorLength));
      offset += vendorLength;
      final userCommentListLength =
          getUint32LE(bytes.sublist(offset, offset + 4));
      offset += 4;

      for (var i = 0; i < userCommentListLength; i++) {
        final length = getUint32LE(bytes.sublist(offset, offset + 4));
        offset += 4;
        final comment = utf8.decode(bytes.sublist(offset, offset + length));
        offset += length;

        final a = comment.split("=");
        final key = a[0];
        final value = a[1];

        switch (key.toUpperCase()) {
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
          default:
            metadata.unknowns[key.toUpperCase()] = value;
            break;
        }
      }
    } else if ((byteNumber & 0xFF) == 5) {
    } else if ((byteNumber & 0xFF) == 6) {
      if (!fetchImage) {
        final actualPosition = reader.positionSync();
        reader.setPositionSync(actualPosition + length);
      } else {
        final pictureType = getUint32(reader.readSync(4));
        final mimeLength = getUint32(reader.readSync(4));

        final mime = String.fromCharCodes(reader.readSync(mimeLength));
        final descriptionLength = getUint32(reader.readSync(4));
        final description = (descriptionLength > 0)
            ? const Utf8Decoder().convert(reader.readSync(descriptionLength))
            : "";

        reader.readSync(16);
        // final widthPicture = getUint32(reader.readSync(4));
        // final heightPicture = getUint32(reader.readSync(4));
        // final colorDepth = getUint32(reader.readSync(4));
        // final indexedColor = getUint32(reader.readSync(4));
        final lengthData = getUint32(reader.readSync(4));

        final data = reader.readSync(lengthData);
        metadata.pictures
            .add(Picture(data, mime, getPictureTypeEnum(pictureType)));
      }
    } else {}

    return MetadataBlock(isLastBlock);
  }

  @override
  static Future<bool> canUserParser(RandomAccessFile reader) async {
    reader.setPositionSync(0);
    final vendorName = String.fromCharCodes(reader.readSync(4));
    return vendorName == "fLaC";
  }
}
