import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/metadata/mp3_metadata.dart';
import 'package:audio_metadata_reader/src/metadata/mp4_metadata.dart';
import 'package:audio_metadata_reader/src/metadata/vorbis_metadata.dart';
import 'package:audio_metadata_reader/src/parsers/id3v2.dart';
import 'package:audio_metadata_reader/src/parsers/mp4.dart';
import 'package:audio_metadata_reader/src/parsers/ogg.dart';
import 'package:audio_metadata_reader/src/parsers/flac.dart';

/// Parse the metadata of a file.
///
/// It automatically detects the type of the file (`.mp3`, `.ogg`, `.flac` etc)
/// and select the matching file parser.
///
/// If there's no parser or an error, a `InvalidTag` instance should be returned.
///
/// By default, it does not fetch the images of the file. Because some
/// images/covers are sometimes huge (~5MB), it can drastically make the
/// parsing slower.
AudioMetadata readMetadata(File track, {bool getImage = false}) {
  final reader = track.openSync();

  try {
    if (ID3v2Parser.canUserParser(reader)) {
      final mp3Metadata =
          ID3v2Parser(fetchImage: getImage).parse(reader) as Mp3Metadata;

      final a = AudioMetadata(
        file: track,
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
        totalDisc: mp3Metadata.totalDics,
        trackNumber: mp3Metadata.trackNumber,
        trackTotal: mp3Metadata.trackTotal,
        year:
            DateTime(mp3Metadata.originalReleaseYear ?? mp3Metadata.year ?? 0),
        discNumber: mp3Metadata.discNumber,
      );

      a.pictures = mp3Metadata.pictures;
      a.genres = mp3Metadata.genres;

      return a;
    } else if (FlacParser.canUserParser(reader)) {
      final vorbisMetadata =
          FlacParser(fetchImage: getImage).parse(reader) as VorbisMetadata;

      final newMetadata = AudioMetadata(
        file: track,
        album: vorbisMetadata.album.firstOrNull,
        artist: vorbisMetadata.artist.firstOrNull,
        bitrate: vorbisMetadata.bitrate,
        discNumber: vorbisMetadata.discNumber,
        duration: vorbisMetadata.duration,
        language: vorbisMetadata.artist.firstOrNull,
        lyrics: vorbisMetadata.lyric,
        sampleRate: vorbisMetadata.sampleRate,
        title: vorbisMetadata.title.firstOrNull,
        totalDisc: vorbisMetadata.discTotal,
        trackNumber: vorbisMetadata.trackNumber.firstOrNull,
        trackTotal: vorbisMetadata.trackTotal,
        year: vorbisMetadata.date.firstOrNull,
      );

      newMetadata.genres = vorbisMetadata.genres;
      newMetadata.pictures = vorbisMetadata.pictures;

      return newMetadata;
    } else if (MP4Parser.canUserParser(reader)) {
      final mp4Metadata =
          MP4Parser(fetchImage: getImage).parse(reader) as Mp4Metadata;

      final a = AudioMetadata(
        file: track,
        album: mp4Metadata.album,
        artist: mp4Metadata.artist,
        bitrate: mp4Metadata.bitrate,
        discNumber: mp4Metadata.discNumber,
        duration: mp4Metadata.duration,
        language: null,
        lyrics: mp4Metadata.lyrics,
        sampleRate: mp4Metadata.sampleRate,
        title: mp4Metadata.title,
        totalDisc: mp4Metadata.totalDiscs,
        trackNumber: mp4Metadata.trackNumber,
        trackTotal: mp4Metadata.totalTracks,
        year: mp4Metadata.year,
      );

      if (mp4Metadata.picture != null) {
        a.pictures.add(mp4Metadata.picture!);
      }

      if (mp4Metadata.genre != null) {
        a.genres.add(mp4Metadata.genre!);
      }

      return a;
    } else if (OGGParser.canUserParser(reader)) {
      final oggMetadata =
          OGGParser(fetchImage: getImage).parse(reader) as VorbisMetadata;

      final newMetadata = AudioMetadata(
        file: track,
        album: oggMetadata.album.firstOrNull,
        artist: oggMetadata.artist.firstOrNull,
        bitrate: oggMetadata.bitrate,
        discNumber: oggMetadata.discNumber,
        duration: oggMetadata.duration,
        language: oggMetadata.artist.firstOrNull,
        lyrics: oggMetadata.lyric,
        sampleRate: oggMetadata.sampleRate,
        title: oggMetadata.title.firstOrNull,
        totalDisc: oggMetadata.discTotal,
        trackNumber: oggMetadata.trackNumber.firstOrNull,
        trackTotal: oggMetadata.trackTotal,
        year: oggMetadata.date.firstOrNull,
      );
      newMetadata.genres = oggMetadata.genres;
      newMetadata.pictures.addAll(oggMetadata.pictures);

      return newMetadata;
    }
    if (ID3v2Parser.isID3v1(reader)) {
      final mp3Metadata =
          ID3v2Parser(fetchImage: getImage).parse(reader) as Mp3Metadata;

      final a = AudioMetadata(
        file: track,
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
        totalDisc: mp3Metadata.totalDics,
        trackNumber: mp3Metadata.trackNumber,
        trackTotal: mp3Metadata.trackTotal,
        year:
            DateTime(mp3Metadata.originalReleaseYear ?? mp3Metadata.year ?? 0),
        discNumber: mp3Metadata.discNumber,
      );

      a.pictures = mp3Metadata.pictures;
      a.genres = mp3Metadata.genres;

      return a;
    }
  } catch (e, trace) {
    print(trace);
    throw MetadataParserException(track: track, message: e.toString());
  }

  throw MetadataParserException(
    track: track,
    message:
        "No available parser for this file. Please raise an issue in Github",
  );
}
