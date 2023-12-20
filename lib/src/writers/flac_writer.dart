import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:intl/intl.dart';

class FlacWriter {
  bool _hasPictureBlock = false;

  Future<void> write(File track, VorbisMetadata metadata) async {
    final reader = await track.open(mode: FileMode.read);
    final futureData = [..."fLaC".codeUnits];

    reader.readSync(4); // vender name fLaC
    bool isLastBlock = false;

    while (!isLastBlock) {
      // first byte: isLastBlock + block type
      // other bytes: length of metadatablock
      final bytes = reader.readSync(4);
      // futureData.add(bytes[0]);
      final byteNumber = bytes[0];
      isLastBlock = byteNumber >> 7 == 1;
      final length = getUint24(bytes.sublist(1));

      if (isLastBlock && !_hasPictureBlock && metadata.pictures.isNotEmpty) {
        // add the picture block if doesnt exist

        for (var picture in metadata.pictures) {
          final imageBytes = <int>[];
          imageBytes
              .addAll(intToUint32(pictureTypeValue[picture.pictureType] ?? 0));
          imageBytes.addAll(intToUint32(picture.mimetype.length));
          imageBytes.addAll(const AsciiEncoder().convert(picture.mimetype));
          imageBytes.addAll(intToUint32(1));
          imageBytes.addAll(const Utf8Encoder().convert("A")); // description
          imageBytes.addAll(intToUint32(405)); // width
          imageBytes.addAll(intToUint32(405)); // height
          imageBytes.addAll(intToUint32(24)); // color depth
          imageBytes.addAll(intToUint32(0)); // number of color used
          imageBytes.addAll(intToUint32(picture.bytes.length));
          imageBytes.addAll(picture.bytes);

          futureData.addAll(Uint8List.fromList(
              [6])); // block header (not last block + block type)
          futureData.addAll(intToUint24(imageBytes.length));
          futureData.addAll(imageBytes);
        }
      }

      switch (byteNumber) {
        case 4: // metadata
          final tmpData = <int>[];

          final vendorLengthBytes = reader.readSync(4);
          final vendorLength = getUint32LE(vendorLengthBytes);

          final vendorStringBytes = reader.readSync(vendorLength);
          // final vendorString = Utf8Decoder().convert(vendorStringBytes);

          final userCommentListLengthBytes = reader.readSync(4);
          final userCommentListLength = getUint32LE(userCommentListLengthBytes);

          tmpData.addAll(vendorLengthBytes);
          tmpData.addAll(vendorStringBytes);

          final currentMetadata = VorbisMetadata();

          for (int i = 0; i < userCommentListLength; i++) {
            final length = getUint32LE(reader.readSync(4));
            final commentBytes = reader.readSync(length);
            final comment = const Utf8Decoder().convert(commentBytes);

            final a = comment.split("=");
            final key = a[0].toUpperCase();
            final value = a[1];
            switch (key) {
              case "TITLE":
                currentMetadata.title.add(value);
                break;
              case "ALBUM":
                currentMetadata.album.add(value);
                break;
              case "VERSION":
                currentMetadata.version.add(value);
                break;
              case "TRACKNUMBER":
                currentMetadata.trackNumber.add(int.parse(value));
                break;
              case "ARTIST":
                currentMetadata.artist.add(value);
                break;
              case "PERFORMER":
                currentMetadata.performer.add(value);
                break;
              case "COPYRIGHT":
                currentMetadata.copyright.add(value);
                break;
              case "LICENSE":
                currentMetadata.license.add(value);
                break;
              case "ORGANIZATION":
                currentMetadata.organization.add(value);
                break;
              case "DESCRIPTION":
                currentMetadata.description.add(value);
                break;
              case "GENRE":
                currentMetadata.genres.add(value);
                break;
              case "DATE":
                if (DateTime.tryParse(value) != null) {
                  currentMetadata.date.add(DateTime.parse(value));
                } else if (value.contains("/")) {
                  currentMetadata.date
                      .add(DateFormat("yyyy/MM/dd").parse(value));
                } else if (value.contains("-")) {
                  currentMetadata.date
                      .add(DateFormat("yyyy-MM-dd").parse(value));
                }
                break;
              case "LOCATION":
                currentMetadata.location.add(value);
                break;
              case "CONTACT":
                currentMetadata.contact.add(value);
                break;
              case "ISRC":
                currentMetadata.isrc.add(value);
                break;
              default:
            }
          }

          final mergedMetadata =
              VorbisMetadata.merge(currentMetadata, metadata);
          final commentData = <int>[];
          int numberOfComments = 0;

          void addFieldToTmpData(List<String> fieldValues, String fieldName) {
            if (fieldValues.isNotEmpty) {
              for (var value in fieldValues) {
                numberOfComments++;
                final entry = "$fieldName=$value";
                commentData.addAll(intToUint32LE(entry.length));
                commentData.addAll(const Utf8Encoder().convert(entry));
              }
            }
          }

          addFieldToTmpData(mergedMetadata.title, "TITLE");
          addFieldToTmpData(mergedMetadata.version, "VERSION");
          addFieldToTmpData(mergedMetadata.album, "ALBUM");
          addFieldToTmpData(
              mergedMetadata.trackNumber.map((e) => e.toString()).toList(),
              "TRACKNUMBER");
          addFieldToTmpData(mergedMetadata.artist, "ARTIST");
          addFieldToTmpData(mergedMetadata.performer, "PERFORMER");
          addFieldToTmpData(mergedMetadata.copyright, "COPYRIGHT");
          addFieldToTmpData(mergedMetadata.license, "LICENSE");
          addFieldToTmpData(mergedMetadata.organization, "ORGANIZATION");
          addFieldToTmpData(mergedMetadata.description, "DESCRIPTION");
          addFieldToTmpData(mergedMetadata.genres, "GENRE");
          addFieldToTmpData(
              mergedMetadata.date
                  .map((e) => DateFormat("yyyy-MM-dd").format(e))
                  .toList(),
              "DATE");
          addFieldToTmpData(mergedMetadata.location, "LOCATION");
          addFieldToTmpData(mergedMetadata.contact, "CONTACT");
          addFieldToTmpData(mergedMetadata.isrc, "ISRC");
          addFieldToTmpData(mergedMetadata.composer, "COMPOSER");
          addFieldToTmpData(mergedMetadata.comment, "COMMENT");
          addFieldToTmpData(mergedMetadata.director, "DIRECTOR");
          addFieldToTmpData(mergedMetadata.encodedBy, "ENCODED_BY");
          addFieldToTmpData(mergedMetadata.encodedUsing, "ENCODED_USING");
          addFieldToTmpData(mergedMetadata.encoder, "ENCODER");
          addFieldToTmpData(mergedMetadata.encoderOptions, "ENCODER_OPTIONS");
          addFieldToTmpData(mergedMetadata.producer, "PRODUCER");
          addFieldToTmpData(
              mergedMetadata.replayGainAlbumGain, "REPLAYGAIN_ALBUM_GAIN");
          addFieldToTmpData(
              mergedMetadata.replayGainAlbumPeak, "REPLAYGAIN_ALBUM_PEAK");
          addFieldToTmpData(
              mergedMetadata.replayGainTrackGain, "REPLAYGAIN_TRACK_GAIN");
          addFieldToTmpData(
              mergedMetadata.replayGainTrackPeak, "REPLAYGAIN_TRACK_PEAK");
          addFieldToTmpData(mergedMetadata.vendor, "VENDOR");

          if (mergedMetadata.duration != null) {
            final durationInSeconds = mergedMetadata.duration!.inSeconds;
            addFieldToTmpData([durationInSeconds.toString()], "DURATION");
          }

          addFieldToTmpData(
              mergedMetadata.trackTotal == null
                  ? []
                  : [mergedMetadata.trackTotal.toString()],
              "TRACKTOTAL");
          addFieldToTmpData(
              mergedMetadata.discNumber == null
                  ? []
                  : [mergedMetadata.discNumber.toString()],
              "DISCNUMBER");
          addFieldToTmpData(
              mergedMetadata.discTotal == null
                  ? []
                  : [mergedMetadata.discTotal.toString()],
              "DISCTOTAL");
          // addFieldToTmpData([mergedMetadata.lyric], "LYRIC");

          addFieldToTmpData(
              mergedMetadata.bitrate == null
                  ? []
                  : [mergedMetadata.bitrate.toString()],
              "BITRATE");
          addFieldToTmpData(
              mergedMetadata.sampleRate == null
                  ? []
                  : [mergedMetadata.sampleRate.toString()],
              "SAMPLERATE");

// Merge unknowns map
          for (var entry in mergedMetadata.unknowns.entries) {
            final unknownEntry = "${entry.key}=${entry.value}";
            commentData.addAll(intToUint32LE(unknownEntry.length));
            commentData.addAll(const Utf8Encoder().convert(unknownEntry));
          }

          tmpData.addAll(intToUint32LE(numberOfComments));
          tmpData.addAll(commentData);

          if (tmpData.length < 16) {
            tmpData.addAll(List.generate(16 - tmpData.length, (index) => 0));
          }

          futureData.addAll(Uint8List.fromList(
              [4])); // block header (not last block + block type)
          futureData.addAll(intToUint24(tmpData.length));
          futureData.addAll(tmpData);
          break;
        case 6 when (metadata.pictures.isNotEmpty): // cover
          _hasPictureBlock = true; // otherwise, we have to create the block
          reader.setPositionSync(reader.positionSync() + length);
          final picture = metadata.pictures.first;
          final imageBytes = <int>[];
          imageBytes
              .addAll(intToUint32(pictureTypeValue[picture.pictureType] ?? 0));
          imageBytes.addAll(intToUint32(picture.mimetype.length));
          imageBytes.addAll(const AsciiEncoder().convert(picture.mimetype));
          imageBytes.addAll([0, 0, 0, 0]);
          imageBytes.addAll(const Utf8Encoder().convert(""));
          imageBytes.addAll(intToUint32(500)); // width
          imageBytes.addAll(intToUint32(500)); // height
          imageBytes.addAll(intToUint32(24)); // color depth
          imageBytes.addAll(intToUint32(0)); // number of color used

          imageBytes.addAll(intToUint32(picture.bytes.length));
          imageBytes.addAll(picture.bytes);
          // final coverBytes = _writeCover();
          // futureData.addAll(intToUint24(coverBytes.length));
          // futureData.addAll(coverBytes);

          break;
        case _:
          futureData.addAll([bytes[0], bytes[1], bytes[2], bytes[3]]);
          futureData.addAll(reader.readSync(length));
          break;
      }
    }
    final restData =
        reader.readSync(reader.lengthSync() - reader.positionSync());
    reader.closeSync();

    final z = await track.open(mode: FileMode.write);
    z.writeFromSync(futureData);
    z.writeFromSync(restData);
    z.closeSync();
  }
}
