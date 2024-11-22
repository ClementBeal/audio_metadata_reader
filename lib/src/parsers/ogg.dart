import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/vorbis_comment.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';

class OggPage {
  final Uint8List data;
  final int headerType;
  final int granulePosition;

  OggPage({
    required this.data,
    required this.headerType,
    required this.granulePosition,
  });
}

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

    VorbisMetadata m = VorbisMetadata();

    for (final page in pages) {
      final content = page.data;

      if (String.fromCharCodes(content.sublist(0, 8)) == "OpusHead") {
        m.sampleRate = getUint32LE(content.sublist(12, 16));
        m.bitrate = getUint32LE(content.sublist(13, 17));
      } else if (String.fromCharCodes(content.sublist(0, 8)) == "OpusTags") {
        m = _parseVorbicComment(content, 8, m);
      } else if (String.fromCharCodes(content.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x03vorbis"
      {
        m = _parseVorbicComment(content, 7, m);
      } else if (String.fromCharCodes(content.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x01, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x01vorbis"
      {
        m.sampleRate = getUint32LE(content.sublist(12, 16));
        m.bitrate = getUint32LE(content.sublist(20, 24));
      }
    }

    // we need the sample rate to calculate the duration
    // it's mandatory
    // we have X samples per second (the sample rate obvio)
    // and a page contains exactly X samples

    if ((m.duration == null || m.duration == Duration.zero) &&
        m.sampleRate != null) {
      OggPage page = parsePages(reader);
      OggPage previousPage = page;

      // 0x04 means it's the last page
      while (page.headerType != 0x04) {
        previousPage = page;
        page = parsePages(reader);
      }

      m.duration = Duration(
        seconds: (previousPage.granulePosition - pages.first.granulePosition) ~/
            m.sampleRate!,
      );
    }

    reader.closeSync();

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

  OggPage parsePages(RandomAccessFile reader) {
    // for the spec, see: https://wiki.xiph.org/Ogg
    List<int> previousPage =
        []; //  contains data from previous (continuing) pages

    while (true) {
      Uint8List headerData;
      try {
        headerData = reader.readSync(27);
      } catch (e) {
        // Handle end of file gracefully (return what we have or throw an error)
        if (previousPage.isNotEmpty) {
          return OggPage(
            data: Uint8List.fromList(previousPage),
            granulePosition: 0, // Or handle this differently
            headerType: 0x04, // Treat as end of stream
          );
        } else {
          // EOF reached
          rethrow;
        }
      }

      if (headerData.length < 27) {
        break;
      }

      final oggs = headerData.sublist(0, 4);
      final version = headerData[4];
      final headerType = headerData[5];
      final granulePosition = getUint64LE(headerData.sublist(6, 14));

      if (String.fromCharCodes(oggs) != 'OggS' || version != 0) {
        throw Exception('Not a valid ogg file!');
      }

      // define the total of segments in this page
      final totalSegments = headerData[26];
      final segsizes = reader.readSync(totalSegments);
      List<int> pageData = []; // Data for the current page

      for (final segsize in segsizes) {
        pageData.addAll(reader.readSync(segsize));
      }

      // Concatenate data from continuing pages if necessary
      if ((headerType & 0x04) != 0) {
        previousPage.addAll(pageData);
      } else {
        // If not a continuation page, combine with previous if any and return
        if (previousPage.isNotEmpty) {
          pageData = previousPage + pageData;
          previousPage = []; // Reset for next page
        }
        return OggPage(
          data: Uint8List.fromList(pageData),
          granulePosition: granulePosition,
          headerType: headerType,
        );
      }
    }

    return OggPage(
      data: Uint8List(0),
      granulePosition: -1,
      headerType: 0x04,
    );
  }
}
