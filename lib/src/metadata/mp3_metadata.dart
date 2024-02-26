// https://teslabs.com/openplayer/docs/docs/specs/id3v2.3.0%20-%20ID3.org.pdf

import 'dart:typed_data';

import '../parsers/tag_parser.dart';

class Mp3Metadata extends ParserTag {
  String? album; // TALB
  String? bpm; // TBPM
  String? composer; // TCOM
  String? contentType; // TCON
  String? copyrightMessage; // TCOP
  String? date; // TDAT
  String? playlistDelay; // TDLY
  String? encodedBy; // TENC
  String? textWriter; // TEXT
  String? fileType; // TFLT
  String? time; // TIME
  String? contentGroupDescription; // TIT1
  String? songName; // TIT2
  String? subtitle; // TIT3
  String? initialKey; // TKEY
  String? languages; // TLAN
  Duration? duration; // TLEN
  String? mediatype; // TMED
  String? originalAlbum; // TOAL
  String? originalFilename; // TOFN
  String? originalTextWriter; // TOLY
  String? originalArtist; // TOPE
  int? originalReleaseYear; // TORY
  String? fileOwner; // TOWN
  String? leadPerformer; // TPE1
  String? bandOrOrchestra; // TPE2
  String? conductor; // TPE3
  String? interpreted; // TPE4
  String? partOfSet; // TPOS
  String? publisher; // TPUB
  int? trackNumber; // TRCK
  int? trackTotal; // custom: guessed with TRCK
  String? recordingDates; // TRDA
  String? internetRadioStationName; // TRSN
  String? internetRadioStationOwner; // TRSO
  String? size; // TSIZ
  String? isrc; // TSRC
  String? encoderSoftware; // TSSE
  int? year; // TYER
  String? uniqueFileIdentifer; // UFID
  String? termsOfUSe; // USER
  String? lyric; // USLT
  Map<String, String> customMetadata = {}; // TXXX
  List<Picture> pictures = []; // APIC
  AudioEncryption? audioEncryption; // AENC
  List<Comment> comments = []; // COMM
  CommercialFrame? commercialFrame; // COMR
// 4.26 ENCR [#sec4.26 Encryption method registration]
// 4.13 EQUA [#sec4.13 Equalization]
// 4.6 ETCO [#sec4.6 Event timing codes]
// 4.16 GEOB [#sec4.16 General encapsulated object]
// 4.27 GRID [#sec4.27 Group identification registration]
// 4.4 IPLS [#sec4.4 Involved people list]
// 4.21 LINK [#sec4.21 Linked information]
  String? musicCdId; // MCDI
// 4.7 MLLT [#sec4.7 MPEG location lookup table]
// 4.24 OWNE [#sec4.24 Ownership frame]
  PrivateFrame? privateFrame; // Private frame
  int? playCounter; // PCNT
  Popularimeter? popularimeter; // POPM
// 4.22 POSS [#sec4.22 Position synchronisation frame]
// 4.19 RBUF [#sec4.19 Recommended buffer size]
// 4.12 RVAD [#sec4.12 Relative volume adjustment]
// 4.14 RVRB [#sec4.14 Reverb]
// 4.10 SYLT [#sec4.10 Synchronized lyric/text]
// 4.8 SYTC [#sec4.8 Synchronized tempo codes]

  // bonus
  int? bitrate;
  int? samplerate;
  List<String> genres = [];
  int? discNumber;

  @override
  String toString() {
    return 'Mp3Metadata{'
        'album: $album, \n'
        'bpm: $bpm, \n'
        'composer: $composer, \n'
        'contentType: $contentType, \n'
        'copyrightMessage: $copyrightMessage, \n'
        'date: $date, \n'
        'playlistDelay: $playlistDelay, \n'
        'encodedBy: $encodedBy, \n'
        'textWriter: $textWriter, \n'
        'fileType: $fileType, \n'
        'time: $time, \n'
        'contentGroupDescription: $contentGroupDescription, \n'
        'songName: $songName, \n'
        'subtitle: $subtitle, \n'
        'initialKey: $initialKey, \n'
        'languages: $languages, \n'
        'duration: $duration, \n'
        'mediatype: $mediatype, \n'
        'originalAlbum: $originalAlbum, \n'
        'originalFilename: $originalFilename, \n'
        'originalTextWriter: $originalTextWriter, \n'
        'originalArtist: $originalArtist, \n'
        'originalReleaseYear: $originalReleaseYear, \n'
        'fileOwner: $fileOwner, \n'
        'leadPerformer: $leadPerformer, \n'
        'bandOrOrchestra: $bandOrOrchestra, \n'
        'conductor: $conductor, \n'
        'interpreted: $interpreted, \n'
        'partOfSet: $partOfSet, \n'
        'publisher: $publisher, \n'
        'trackNumber: $trackNumber, \n'
        'trackTotal: $trackTotal, \n'
        'recordingDates: $recordingDates, \n'
        'internetRadioStationName: $internetRadioStationName, \n'
        'internetRadioStationOwner: $internetRadioStationOwner, \n'
        'size: $size, \n'
        'isrc: $isrc, \n'
        'encoderSoftware: $encoderSoftware, \n'
        'year: $year, \n'
        'uniqueFileIdentifer: $uniqueFileIdentifer, \n'
        'termsOfUSe: $termsOfUSe, \n'
        'lyric: $lyric, \n'
        'customMetadata: $customMetadata, \n'
        'pictures: $pictures, \n'
        'audioEncryption: $audioEncryption, \n'
        'comments: $comments, \n'
        'commercialFrame: $commercialFrame, \n'
        'musicCdId: $musicCdId, \n'
        'privateFrame: $privateFrame, \n'
        'playCounter: $playCounter, \n'
        'popularimeter: $popularimeter\n}';
  }
}

class AudioEncryption {
  final String ownerId;
  final int previewStart;
  final int previewEnd;
  final Uint8List encryptionInfo;

  AudioEncryption(
      this.ownerId, this.previewStart, this.previewEnd, this.encryptionInfo);
}

class CommercialFrame {
  final String price; // terminated with $00
  final String validUntil;
  final String contactUrl; // terminated with $00
  final int receivedAs;
  final String sellerName; // terminated with $00
  final String description; // terminated with $00
  final String mimeType; // terminated with $00
  final Uint8List sellerLogo;

  CommercialFrame(this.price, this.validUntil, this.contactUrl, this.receivedAs,
      this.sellerName, this.description, this.mimeType, this.sellerLogo);
}

class Popularimeter {
  final String? email;
  final int rating;
  final int counter;

  Popularimeter(this.email, this.rating, this.counter);

  @override
  String toString() {
    return 'Popularimeter{'
        'email: $email, '
        'rating: $rating, '
        'counter: $counter}';
  }
}

class PrivateFrame {
  final String identifer;
  final Uint8List data;

  PrivateFrame(this.identifer, this.data);
}

class Comment {
  final String language;
  String? shortDescription;
  final String text;

  Comment(this.language, this.text);
}
