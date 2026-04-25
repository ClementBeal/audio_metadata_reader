import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/parsers/tags/vorbis_comment.dart';
import 'package:test/test.dart';

void main() {
  test('Parse LANGUAGE Vorbis comment into dedicated field', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('LANGUAGE=ja'.codeUnits, metadata, false);

    expect(metadata.language, equals(['ja']));
    expect(metadata.unknowns.containsKey('LANGUAGE'), isFalse);
  });

  test('Parse LANG Vorbis comment alias into dedicated field', () {
    final metadata = VorbisMetadata();

    parseVorbisComment('LANG=zh-CN'.codeUnits, metadata, false);

    expect(metadata.language, equals(['zh-CN']));
    expect(metadata.unknowns.containsKey('LANG'), isFalse);
  });
}
