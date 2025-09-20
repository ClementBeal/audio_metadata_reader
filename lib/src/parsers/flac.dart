import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

import '../utils/bit_manipulator.dart';

/// The different reserved block types that are defined
/// for this format
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
typedef MetadataBlockHeader = ({bool isLastBlock, int type, int length});

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
  late final Buffer buffer;

  FlacParser({super.fetchImage = false});

  @override
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    buffer = Buffer(randomAccessFile: reader);

    buffer.skip(4);

    bool isLastBlock = false;
    while (!isLastBlock) {
      final block = _parseMetadataBlock(reader);

      isLastBlock = block.isLastBlock;
    }

    reader.closeSync();

    return metadata;
  }

  MetadataBlockHeader _parseMetadataBlock(RandomAccessFile reader) {
    final bytes = buffer.read(4);
    final byteNumber = bytes[0];

    final MetadataBlockHeader block = (
      isLastBlock: byteNumber >> 7 == 1, // 0: not last block - 1: last block
      type: byteNumber & 0x7F, // keep the 7 next bits (0XXXXXXX)
      length: bytes[3] | bytes[2] << 8 | bytes[1] << 16,
    );

    switch (block.type) {
      case 0:
        buffer.skip(10);

        final end = ByteData.sublistView(buffer.read(8)).getUint64(0);

        final sampleRate = getIntFromArbitraryBits(end, 0, 20);
        final bitPerSample = getIntFromArbitraryBits(end, 23, 5) + 1;
        final totalSamplesInSteam = getIntFromArbitraryBits(end, 28, 36);
        final duration = totalSamplesInSteam / sampleRate * 1000;

        metadata.duration = Duration(milliseconds: duration.toInt());
        metadata.sampleRate = sampleRate;
        metadata.bitrate = (bitPerSample * sampleRate).toInt();

        buffer.skip(16); // signature (128 ~/ 8)
        break;
      case 3:
        buffer.skip(block.length);
        break;
      case 4:
        final bytes = buffer.read(block.length);
        _parseVorbisComment(bytes);
        break;
      case 6:
        if (!fetchImage) {
          buffer.skip(block.length);
        } else {
          final pictureType = getUint32(buffer.read(4));
          final mimeLength = getUint32(buffer.read(4));

          final mime = String.fromCharCodes(buffer.read(mimeLength));
          final descriptionLength = getUint32(buffer.read(4));

          buffer.skip(descriptionLength + 16);
          // (descriptionLength > 0)
          //     ? const Utf8Decoder().convert(buffer.read(descriptionLength))
          //     : ""; // description

          // buffer.skip(16);
          final lengthData = getUint32(buffer.read(4));

          final data = buffer.read(lengthData);
          metadata.pictures.add(
            Picture(
              data,
              mime,
              getPictureTypeEnum(pictureType),
            ),
          );
        }
        break;
      default:
        buffer.skip(block.length);
        break;
    }

    return block;
  }

  /// To detect if this parser can be used to parse this file, the 4 first bytes
  /// must be equal to `fLaC`
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);
    final vendorName = String.fromCharCodes(reader.readSync(4));
    return vendorName == "fLaC";
  }

  /// Parse a Vorbis comment. All the number are little-endian coded.
  /// A comment has this structure `<name>=<DATA>`
  /// There may be multiple comments of the same kind
  ///
  /// https://xiph.org/vorbis/doc/v-comment.html
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
      final value = a.sublist(1).join("="); // 避免 value 中也有 "=" 被截断

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
