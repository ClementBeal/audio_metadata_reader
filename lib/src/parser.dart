import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/riff.dart';
import 'package:audio_metadata_reader/src/metadata/base.dart';
import 'package:audio_metadata_reader/src/utils/buffer.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;


Future<AudioMetadata> readMetadataFile(File track, {bool getImage = false}) async {
  MyRandomAccessFile reader = FileRandomAccessFile(randomAccessFile: track.openSync());
  return readMetadata(reader, getImage: getImage);
}


Future<AudioMetadata> readMetadataWebDav(webdav.Client client, String path,
    {bool getImage = false}) async {
  final reader = WebDavRandomAccessFile(client: client, path: path);
  return readMetadata(reader, getImage: getImage);
}

Future<AudioMetadata> readMetadataUint8List(Uint8List data,{bool getImage = false}) async {
  final reader = Uint8ListRandomAccessFile(data: data);
  return readMetadata(reader, getImage: getImage);
}



Future<AudioMetadata> readMetadata(MyRandomAccessFile reader,
    {bool getImage = false}) async {
  try {
    if (await ID3v2Parser.canUserParser(reader)) {
      final mp3Metadata = (await ID3v2Parser(fetchImage: getImage)
          .parse(reader)) as Mp3Metadata;

      final a = AudioMetadata(
        file: File(''),
        album: mp3Metadata.album,
        artist: mp3Metadata.bandOrOrchestra ??
            mp3Metadata.leadPerformer ??
            mp3Metadata.originalArtist,
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

      final guestArtistFrame = mp3Metadata.customMetadata["GUEST ARTIST"];

      if (guestArtistFrame != null) {
        a.performers.addAll(guestArtistFrame.split("/"));
      }

      return a;
    } else if (await FlacParser.canUserParser(reader)) {
      final vorbisMetadata = (await FlacParser(fetchImage: getImage)
          .parse(reader)) as VorbisMetadata;

      final newMetadata = AudioMetadata(
        file: File(''),
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
      newMetadata.performers.addAll(vorbisMetadata.performer);

      return newMetadata;
    } else if (await MP4Parser.canUserParser(reader)) {
      final mp4Metadata =
          (await MP4Parser(fetchImage: getImage).parse(reader)) as Mp4Metadata;

      final newMetadata = AudioMetadata(
        file: File(''),
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
        newMetadata.pictures.add(mp4Metadata.picture!);
      }

      if (mp4Metadata.genre != null) {
        newMetadata.genres.add(mp4Metadata.genre!);
      }

      return newMetadata;
    } else if (await OGGParser.canUserParser(reader)) {
      final oggMetadata = (await OGGParser(fetchImage: getImage).parse(reader))
          as VorbisMetadata;

      final newMetadata = AudioMetadata(
        file: File(''),
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
      newMetadata.performers.addAll(oggMetadata.performer);

      return newMetadata;
    } else if (await RiffParser.canUserParser(reader)) {
      final riffMetadata = (await RiffParser().parse(reader)) as RiffMetadata;

      final newMetadata = AudioMetadata(
        file: File(''),
        album: riffMetadata.album,
        artist: riffMetadata.artist,
        bitrate: riffMetadata.bitrate,
        duration: riffMetadata.duration,
        language: null,
        lyrics: riffMetadata.comment,
        sampleRate: riffMetadata.samplerate,
        title: riffMetadata.title,
        totalDisc: null,
        trackNumber: riffMetadata.trackNumber,
        trackTotal: null,
        year: riffMetadata.year,
        discNumber: null,
      );

      newMetadata.pictures = riffMetadata.pictures;
      newMetadata.genres =
          (riffMetadata.genre != null) ? [riffMetadata.genre!] : [];

      return newMetadata;
    } else if (await ID3v1Parser.canUserParser(reader)) {
      final mp3Metadata = (await ID3v1Parser().parse(reader)) as Mp3Metadata;

      final newMetadata = AudioMetadata(
        file: File(''),
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

      newMetadata.pictures = mp3Metadata.pictures;
      newMetadata.genres = mp3Metadata.genres;

      return newMetadata;
    }
  } on MetadataParserException catch (e, s) {
    Error.throwWithStackTrace(
        MetadataParserException(track: reader, message: e.message), s);
  } catch (e, s) {
    Error.throwWithStackTrace(
        MetadataParserException(track: reader, message: e.toString()), s);
  }

  throw NoMetadataParserException(
    track: reader,
  );
}


Future<ParserTag> readAllMetadata(MyRandomAccessFile reader, {bool getImage = true}) async {
  try {
    if (await ID3v2Parser.canUserParser(reader)) {
      return ID3v2Parser(fetchImage: getImage).parse(reader);
    } else if (await FlacParser.canUserParser(reader)) {
      return FlacParser(fetchImage: getImage).parse(reader);
    } else if (await MP4Parser.canUserParser(reader)) {
      return MP4Parser(fetchImage: getImage).parse(reader);
    } else if (await OGGParser.canUserParser(reader)) {
      return OGGParser(fetchImage: getImage).parse(reader);
    } else if (await ID3v2Parser.isID3v1(reader)) {
      return ID3v1Parser().parse(reader);
    } else if (await RiffParser.canUserParser(reader)) {
      return RiffParser().parse(reader);
    }
  } catch (e, trace) {
    print(trace);
    throw MetadataParserException(track: reader, message: e.toString());
  }

  throw MetadataParserException(
    track: reader,
    message:
        "No available parser for this file. Please raise an issue in Github",
  );
}
