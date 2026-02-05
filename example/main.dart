import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parser.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

final client = webdav.newClient(
  "https://xxx.xxx.xx/dav",
  user: 'xxx',
  password: 'xxxxxx',
);

void main() async {
  File file = File('/Users/lyp/Music/LZF-Music/After Hours - The Weeknd.flac');
  Uint8List data = await file.readAsBytes();
  print(data.length);
  final metadata = await readMetadataUint8List(Stream.value(data), getImage: true);
  print(metadata);
}
