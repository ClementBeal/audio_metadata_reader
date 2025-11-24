import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/flac.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/writers/base_writer.dart';

class FlacWriter extends BaseMetadataWriter<VorbisMetadata> {
  @override
  Future<Uint8List> writeToBytes(Uint8List inputBytes, VorbisMetadata metadata) async {
    final builder = BytesBuilder();
    int position = 0;

    builder.add(inputBytes.sublist(position, position + 4));
    position += 4;

    bool isLastBlock = false;
    int i = 0;
    while (!isLastBlock) {
      if (i == 1) {
        _writeVorbisComments(builder, metadata);

        for (var picture in metadata.pictures) {
          _writePictureBlock(builder, picture);
        }
      }

      final block = _parseMetadataBlock(inputBytes, position, builder, metadata);
      position = block.newPosition;
      isLastBlock = block.isLastBlock;
      i++;
    }

    builder.add(inputBytes.sublist(position));

    return builder.toBytes();
  }

  ({bool isLastBlock, int type, int length, int newPosition}) _parseMetadataBlock(
      Uint8List inputBytes, int position, BytesBuilder builder, VorbisMetadata metadata) {
    final bytes = inputBytes.sublist(position, position + 4);
    final byteNumber = bytes[0];

    final MetadataBlockHeader block = (
      isLastBlock: byteNumber >> 7 == 1, // 0: not last block - 1: last block
      type: byteNumber & 0x7F, // keep the 7 next bits (0XXXXXXX)
      length: bytes[3] | bytes[2] << 8 | bytes[1] << 16,
    );

    int newPosition = position + 4;

    // we skip the metadata blocks because we rewrite them
    // block 4 -> Vorbis comment
    // block 6 -> picture
    switch (block.type) {
      case 3:
      case 4:
      case 6:
        newPosition += block.length;
        break;
      default:
        _writeBlock(
          builder,
          inputBytes.sublist(newPosition, newPosition + block.length),
          block.type,
          block.isLastBlock,
        );
        newPosition += block.length;
        break;
    }

    return (
      isLastBlock: block.isLastBlock,
      type: block.type,
      length: block.length,
      newPosition: newPosition,
    );
  }

  void _writeBlockHeader(
      BytesBuilder builder, int blockType, int length, bool isLastBlock) {
    int firstByte = isLastBlock ? (1 << 7) : 0;
    firstByte = (firstByte | blockType);

    builder.addByte(firstByte);
    builder.add(intToUint24(length));
  }

  void _writeBlock(
      BytesBuilder builder, Uint8List data, int blockId, bool isLastBlock) {
    int firstByte = (isLastBlock) ? 255 | blockId : blockId & 255;

    builder.addByte(firstByte);
    builder.add(intToUint24(data.length));

    builder.add(data);
  }

  void _writePictureBlock(BytesBuilder builder, Picture picture) {
    final headerBytes = BytesBuilder();

    headerBytes.add(intToUint32(picture.pictureType.index));
    headerBytes.add(intToUint32(picture.mimetype.length));
    headerBytes.add(ascii.encode(picture.mimetype));
    headerBytes.add(intToUint32(0)); // No Description for now
    headerBytes.add(intToUint32(0)); // No width for now
    headerBytes.add(intToUint32(0)); // No height for now
    headerBytes.add(intToUint32(0)); // No color depth for now
    headerBytes.add(intToUint32(0)); // No color number for now
    headerBytes.add(intToUint32(picture.bytes.length));
    headerBytes.add(picture.bytes);

    final blockLength = headerBytes.length;

    _writeBlockHeader(builder, 6, blockLength, false);
    builder.add(headerBytes.toBytes());
  }

  void _writeVorbisComments(BytesBuilder builder, VorbisMetadata metadata) {
    final mainBuilder = BytesBuilder();
    final commentsBuilder = BytesBuilder();

    // vendor length
    // I don't know what to use. The library name? The user selects the name he wants?
    mainBuilder.add(intToUint32LE(0));

    int i = 0;

    void _writeComment(String name, List<String> data) {
      if (data.isNotEmpty) {
        for (var d in data) {
          i++;
          final toWrite = utf8.encode("$name=$d");
          commentsBuilder.add(intToUint32LE(toWrite.length));
          commentsBuilder.add(toWrite);
        }
      }
    }

    _writeComment("TITLE", metadata.title);
    _writeComment("VERSION", metadata.version);
    _writeComment("ALBUM", metadata.album);
    _writeComment(
        "TRACKNUMBER", metadata.trackNumber.map((e) => e.toString()).toList());
    _writeComment("ARTIST", metadata.artist);
    _writeComment("PERFORMER", metadata.performer);
    _writeComment("COPYRIGHT", metadata.copyright);
    _writeComment("LICENSE", metadata.license);
    _writeComment("ORGANIZATION", metadata.organization);
    _writeComment("DESCRIPTION", metadata.description);
    _writeComment("GENRE", metadata.genres);
    _writeComment(
        "DATE",
        metadata.date
            .map((d) =>
                "${d.year}/${d.month.toString().padLeft(2, "0")}/${d.day.toString().padLeft(2, "0")}")
            .toList());
    _writeComment("LOCATION", metadata.location);
    _writeComment("CONTACT", metadata.contact);
    _writeComment("ISRC", metadata.isrc);

    mainBuilder.add(intToUint32LE(i));
    mainBuilder.add(commentsBuilder.toBytes());

    _writeBlockHeader(builder, 4, mainBuilder.length, false);
    builder.add(mainBuilder.takeBytes());
  }
}
