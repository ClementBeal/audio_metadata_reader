import 'dart:io';
import 'dart:typed_data';

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
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    // first page : useless
    final pages = [parsePages(reader), parsePages(reader)];

    var m = VorbisMetadata();

    for (var page in pages) {
      if (String.fromCharCodes(page.sublist(0, 8)) == "OpusHead") {
        m.sampleRate = getUint32LE(page.sublist(12, 16));
        m.bitrate = getUint32LE(page.sublist(13, 17));
      } else if (String.fromCharCodes(page.sublist(0, 8)) == "OpusTags") {
        m = _parseVorbicComment(page, 8, m);
      } else if (String.fromCharCodes(page.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x03vorbis"
      {
        m = _parseVorbicComment(page, 7, m);
      } else if (String.fromCharCodes(page.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x01vorbis"
      {
        m.sampleRate = getUint32LE(page.sublist(12, 16));
        m.bitrate = getUint32LE(page.sublist(20, 24));
      }
    }

    if ((m.duration == null || m.duration == Duration.zero) &&
        m.bitrate != null) {
      final contentSize = 8 * (reader.lengthSync() - reader.positionSync());
      m.duration = Duration(seconds: contentSize ~/ m.bitrate!);
    }

    return m;
  }

  VorbisMetadata _parseVorbicComment(
      Uint8List page, int headerOffset, VorbisMetadata m) {
    var offset = headerOffset;
    final buffer = ByteData.sublistView(page);
    final vendorLength = buffer.getUint32(offset, Endian.little);
    offset += 4;
    offset += vendorLength;

    final userCommentListLength = buffer.getUint32(offset, Endian.little);
    offset += 4;

    for (var i = 0; i < userCommentListLength; i++) {
      final commentLength = buffer.getUint32(offset, Endian.little);
      offset += 4;

      final comment = buffer.buffer.asUint8List(offset, commentLength);
      offset += commentLength;
      m = parseVorbisComment(comment, m);
    }

    return m;
  }

  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final capturePatternBytes = reader.readSync(4);
    final capturePattern = String.fromCharCodes(capturePatternBytes);

    return capturePattern == "OggS";
  }

  Uint8List parsePages(RandomAccessFile fh) {
    // # for the spec, see: https://wiki.xiph.org/Ogg
    var previousPage =
        <int>[]; //  # contains data from previous (continuing) pages
    var headerData = fh.readSync(27); //  # read ogg page header

    while (headerData.length == 27) {
      final oggs = headerData.sublist(0, 4);
      final version = headerData[4];

      if (String.fromCharCodes(oggs) != 'OggS' || version != 0) {
        throw Exception('Not a valid ogg file!');
      }

      // define the total of segments in this page
      final totalSegments = headerData[26];
      final segsizes = fh.readSync(totalSegments).toList();
      var total = 0;

      for (var segsize in segsizes) {
        total += segsize;

        // less than 255 bytes means end of page
        if (total < 255) {
          return fh.readSync(total);
        }
      }

      if (total > 0) {
        if (total % 255 == 0) {
          previousPage.addAll(fh.readSync(total));
        } else {
          previousPage.addAll(fh.readSync(total));
          return Uint8List.fromList(previousPage);
        }
      }

      headerData = fh.readSync(27);
    }

    return Uint8List(0);
  }
}
