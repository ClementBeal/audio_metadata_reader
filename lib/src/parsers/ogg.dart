import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/vorbis_comment.dart';
import 'package:audio_metadata_reader/src/utils/bit_manipulator.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';

class OggPage {
  final Uint8List data;
  final int headerType;
  final int granulePosition;
  final int bitstreamSerialNumber;

  OggPage({
    required this.data,
    required this.headerType,
    required this.granulePosition,
    required this.bitstreamSerialNumber,
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

  late final Buffer buffer;

  @override
  ParserTag parse(RandomAccessFile reader) {
    reader.setPositionSync(0);

    buffer = Buffer(randomAccessFile: reader);

    // first page : contains samplerate and bitrate
    // second page : contains the metadata
    // it may not contains all the metadata so we would have to get them later
    final pages = [
      _parseUniquePage(),
      _parseUniquePage(),
    ];

    VorbisMetadata m = VorbisMetadata();

    for (final page in pages) {
      final content = page.data;

      if (String.fromCharCodes(content.sublist(0, 8)) == "OpusHead") {
        m.sampleRate = getUint32LE(content.sublist(12, 16));
        m.bitrate = getUint32LE(content.sublist(13, 17));
      } else if (String.fromCharCodes(content.sublist(0, 8)) == "OpusTags") {
        _parseVorbisComment(content, 8, m);
      } else if (String.fromCharCodes(content.sublist(0, 7)) ==
          String.fromCharCodes(
              [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])) // "\x03vorbis"
      {
        _parseVorbisComment(content, 7, m);
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
      OggPage? page;

      while (page?.headerType != 0x04) {
        page = _parseUniquePageHeader();
      }

      m.duration = Duration(
        seconds: (page!.granulePosition - pages.first.granulePosition) ~/
            m.sampleRate!,
      );
    }

    reader.closeSync();

    return m;
  }

  VorbisMetadata _parseVorbisComment(
    Uint8List page,
    int headerOffset,
    VorbisMetadata m,
  ) {
    final dataBuffer = List<int>.from(page.sublist(headerOffset));
    int offset = 0;

    final vendorLength = getUint32LE(dataBuffer.sublist(offset, offset + 4));
    offset += 4;
    offset += vendorLength;

    final userCommentListLength =
        getUint32LE(dataBuffer.sublist(offset, offset + 4));
    offset += 4;

    for (int i = 0; i < userCommentListLength; i++) {
      final commentLength = getUint32LE(dataBuffer.sublist(offset, offset + 4));
      offset += 4;

      while (dataBuffer.length - offset < commentLength) {
        dataBuffer.addAll(_parseUniquePage().data);
      }
      final commentData = dataBuffer.sublist(offset, offset + commentLength);
      offset += commentLength;
      parseVorbisComment(commentData, m, fetchImage);
    }

    return m;
  }

  /// Check if the OGG parser can be use for a specific file
  static bool canUserParser(RandomAccessFile reader) {
    reader.setPositionSync(0);

    final capturePatternBytes = reader.readSync(4);
    final capturePattern = String.fromCharCodes(capturePatternBytes);

    return capturePattern == "OggS";
  }

  /// Parse a unique OGG page
  /// It means from the OggS magic word to the last segment
  OggPage _parseUniquePage() {
    // for the spec, see: https://wiki.xiph.org/Ogg
    List<int> data = []; //  contains data from previous (continuing) pages

    Uint8List headerData;
    try {
      headerData = buffer.read(27);
    } catch (e) {
      // Handle end of file gracefully (return what we have or throw an error)
      if (data.isNotEmpty) {
        return OggPage(
          data: Uint8List.fromList(data),
          granulePosition: 0, // Or handle this differently
          headerType: 0x04, // Treat as end of stream
          bitstreamSerialNumber: -1,
        );
      } else {
        // EOF reached
        rethrow;
      }
    }

    final oggs = headerData.sublist(0, 4);
    final version = headerData[4];
    final headerType = headerData[5];
    final granulePosition = getUint64LE(headerData.sublist(6, 14));
    final bitstreamSerialNumber = getUint32LE(headerData.sublist(14, 18));

    if (String.fromCharCodes(oggs) != 'OggS' || version != 0) {
      throw Exception('Not a valid ogg file!');
    }

    // define the total of segments in this page
    final totalSegments = headerData[26];
    final segsizes = buffer.read(totalSegments);
    List<int> pageData = []; // Data for the current page

    for (final segsize in segsizes) {
      pageData.addAll(buffer.read(segsize));
    }

    // Concatenate data from continuing pages if necessary

    return OggPage(
      data: Uint8List.fromList(pageData),
      granulePosition: granulePosition,
      headerType: headerType,
      bitstreamSerialNumber: bitstreamSerialNumber,
    );
  }

  /// Parse the header of an OGG page
  /// We also skip the content of the page to be synchronized
  OggPage _parseUniquePageHeader() {
    Uint8List headerData;

    headerData = buffer.read(27);

    final headerType = headerData[5];
    final granulePosition = getUint64LE(headerData.sublist(6, 14));
    final bitstreamSerialNumber = getUint32LE(headerData.sublist(14, 18));

    final totalSegments = headerData[26];
    final segsizes = buffer.read(totalSegments);
    int total = 0;

    for (final segsize in segsizes) {
      total += segsize;
    }

    buffer.skip(total);

    return OggPage(
      data: Uint8List(0),
      headerType: headerType,
      granulePosition: granulePosition,
      bitstreamSerialNumber: bitstreamSerialNumber,
    );
  }
}
