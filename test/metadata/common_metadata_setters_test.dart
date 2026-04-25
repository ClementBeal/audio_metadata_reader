import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:test/test.dart';

void main() {
  test('setTrackTotal does not override trackNumber for RIFF', () {
    final metadata = RiffMetadata(trackNumber: 7);

    metadata.setTrackTotal(12);

    expect(metadata.trackNumber, equals(7));
  });

  test('setTrackTotal updates supported formats', () {
    final mp3 = Mp3Metadata();
    final mp4 = Mp4Metadata();
    final vorbis = VorbisMetadata();

    mp3.setTrackTotal(10);
    mp4.setTrackTotal(10);
    vorbis.setTrackTotal(10);

    expect(mp3.trackTotal, equals(10));
    expect(mp4.totalTracks, equals(10));
    expect(vorbis.trackTotal, equals(10));
  });
}
