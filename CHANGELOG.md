## 0.0.8

- Fix : MP4 day is parsed correctly
- Fix : The `Buffer` skip function is skipping correctly
- Some basic refactoring

## 0.0.7

### BREAKING CHANGE

- `readMetadata` is now synchronous. You may remove some `Future.wait()`
- `InvalidTag` class has beem removed and replace with a real exception `MetadataParserException`
- Remove the writers. They are not working

## Other

- Performance improvement : **70%** faster by using sync IO operations and a File Buffer to read files
- Support `ID3v1`

## 0.0.6

- Fix : the MP4 duration was not accurate (#9). Thanks to @PKiman

## 0.0.5

- A reference to the file is returned with the metadata

## 0.0.4

- Update docs : show what format can be read and written
- Add tests to the projects
- Fix : mp3 can retreive total discs
- Fix : mp4 can retreive lyrics/genre/samplerate/total tracks/total discs
- Fix : OGG and OPUS can retreive lyrics

## 0.0.3

- Remove dependencies to Flutter
- add support for OPUS and OGG

## 0.0.2

- FIX : read correcly a FLAC track. A mistake in the mask was missing the metadata
- FIX : compute correctly the duration of a MP3 track with Variable Bit Rate (VBR)

## 0.0.1

- Release of the first version
