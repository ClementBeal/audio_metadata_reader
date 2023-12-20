library audio_metadata_reader;

export "src/parsers/tag_parser.dart" show AudioMetadata, InvalidTag, Picture;
export 'src/metadata/base.dart' show PictureType;
export 'src/parser.dart' show readMetadata;
export 'src/writer.dart' show writeMetadata;
