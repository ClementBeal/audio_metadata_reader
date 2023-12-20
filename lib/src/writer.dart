import 'dart:io';

import 'package:audio_metadata_reader/src/metadata/mp4_metadata.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/mp4.dart';
import 'package:audio_metadata_reader/src/parsers/tag_parser.dart';
import 'package:audio_metadata_reader/src/parsers/flac.dart';
import 'package:audio_metadata_reader/src/writers/flac_writer.dart';
import 'package:audio_metadata_reader/src/writers/mp4_writer.dart';

Future<void> writeMetadata(File track, AudioMetadata metadata) async {
  final reader = await track.open();

  try {
    // if (await ID3v2Parser.canUserParser(reader)) {
    //   final mp3Metadata =
    //       await ID3v2Parser(fetchImage: getImage).parse(reader) as Mp3Metadata;

    //   final a = AudioMetadata(
    //     album: mp3Metadata.album,
    //     artist: mp3Metadata.bandOrOrchestra ??
    //         mp3Metadata.originalArtist ??
    //         mp3Metadata.leadPerformer,
    //     bitrate: mp3Metadata.bitrate,
    //     duration: mp3Metadata.duration,
    //     language: mp3Metadata.languages,
    //     lyrics: mp3Metadata.lyric,
    //     sampleRate: mp3Metadata.samplerate,
    //     title: mp3Metadata.songName,
    //     totalDisc: 0,
    //     trackNumber: mp3Metadata.trackNumber,
    //     trackTotal: mp3Metadata.trackTotal,
    //     year:
    //         DateTime(mp3Metadata.originalReleaseYear ?? mp3Metadata.year ?? 0),
    //     discNumber: mp3Metadata.discNumber,
    //   );

    //   a.pictures = mp3Metadata.pictures;
    //   a.genres = mp3Metadata.genres;
    //   // if (mp3Metadata.contentType != null) {
    //   //   print(mp3Metadata.contentType);
    //   //   // a.genres.add(mp3Metadata.contentType!);
    //   // }

    //   return a;
    // } else
    if (await FlacParser.canUserParser(reader)) {
      final newMetadata = VorbisMetadata();
      if (metadata.title != null) newMetadata.title.add(metadata.title!);
      if (metadata.album != null) newMetadata.album.add(metadata.album!);
      if (metadata.artist != null) newMetadata.artist.add(metadata.artist!);
      if (metadata.discNumber != null) {
        newMetadata.discNumber = metadata.discNumber!;
      }
      if (metadata.duration != null) newMetadata.duration = metadata.duration;
      if (metadata.genres.isNotEmpty) {
        newMetadata.genres.addAll(metadata.genres);
      }
      if (metadata.pictures.isNotEmpty) {
        newMetadata.pictures.addAll(metadata.pictures);
      }
      if (metadata.year != null) newMetadata.date.add(metadata.year!);

      await FlacWriter().write(track, newMetadata);
    } else if (await MP4Parser.canUserParser(reader)) {
      await Mp4Writer().write(
          reader,
          Mp4Metadata(
            title: metadata.title,
            album: metadata.album,
            artist: metadata.artist,
            bitrate: metadata.bitrate,
            discNumber: metadata.discNumber,
            duration: metadata.duration,
            picture: metadata.pictures.firstOrNull,
            trackNumber: metadata.trackNumber,
            year: metadata.year,
          ));
    }
  } catch (e) {}
}
