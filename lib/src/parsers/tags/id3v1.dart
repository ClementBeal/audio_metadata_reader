import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';

class ID3v1Parser extends TagParser<Mp3Metadata> {
  final Mp3Metadata metadata = Mp3Metadata();

  ID3v1Parser({super.fetchImage = false});

  ///  Extract the part text between the [start] and the [end]
  ///  until we reach a "\x00" character
  String _extract(Uint8List tagData, int start, int end) {
    int i = start;

    while (i < end && tagData[i] != 0) {
      i++;
    }

    if (tagData[i] == 0) {
      return utf8.decode(tagData.sublist(start, i));
    }

    return latin1.decode(tagData.sublist(start, end));
  }

  @override
  Mp3Metadata parse(RandomAccessFile reader) {
    final tagData = reader.readSync(128);
    metadata.songName = _extract(tagData, 3, 33);
    metadata.leadPerformer = _extract(tagData, 33, 63);
    metadata.album = _extract(tagData, 63, 93);
    final yearAsString =
        latin1.decode(tagData.sublist(93, 97)).replaceAll('\x00', '').trim();
    metadata.year = int.tryParse(yearAsString);
    metadata.comments = [
      Comment("", _extract(tagData, 97, 127)),
    ];
    metadata.genres = [""];

    // metadata.genres =  [tagData[127]];

    return metadata;
  }
}
