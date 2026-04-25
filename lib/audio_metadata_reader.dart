library audio_metadata_reader;

export "src/parsers/tags/tag_parser.dart" show AudioMetadata, Picture;
export 'src/metadata/base.dart' show PictureType;
export 'src/constants/constant.dart' show supportedFileExtensions;
export 'src/utils/metadata_parser_exception.dart'
    show MetadataParserException, NoMetadataParserException;
export 'src/parser.dart' show readMetadata, readAllMetadata;
export 'src/writer.dart' show updateMetadata, writeMetadata;

export 'src/parsers/containers/mp3.dart' show MP3Parser;
export 'src/parsers/tags/id3v1.dart' show ID3v1Parser;
export 'src/parsers/tags/id3v2.dart' show ID3v2Parser;
export 'src/parsers/containers/flac.dart' show FlacParser;
export 'src/parsers/containers/mp4.dart' show MP4Parser;
export 'src/parsers/containers/ogg.dart' show OGGParser;

export 'src/writers/id3v4_writer.dart' show Id3v4Writer;
export 'src/writers/flac_writer.dart' show FlacWriter;
export 'src/writers/id3v1_writer.dart' show ID3v1Writer;
export 'src/writers/mp4_writer.dart' show Mp4Writer;
export 'src/writers/riff_writer.dart' show RiffWriter;

export 'src/metadata/base.dart'
    show
        Chapter,
        Mp3Metadata,
        Mp4Metadata,
        RiffMetadata,
        VorbisMetadata,
        CommonMetadataSetters;
