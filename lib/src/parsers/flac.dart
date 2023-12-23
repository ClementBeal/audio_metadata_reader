import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';

import '../utils/bit_manipulator.dart';

enum BlockType {
  streamInfo,
  padding,
  application,
  seekTable,
  vorbisComment,
  cueSheet,
  picture,
  reserved,
  invalid,
}

///
/// Representation of a FLAC bloc. The only important information is to know
/// if the block is the last one or not
///
class MetadataBlockHeader {
  final bool isLastBlock;
  final int type;
  final int length;

  MetadataBlockHeader(this.isLastBlock, this.type, this.length);
}

///
/// Parser for a FLAC file
///
/// A FLAC file is made of blocks. 3 blocks are interesting for us:
/// - STREAMINFO: bitrate ; samplerate ; duration
/// - VORBIS_COMMENT: contains all the metadata
/// - PICTURE: to get the pictures. Can have multiple `PICTURE` blocks
///
/// All numbers are big-endian coded expecting the numbers from the
/// Vorbis comment
///
/// Documentation: https://xiph.org/flac/format.html
class FlacParser extends TagParser {
  final metadata = VorbisMetadata();

  FlacParser({fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  Future<ParserTag> parse(RandomAccessFile reader) async {
    reader.setPositionSync(4);

    while (true) {
      final block = await _parseMetadataBlock(reader);

      if (block.isLastBlock) break;
    }

    reader.closeSync();

    return metadata;
  }

  Future<MetadataBlockHeader> _parseMetadataBlock(
      RandomAccessFile reader) async {
    final bytes = reader.readSync(4);
    final byteNumber = bytes[0];

    final block = MetadataBlockHeader(
      byteNumber >> 7 == 1,
      byteNumber & 0xFF,
      bytes[3] | bytes[2] << 8 | bytes[1] << 16,
    );

    switch (block.type) {
      case 0:
        reader.readSync(10);

        final end = ByteData.sublistView(reader.readSync(8).buffer.asByteData())
            .getUint64(0);

        final sampleRate = getIntFromArbitraryBits(end, 0, 20);
        final bitPerSample = getIntFromArbitraryBits(end, 23, 5) + 1;
        final totalSamplesInSteam = getIntFromArbitraryBits(end, 28, 36);
        final duration = totalSamplesInSteam / sampleRate * 1000;

        metadata.duration = Duration(milliseconds: duration.toInt());
        metadata.sampleRate = sampleRate;
        metadata.bitrate = (bitPerSample * sampleRate).toInt();

        reader.readSync(128 ~/ 8); // signature
        break;
      case 3:
        reader.readSync(block.length);
        break;
      case 4:
        final bytes = reader.readSync(block.length);
        _parseVorbisComment(bytes);
        break;
      case 6:
        if (!fetchImage) {
          final actualPosition = reader.positionSync();
          reader.setPositionSync(actualPosition + block.length);
        } else {
          final pictureType = getUint32(reader.readSync(4));
          final mimeLength = getUint32(reader.readSync(4));

          final mime = String.fromCharCodes(reader.readSync(mimeLength));
          final descriptionLength = getUint32(reader.readSync(4));
          (descriptionLength > 0)
              ? const Utf8Decoder().convert(reader.readSync(descriptionLength))
              : ""; // description

          reader.readSync(16);
          final lengthData = getUint32(reader.readSync(4));

          final data = reader.readSync(lengthData);
          metadata.pictures
              .add(Picture(data, mime, getPictureTypeEnum(pictureType)));
        }
        break;
      default:
        break;
    }

    return block;
  }

  ///
  /// To detect if this parser can be used to parse this file, the 4 first bytes
  /// must be equal to `fLaC`
  ///
  static Future<bool> canUserParser(RandomAccessFile reader) async {
    reader.setPositionSync(0);
    final vendorName = String.fromCharCodes(reader.readSync(4));
    return vendorName == "fLaC";
  }

  ///
  /// Parse a Vorbis comment. All the number are little-endian coded.
  /// A comment has this structure `<name>=<DATA>`
  /// There may be multiple comments of the same kind
  ///
  /// https://xiph.org/vorbis/doc/v-comment.html
  ///
  void _parseVorbisComment(Uint8List bytes) {
    int offset = 0;

    final vendorLength = getUint32LE(bytes.sublist(0, 4));
    offset = offset + 4 + vendorLength;
    final userCommentListLength = getUint32LE(
      bytes.sublist(offset, offset + 4),
    ); // it's the number of comments / tags / metadata (the way you want to call it)
    offset += 4;

    for (var i = 0; i < userCommentListLength; i++) {
      final length = getUint32LE(bytes.sublist(offset, offset + 4));
      offset += 4;
      final comment = utf8.decode(bytes.sublist(offset, offset + length));
      offset += length;

      final a = comment.split("=");
      final commentName = a[0];
      final value = a[1];

      switch (commentName.toUpperCase()) {
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
          metadata.unknowns[commentName.toUpperCase()] = value;
          break;
      }
    }
  }
}
