import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/vorbis_comment.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';

// The parser for an OGG file
//
// The metadata are using the Vorbis format (like flac)
//
// OGG : https://datatracker.ietf.org/doc/pdf/rfc7845.pdf
// vorbis : http://web.mit.edu/cfox/share/doc/libvorbis-1.0/vorbis-spec-ref.html
class OGGParser extends TagParser {
  OGGParser({required super.fetchImage});

  @override
  Future<ParserTag> parse(RandomAccessFile reader) async {
    reader.setPositionSync(28);

    var m = VorbisMetadata();

    // we look for the `OpusTags` header

    List<int> header = [...reader.readSync(1024)];

    var offset = 0;
    var isFound = false;
    var isVorbis = false;

    while (!isFound) {
      if (String.fromCharCodes(header.sublist(offset, offset + 8)) ==
          "OpusTags") {
        isFound = true;
        offset += 28 + 8;
        break;
      }

      if (String.fromCharCodes(header.sublist(offset, offset + 6)) ==
          "vorbis") {
        isVorbis = true;
        offset += 28 + 6;

        break;
      }

      offset++;
    }

    reader.setPositionSync(offset);

    if (isVorbis) {
      reader.readSync(4); // vorbis version
      reader.readSync(1); // audio channels
      m.sampleRate = getUint32LE(reader.readSync(4));
      reader.readSync(4); // bitrate max
      m.bitrate = getUint32LE(reader.readSync(4));
      reader.readSync(6);

      reader.readSync(28); // pass the secong OggS header

      final List<int> buffer = [...reader.readSync(6)];
      while (String.fromCharCodes(buffer) != "vorbis") {
        buffer.removeAt(0);
        buffer.add(reader.readByteSync());
      }
    }

    final vendorLength = getUint32LE(reader.readSync(4));
    reader.readSync(vendorLength);
    final userCommentListLength = getUint32LE(reader.readSync(4));

    for (var i = 0; i < userCommentListLength; i++) {
      final commentLength = getUint32LE(reader.readSync(4));
      final comment = reader.readSync(commentLength);
      m = parseVorbisComment(comment, m);
    }

    if ((m.duration == null || m.duration == Duration.zero) &&
        isVorbis &&
        m.bitrate != null) {
      final contentSize = 8 * (reader.lengthSync() - reader.positionSync());
      m.duration = Duration(seconds: contentSize ~/ m.bitrate!);
    }

    return m;
  }

  static Future<bool> canUserParser(RandomAccessFile reader) async {
    reader.setPositionSync(0);

    final capturePatternBytes = reader.readSync(4);
    final capturePattern = String.fromCharCodes(capturePatternBytes);

    return capturePattern == "OggS";
  }
}
