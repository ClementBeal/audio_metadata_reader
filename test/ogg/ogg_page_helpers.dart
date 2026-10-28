import 'dart:io';
import 'dart:typed_data';

/// One page of an Ogg file, as read by [readOggPages].
class OggTestPage {
  final int offset;
  final int headerType;

  /// Granule position as stored (-1 when no packet ends on the page).
  final int granule;
  final int serial;
  final Uint8List segmentSizes;
  final Uint8List body;

  OggTestPage(this.offset, this.headerType, this.granule, this.serial,
      this.segmentSizes, this.body);

  int get end => offset + 27 + segmentSizes.length + body.length;
}

/// Reads the complete pages of [bytes], stopping at the first page that is
/// cut or at data that is not an Ogg page.
List<OggTestPage> readOggPages(Uint8List bytes) {
  final List<OggTestPage> pages = <OggTestPage>[];
  final ByteData data = ByteData.sublistView(bytes);
  int offset = 0;

  while (offset + 27 <= bytes.length &&
      String.fromCharCodes(bytes, offset, offset + 4) == 'OggS') {
    final int segmentCount = bytes[offset + 26];
    if (offset + 27 + segmentCount > bytes.length) {
      break;
    }
    final Uint8List segments = Uint8List.fromList(
        bytes.sublist(offset + 27, offset + 27 + segmentCount));
    final int bodySize = segments.fold(0, (int sum, int size) => sum + size);
    final int bodyStart = offset + 27 + segmentCount;
    if (bodyStart + bodySize > bytes.length) {
      break;
    }
    final OggTestPage page = OggTestPage(
      offset,
      bytes[offset + 5],
      data.getInt64(offset + 6, Endian.little),
      data.getUint32(offset + 14, Endian.little),
      segments,
      Uint8List.fromList(bytes.sublist(bodyStart, bodyStart + bodySize)),
    );
    pages.add(page);
    offset = page.end;
  }

  return pages;
}

/// Builds one Ogg page with a valid checksum.
Uint8List buildOggPage({
  required int headerType,
  required int granule,
  required int serial,
  required int sequence,
  required List<int> segmentSizes,
  required List<int> body,
}) {
  final BytesBuilder builder = BytesBuilder();
  final ByteData header = ByteData(27);
  header.setUint32(0, 0x4F676753); // OggS
  header.setUint8(4, 0);
  header.setUint8(5, headerType);
  header.setInt64(6, granule, Endian.little);
  header.setUint32(14, serial, Endian.little);
  header.setUint32(18, sequence, Endian.little);
  header.setUint8(26, segmentSizes.length);
  builder
    ..add(header.buffer.asUint8List())
    ..add(segmentSizes)
    ..add(body);

  final Uint8List page = builder.takeBytes();
  ByteData.sublistView(page).setUint32(22, _oggCrc(page), Endian.little);
  return page;
}

/// Laces one [packet] over as many pages as it needs, granule 0 on each.
List<Uint8List> buildPacketPages({
  required Uint8List packet,
  required int serial,
  required int firstSequence,
}) {
  final List<int> lacing = <int>[
    for (int i = 0; i < packet.length ~/ 255; i++) 255,
    packet.length % 255,
  ];

  final List<Uint8List> pages = <Uint8List>[];
  int lace = 0;
  int bodyOffset = 0;
  while (lace < lacing.length) {
    final List<int> segments = lacing.sublist(
        lace, lace + 255 < lacing.length ? lace + 255 : lacing.length);
    final int bodySize = segments.fold(0, (int sum, int size) => sum + size);
    pages.add(buildOggPage(
      headerType: lace == 0 ? 0 : 0x01,
      granule: lace + segments.length < lacing.length ? -1 : 0,
      serial: serial,
      sequence: firstSequence + pages.length,
      segmentSizes: segments,
      body: packet.sublist(bodyOffset, bodyOffset + bodySize),
    ));
    lace += segments.length;
    bodyOffset += bodySize;
  }
  return pages;
}

/// Rewrites [page] with a new sequence number (and a valid checksum).
Uint8List renumberOggPage(OggTestPage page, int sequence) => buildOggPage(
      headerType: page.headerType,
      granule: page.granule,
      serial: page.serial,
      sequence: sequence,
      segmentSizes: page.segmentSizes,
      body: page.body,
    );

/// Writes [bytes] to a new temporary file named [name].
File writeTemporaryOgg(String name, List<int> bytes) {
  final Directory directory = Directory.systemTemp.createTempSync('ogg_test');
  _temporaryDirectories.add(directory);
  return File('${directory.path}/$name')..writeAsBytesSync(bytes);
}

final List<Directory> _temporaryDirectories = <Directory>[];

/// Deletes the files written by [writeTemporaryOgg].
void deleteTemporaryOggFiles() {
  for (final Directory directory in _temporaryDirectories) {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
  _temporaryDirectories.clear();
}

final List<int> _crcTable = List<int>.generate(256, (int index) {
  int r = index << 24;
  for (int i = 0; i < 8; i++) {
    r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04C11DB7) : (r << 1);
    r &= 0xFFFFFFFF;
  }
  return r;
});

int _oggCrc(Uint8List page) {
  int crc = 0;
  for (int i = 0; i < page.length; i++) {
    final int byte = (i >= 22 && i < 26) ? 0 : page[i];
    crc = ((crc << 8) & 0xFFFFFFFF) ^ _crcTable[((crc >> 24) & 0xFF) ^ byte];
  }
  return crc;
}
