import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:audio_metadata_reader/src/metadata/mp4_metadata.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/mp4.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/flac.dart';

Future<AudioMetadata> readMetadata(File track, {bool getImage = false}) async {
  final reader = await track.open();

  try {
    if (await ID3v2Parser.canUserParser(reader)) {
      final mp3Metadata =
          await ID3v2Parser(fetchImage: getImage).parse(reader) as Mp3Metadata;

      final a = AudioMetadata(
        album: mp3Metadata.album,
        artist: mp3Metadata.bandOrOrchestra ??
            mp3Metadata.originalArtist ??
            mp3Metadata.leadPerformer,
        bitrate: mp3Metadata.bitrate,
        duration: mp3Metadata.duration,
        language: mp3Metadata.languages,
        lyrics: mp3Metadata.lyric,
        sampleRate: mp3Metadata.samplerate,
        title: mp3Metadata.songName,
        totalDisc: 0,
        trackNumber: mp3Metadata.trackNumber,
        trackTotal: mp3Metadata.trackTotal,
        year:
            DateTime(mp3Metadata.originalReleaseYear ?? mp3Metadata.year ?? 0),
        discNumber: mp3Metadata.discNumber,
      );

      a.pictures = mp3Metadata.pictures;
      a.genres = mp3Metadata.genres;
      // if (mp3Metadata.contentType != null) {
      //   print(mp3Metadata.contentType);
      //   // a.genres.add(mp3Metadata.contentType!);
      // }

      return a;
    } else if (await FlacParser.canUserParser(reader)) {
      final vorbisMetadata = await FlacParser(fetchImage: getImage)
          .parse(reader) as VorbisMetadata;
      final newMetadata = AudioMetadata(
        album: vorbisMetadata.album.firstOrNull,
        artist: vorbisMetadata.artist.firstOrNull,
        bitrate: vorbisMetadata.bitrate,
        discNumber: vorbisMetadata.discNumber,
        duration: vorbisMetadata.duration,
        language: vorbisMetadata.artist.firstOrNull,
        lyrics: vorbisMetadata.artist.firstOrNull,
        sampleRate: vorbisMetadata.sampleRate,
        title: vorbisMetadata.title.firstOrNull,
        totalDisc: vorbisMetadata.discTotal,
        trackNumber: vorbisMetadata.trackNumber.firstOrNull,
        trackTotal: vorbisMetadata.trackTotal,
        year: vorbisMetadata.date.firstOrNull,
      );
      newMetadata.genres = vorbisMetadata.genres;

      return newMetadata;
    } else if (await MP4Parser.canUserParser(reader)) {
      final mp4Metadata =
          await MP4Parser(fetchImage: getImage).parse(reader) as Mp4Metadata;

      final a = AudioMetadata(
        album: mp4Metadata.album,
        artist: mp4Metadata.artist,
        bitrate: mp4Metadata.bitrate,
        discNumber: mp4Metadata.discNumber,
        duration: mp4Metadata.duration,
        language: null,
        lyrics: null,
        sampleRate: null,
        title: mp4Metadata.title,
        totalDisc: null,
        trackNumber: mp4Metadata.trackNumber,
        trackTotal: null,
        year: mp4Metadata.year,
      );

      if (mp4Metadata.picture != null) {
        a.pictures.add(mp4Metadata.picture!);
      }

      return a;
    }
  } catch (e, t) {
    print(t);
    print(e);
    return InvalidTag();
  }

  return InvalidTag();
}
