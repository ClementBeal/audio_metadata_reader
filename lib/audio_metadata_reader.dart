library audio_metadata_reader;

export "src/parsers/tag_parser.dart" show AudioMetadata, Picture;
export 'src/metadata/base.dart' show PictureType;
export 'src/utils/metadata_parser_exception.dart' show MetadataParserException;
export 'src/parser.dart' show readMetadata, readAllMetadata;
