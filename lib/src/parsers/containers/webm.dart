import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:audio_metadata_reader/src/utils/metadata_parser_exception.dart';

/// Parser for WebM and Matroska containers.
///
/// WebM is a Matroska profile. Both formats use EBML, a hierarchy of
/// length-prefixed elements rather than fixed-size boxes. This parser reads
/// the metadata-bearing elements and skips clusters and codec packets.
///
/// Protocol section: EBML element header
/// Layout (big-endian, variable width):
/// ```text
/// ID:   0xxxxxxx [0...][0...][0...]
/// SIZE: 1xxxxxxx [optional bytes...]
/// ```
/// Meaning:
/// - The first `1` bit identifies the width of the variable integer. The
///   first set bit is the width marker and is not part of a size value.
/// - Element IDs keep the marker bit; size values remove it.
/// - Size values are unsigned big-endian integers. All value bits set to one
///   means an unknown size, which is bounded by the containing element here.
/// Constraints:
/// - IDs are at most four bytes; sizes are at most eight bytes.
/// - Every finite child size must stay inside its parent element.
/// - A malformed header or out-of-bounds child is rejected deterministically.
///
/// Relevant WebM/Matroska elements:
/// ```text
/// EBML (1A45DFA3)
/// Segment (18538067)
/// ├─ Info (1549A966)
/// │  ├─ TimecodeScale (2AD7B1), uint nanoseconds
/// │  └─ Duration (4489), float timecode units
/// ├─ Tracks (1654AE6B)
/// │  └─ TrackEntry (AE) → TrackType (83), Audio (E1), CodecPrivate (63A2)
/// ├─ Tags (1254C367) → Tag (7373) → SimpleTag (67C8)
/// └─ Attachments (1941A469) → AttachedFile (61A7)
/// ```
///
/// `Duration * TimecodeScale` is nanoseconds. `SamplingFrequency` is a
/// big-endian IEEE-754 float. Text tags are UTF-8. Image attachment payloads
/// are skipped when [fetchImage] is false, preventing cover allocations.
class WebmParser extends TagParser<VorbisMetadata> {
  static const int _ebml = 0x1A45DFA3;
  static const int _segment = 0x18538067;
  static const int _info = 0x1549A966;
  static const int _timecodeScale = 0x2AD7B1;
  static const int _duration = 0x4489;
  static const int _infoTitle = 0x7BA9;
  static const int _muxingApp = 0x4D80;
  static const int _writingApp = 0x5741;
  static const int _tracks = 0x1654AE6B;
  static const int _trackEntry = 0xAE;
  static const int _trackType = 0x83;
  static const int _codecId = 0x86;
  static const int _codecPrivate = 0x63A2;
  static const int _audio = 0xE1;
  static const int _samplingFrequency = 0xB5;
  static const int _outputSamplingFrequency = 0x78B5;
  static const int _channels = 0x9F;
  static const int _bitDepth = 0x6264;
  static const int _tags = 0x1254C367;
  static const int _tag = 0x7373;
  static const int _simpleTag = 0x67C8;
  static const int _tagName = 0x45A3;
  static const int _tagString = 0x4487;
  static const int _attachments = 0x1941A469;
  static const int _attachedFile = 0x61A7;
  static const int _fileMimeType = 0x4660;
  static const int _fileData = 0x465C;

  /// Parsed metadata returned to the caller.
  VorbisMetadata tags = VorbisMetadata();

  late Buffer _buffer;
  late int _fileLength;
  _AudioTrack? _audioTrack;
  int _timecodeScaleValue = 1000000;
  double? _durationTimecode;

  /// Create a WebM/Matroska parser.
  WebmParser({bool fetchImage = false}) : super(fetchImage: fetchImage);

  @override
  VorbisMetadata parse(RandomAccessFile reader) {
    reader.setPositionSync(0);
    _buffer = Buffer(randomAccessFile: reader);
    _fileLength = reader.lengthSync();
    tags = VorbisMetadata();
    _audioTrack = null;
    _timecodeScaleValue = 1000000;
    _durationTimecode = null;

    final ebml = _readElementHeader(_fileLength);
    if (ebml.id != _ebml) {
      throw _malformed('Missing EBML header');
    }
    _skipTo(ebml.end);

    if (_buffer.fileCursor >= _fileLength) {
      throw _malformed('Missing Matroska Segment');
    }

    final segment = _readElementHeader(_fileLength);
    if (segment.id != _segment) {
      throw _malformed('Missing Matroska Segment');
    }
    _parseSegment(segment.end);

    _applyTrackMetadata();
    _applyDuration();

    return tags;
  }

  /// Detects EBML by content, not by filename extension. This is intentional:
  /// some of the user's `.mp4` files are actually WebM files renamed by a
  /// media manager.
  static bool canUserParser(RandomAccessFile reader) {
    if (reader.lengthSync() < 4) {
      return false;
    }

    reader.setPositionSync(0);
    final bytes = reader.readSync(4);
    return _readBigEndian(bytes) == _ebml;
  }

  void _parseSegment(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _info:
          _parseInfo(element.end);
        case _tracks:
          _parseTracks(element.end);
        case _tags:
          _parseTags(element.end);
        case _attachments:
          _parseAttachments(element.end);
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  void _parseInfo(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _timecodeScale:
          _timecodeScaleValue = _readUnsigned(element.end);
        case _duration:
          _durationTimecode = _readFloat(element.end);
        case _infoTitle:
          tags.title.add(_readText(element.end));
        case _muxingApp || _writingApp:
          tags.encoder.add(_readText(element.end));
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  void _parseTracks(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      if (element.id == _trackEntry) {
        final track = _parseTrackEntry(element.end);
        if (track.type == 2 && _audioTrack == null) {
          _audioTrack = track;
        }
      } else {
        _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  _AudioTrack _parseTrackEntry(int end) {
    var type = 0;
    String? codecId;
    Uint8List? codecPrivate;
    double? samplingFrequency;
    double? outputSamplingFrequency;

    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _trackType:
          type = _readUnsigned(element.end);
        case _codecId:
          codecId = _readText(element.end);
        case _codecPrivate:
          codecPrivate = _buffer.read(element.length);
        case _audio:
          final audio = _parseAudio(element.end);
          samplingFrequency = audio.samplingFrequency;
          outputSamplingFrequency = audio.outputSamplingFrequency;
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }

    return _AudioTrack(
      type: type,
      codecId: codecId,
      codecPrivate: codecPrivate,
      samplingFrequency: samplingFrequency,
      outputSamplingFrequency: outputSamplingFrequency,
    );
  }

  _AudioSettings _parseAudio(int end) {
    double? samplingFrequency;
    double? outputSamplingFrequency;

    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _samplingFrequency:
          samplingFrequency = _readFloat(element.end);
        case _outputSamplingFrequency:
          outputSamplingFrequency = _readFloat(element.end);
        case _channels || _bitDepth:
          _skipTo(element.end);
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }

    return _AudioSettings(
      samplingFrequency: samplingFrequency,
      outputSamplingFrequency: outputSamplingFrequency,
    );
  }

  void _parseTags(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      if (element.id == _tag) {
        _parseTag(element.end);
      } else {
        _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  void _parseTag(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      if (element.id == _simpleTag) {
        _parseSimpleTag(element.end);
      } else {
        _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  void _parseSimpleTag(int end) {
    String? name;
    String? value;

    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _tagName:
          name = _readText(element.end);
        case _tagString:
          value = _readText(element.end);
        case _simpleTag:
          // Nested SimpleTag values are independent entries. Parse them now;
          // the current tag is emitted after its own name/value are complete.
          _parseSimpleTag(element.end);
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }

    final tagName = name;
    final tagValue = value;
    if (tagName != null && tagValue != null && tagName.isNotEmpty) {
      final normalizedName = _normalizeTagName(tagName);
      if (normalizedName != null && tagValue.isNotEmpty) {
        parseVorbisComment(
          utf8.encode('$normalizedName=$tagValue'),
          tags,
          fetchImage: fetchImage,
        );
        _applyCompoundNumber(normalizedName, tagValue);
      }
    }
  }

  void _applyCompoundNumber(String name, String value) {
    final parts = value.split('/');
    if (parts.length != 2) {
      return;
    }

    final total = int.tryParse(parts.last);
    if (total == null) {
      return;
    }

    switch (name) {
      case 'TRACKNUMBER':
        tags.trackTotal = total;
      case 'DISCNUMBER':
        tags.discTotal = total;
    }
  }

  void _parseAttachments(int end) {
    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      if (element.id == _attachedFile) {
        _parseAttachedFile(element.end);
      } else {
        _skipTo(element.end);
      }
      _finishElement(element.end);
    }
  }

  void _parseAttachedFile(int end) {
    String? mimeType;
    Uint8List? data;

    while (_buffer.fileCursor < end) {
      final element = _readElementHeader(end);
      switch (element.id) {
        case _fileMimeType:
          mimeType = _readText(element.end);
        case _fileData:
          if (fetchImage) {
            data = _buffer.read(element.length);
          } else {
            // Cover bytes are the potentially large part of an attachment.
            // Skip them without allocating a Uint8List.
            _skipTo(element.end);
          }
        default:
          _skipTo(element.end);
      }
      _finishElement(element.end);
    }

    final imageData = data;
    final imageMimeType = mimeType;
    if (fetchImage &&
        imageData != null &&
        imageMimeType != null &&
        imageMimeType.startsWith('image/')) {
      tags.pictures
          .add(Picture(imageData, imageMimeType, PictureType.coverFront));
    }
  }

  void _applyTrackMetadata() {
    final track = _audioTrack;
    if (track == null) {
      return;
    }

    double? sampleRate =
        track.samplingFrequency ?? track.outputSamplingFrequency;
    final opusSampleRate = _readOpusSampleRate(track.codecPrivate);
    if (sampleRate == null && opusSampleRate != null) {
      sampleRate = opusSampleRate.toDouble();
    }
    if (sampleRate != null && sampleRate > 0) {
      tags.sampleRate = sampleRate.round();
    }

    // Matroska's TrackEntry does not carry a universal bitrate field. The
    // average container bitrate is a useful fallback when duration is known.
    // It includes container/tag overhead and is therefore not a codec bitrate.
    if (track.codecId != null && tags.sampleRate == null) {
      tags.unknowns['CODEC_ID'] = track.codecId!;
    }
  }

  void _applyDuration() {
    final durationTimecode = _durationTimecode;
    if (durationTimecode == null ||
        !durationTimecode.isFinite ||
        durationTimecode < 0 ||
        _timecodeScaleValue <= 0) {
      return;
    }

    final durationMicros = durationTimecode *
        _timecodeScaleValue /
        Duration.microsecondsPerMillisecond;
    tags.duration = Duration(microseconds: durationMicros.round());

    if (tags.duration!.inMicroseconds > 0 && _fileLength > 0) {
      final seconds =
          tags.duration!.inMicroseconds / Duration.microsecondsPerSecond;
      tags.bitrate = ((_fileLength * 8) / seconds).round();
    }
  }

  int? _readOpusSampleRate(Uint8List? codecPrivate) {
    if (codecPrivate == null || codecPrivate.length < 16) {
      return null;
    }
    if (String.fromCharCodes(codecPrivate.sublist(0, 8)) != 'OpusHead') {
      return null;
    }
    return ByteData.sublistView(codecPrivate).getUint32(12, Endian.little);
  }

  _EbmlElement _readElementHeader(int parentEnd) {
    final id = _readVint(isId: true);
    final size = _readVint(isId: false);
    final payloadStart = _buffer.fileCursor;
    final end = size.unknown ? parentEnd : payloadStart + size.value;

    if (end < payloadStart || end > parentEnd) {
      throw _malformed('Element exceeds its parent boundary');
    }

    return _EbmlElement(
      id: id.value,
      length: size.unknown ? parentEnd - payloadStart : size.value,
      end: end,
    );
  }

  _Vint _readVint({required bool isId}) {
    final first = _buffer.read(1)[0];
    var marker = 0x80;
    var width = 1;
    while (width <= 8 && first & marker == 0) {
      marker >>= 1;
      width++;
    }

    if (width > 8 || (isId && width > 4)) {
      throw _malformed('Invalid EBML variable integer');
    }

    var value = isId ? first : first & (marker - 1);
    if (width > 1) {
      final remaining = _buffer.read(width - 1);
      for (final byte in remaining) {
        value = (value << 8) | byte;
      }
    }

    final unknownValue = !isId && value == (1 << (7 * width)) - 1;
    return _Vint(value: value, width: width, unknown: unknownValue);
  }

  int _readUnsigned(int end) {
    final length = end - _buffer.fileCursor;
    if (length < 1 || length > 8) {
      throw _malformed('Invalid unsigned integer length: $length');
    }
    return _readBigEndian(_buffer.read(length));
  }

  double _readFloat(int end) {
    final length = end - _buffer.fileCursor;
    final bytes = _buffer.read(length);
    final data = ByteData.sublistView(bytes);
    return switch (length) {
      4 => data.getFloat32(0, Endian.big),
      8 => data.getFloat64(0, Endian.big),
      _ => throw _malformed('Invalid floating-point length: $length'),
    };
  }

  String _readText(int end) =>
      utf8.decode(_buffer.read(end - _buffer.fileCursor), allowMalformed: true);

  void _finishElement(int end) {
    if (_buffer.fileCursor > end) {
      throw _malformed('Parser read beyond element boundary');
    }
    _skipTo(end);
  }

  void _skipTo(int end) {
    if (end < _buffer.fileCursor) {
      throw _malformed('Invalid backwards element boundary');
    }
    if (end > _buffer.fileCursor) {
      _buffer.skip(end - _buffer.fileCursor);
    }
  }

  String? _normalizeTagName(String name) => switch (name.toUpperCase()) {
        'TRACK' || 'TRACKNUMBER' || 'PART_NUMBER' => 'TRACKNUMBER',
        'TOTAL_TRACKS' || 'TRACKTOTAL' => 'TRACKTOTAL',
        'DISC' || 'DISCNUMBER' => 'DISCNUMBER',
        'TOTAL_DISCS' || 'DISCTOTAL' => 'DISCTOTAL',
        'ALBUM_ARTIST' => 'ALBUMARTIST',
        'DATE_RELEASED' || 'RELEASE_DATE' => 'DATE',
        _ => name,
      };

  MetadataParserException _malformed(String message) => MetadataParserException(
      track: File(''), message: 'Malformed WebM: $message');

  static int _readBigEndian(List<int> bytes) {
    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
    }
    return value;
  }
}

class _Vint {
  const _Vint(
      {required this.value, required this.width, required this.unknown});

  final int value;
  final int width;
  final bool unknown;
}

class _EbmlElement {
  const _EbmlElement(
      {required this.id, required this.length, required this.end});

  final int id;
  final int length;
  final int end;
}

class _AudioTrack {
  const _AudioTrack({
    required this.type,
    required this.codecId,
    required this.codecPrivate,
    required this.samplingFrequency,
    required this.outputSamplingFrequency,
  });

  final int type;
  final String? codecId;
  final Uint8List? codecPrivate;
  final double? samplingFrequency;
  final double? outputSamplingFrequency;
}

class _AudioSettings {
  const _AudioSettings({
    required this.samplingFrequency,
    required this.outputSamplingFrequency,
  });

  final double? samplingFrequency;
  final double? outputSamplingFrequency;
}
