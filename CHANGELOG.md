## [1.4.3](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.4.2...v1.4.3) (2025-07-19)

### Features

* add APEv2 parser 

## [1.4.2](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.4.1...v1.4.2) (2025-06-28)

### Chore

* Bump `intl` and `test` ([#70](https://github.com/ClementBeal/audio_metadata_reader/issues/80)) ([8923c67](https://github.com/ClementBeal/audio_metadata_reader/commit/89c277127449455489e6a53c99a103a098619196))

### Bug Fixes

* MP4 should be able to skip the images ([#75](https://github.com/ClementBeal/audio_metadata_reader/issues/75)) ([8923c67](https://github.com/ClementBeal/audio_metadata_reader/commit/8923c67342038d0408dad359a1461df50f2386f4))

## [1.4.1](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.4.0...v1.4.1) (2025-04-29)

### Bug Fixes

* MP4 should be able to skip the images ([#75](https://github.com/ClementBeal/audio_metadata_reader/issues/75)) ([8923c67](https://github.com/ClementBeal/audio_metadata_reader/commit/8923c67342038d0408dad359a1461df50f2386f4))

## [1.4.0](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.3.1...v1.4.0) (2025-04-20)

### Features

* add toString method to all metadata classes ([#71](https://github.com/ClementBeal/audio_metadata_reader/issues/71)) ([6d9a9e8](https://github.com/ClementBeal/audio_metadata_reader/commit/6d9a9e8792fcd9a8a51598975e589da33468947f))

### Bug Fixes

* **MP4:** use the mdhv version for the duration calculation ([#73](https://github.com/ClementBeal/audio_metadata_reader/issues/73)) ([d78ae23](https://github.com/ClementBeal/audio_metadata_reader/commit/d78ae233e621d8c2d833054e24d9dccaeadec8fd))
* write CD and genres for MP3 ([#70](https://github.com/ClementBeal/audio_metadata_reader/issues/70)) ([1d7c01c](https://github.com/ClementBeal/audio_metadata_reader/commit/1d7c01c47904a68d1330bde7848810713983de05))

## [1.3.1](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.3.0...v1.3.1) (2025-04-20)

### Bug Fixes

* remove a forgotten `}` for TLEN frame ([56593cb](https://github.com/ClementBeal/audio_metadata_reader/commit/56593cb02daf79b65e1b4ba3628c7a5df46b5f18))
* TLEN parser can fail if the content is not an integer ([d7ff5db](https://github.com/ClementBeal/audio_metadata_reader/commit/d7ff5dbf903d372b62dcef7c9ba55e9c2a34894e))
* write and read number in MP3 ([5441412](https://github.com/ClementBeal/audio_metadata_reader/commit/5441412ef650fa63d7bfde63c23ceb7e00b66fb2))
* write track number if it's alone ([6d2836e](https://github.com/ClementBeal/audio_metadata_reader/commit/6d2836e052d77dadb7fb959a4f22bf8300297158))

## [1.3.0](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.2.0...v1.3.0) (2025-04-20)

### Features

* add metadata writers ([#26](https://github.com/ClementBeal/audio_metadata_reader/issues/26)) ([463e10a](https://github.com/ClementBeal/audio_metadata_reader/commit/463e10a84266866361c111b23bb2c804a43e75c9))

## [1.2.0](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.1.2...v1.2.0) (2025-04-19)

### Features

* add RIFF parser ([#60](https://github.com/ClementBeal/audio_metadata_reader/issues/60)) ([cf9d686](https://github.com/ClementBeal/audio_metadata_reader/commit/cf9d6865a46293218dcaa96eb6b8bda5925672c5))

## [1.1.2](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.1.1...v1.1.2) (2025-04-15)

### Bug Fixes

* OGG parsing was overflowing ([#58](https://github.com/ClementBeal/audio_metadata_reader/issues/58)) ([4d8d00f](https://github.com/ClementBeal/audio_metadata_reader/commit/4d8d00faf6364210bb181d2f9fdbe65bec0a8b4a))

## [1.1.1](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.1.0...v1.1.1) (2025-04-06)

### Bug Fixes

* calculate ID3v2 duration at the microsecond ([#54](https://github.com/ClementBeal/audio_metadata_reader/issues/54)) ([5eedca0](https://github.com/ClementBeal/audio_metadata_reader/commit/5eedca0a5d91f537dce7a846210730f008d8651c))
* find correctly the first MP3 frame ([#52](https://github.com/ClementBeal/audio_metadata_reader/issues/52)) ([ed6322c](https://github.com/ClementBeal/audio_metadata_reader/commit/ed6322c65c1371247f2cb5ab0dee17882d6deb71))
* MP4 parser is more robust ([#55](https://github.com/ClementBeal/audio_metadata_reader/issues/55)) ([1d0f7bf](https://github.com/ClementBeal/audio_metadata_reader/commit/1d0f7bf080886a17ec5a3c3bd03859b4cf45873f))

## [1.1.0](https://github.com/ClementBeal/audio_metadata_reader/compare/v1.0.0...v1.1.0) (2024-12-07)

### Features

* support album artist ([#39](https://github.com/ClementBeal/audio_metadata_reader/issues/39)) ([97c84cb](https://github.com/ClementBeal/audio_metadata_reader/commit/97c84cb9aede651eb8957e27e84047e467ec4e54))

### Bug Fixes

* ID3v2 wasn't parsing description as UTF-16 ([#42](https://github.com/ClementBeal/audio_metadata_reader/issues/42)) ([78e8c79](https://github.com/ClementBeal/audio_metadata_reader/commit/78e8c79d3240e38c60c5f6d91cec12d4642cdf72))
* parse correctly the null character ([#43](https://github.com/ClementBeal/audio_metadata_reader/issues/43)) ([7dda538](https://github.com/ClementBeal/audio_metadata_reader/commit/7dda538f2caf865153086556db28259923184daf))

## 1.0.0 (2024-11-28)

### Features

* metadata returns File reference ([01b01a3](https://github.com/ClementBeal/audio_metadata_reader/commit/01b01a375c27acaeb37a1e0d3420aa454ca9c1c8))
* use different exception if there's no available parser ([#29](https://github.com/ClementBeal/audio_metadata_reader/issues/29)) ([197624a](https://github.com/ClementBeal/audio_metadata_reader/commit/197624a94548b0bf1dc3263b1a7562da63b0affb))

### Bug Fixes

* exit if MP4 is malformed ([#35](https://github.com/ClementBeal/audio_metadata_reader/issues/35)) ([44536c6](https://github.com/ClementBeal/audio_metadata_reader/commit/44536c639acde9ec7af3bdeb968bd69cdc4ea61c))
* id3v1 metadata with ASCII ([#30](https://github.com/ClementBeal/audio_metadata_reader/issues/30)) ([22d5eeb](https://github.com/ClementBeal/audio_metadata_reader/commit/22d5eeb4b31d70a83f11f90ba9101ba439a5574f))
* id3v2 lyric ([#36](https://github.com/ClementBeal/audio_metadata_reader/issues/36)) ([4987448](https://github.com/ClementBeal/audio_metadata_reader/commit/498744840c42c4a2e633a1a8a822c390d4334b18))
* ID3v2 lyrics with UTF-16 ([#27](https://github.com/ClementBeal/audio_metadata_reader/issues/27)) ([57f18eb](https://github.com/ClementBeal/audio_metadata_reader/commit/57f18ebca7072cbea86b9804c3e901b4b645cd64))
* ogg perf and mp4 parsing ([#34](https://github.com/ClementBeal/audio_metadata_reader/issues/34)) ([9183ae8](https://github.com/ClementBeal/audio_metadata_reader/commit/9183ae8974c2f86a469677d01f6f8b544caa9465))
* Opus/OGG duration ([#21](https://github.com/ClementBeal/audio_metadata_reader/issues/21)) ([3ade1b7](https://github.com/ClementBeal/audio_metadata_reader/commit/3ade1b74b40b261dd66ba67a666601d409940db9))
* read all metadata from Opus ([#28](https://github.com/ClementBeal/audio_metadata_reader/issues/28)) ([0be3d0e](https://github.com/ClementBeal/audio_metadata_reader/commit/0be3d0ebbc79ce93fae247ce85e34e3366baa213))
* skip images + id3v2 extended header ([#22](https://github.com/ClementBeal/audio_metadata_reader/issues/22)) ([d1eb14f](https://github.com/ClementBeal/audio_metadata_reader/commit/d1eb14f3df938c0798a9c7ba7cf1b4832a31e8fa))
* skip the non used id3 tags ([a24eab6](https://github.com/ClementBeal/audio_metadata_reader/commit/a24eab6378c3b3960e5e488e385c7e49354ec03b))
* sometimes the track value is empty ([#31](https://github.com/ClementBeal/audio_metadata_reader/issues/31)) ([256da3d](https://github.com/ClementBeal/audio_metadata_reader/commit/256da3d51de1694fd73797f79a152d5b787f94b1))
* various bugs in ID3 ([#24](https://github.com/ClementBeal/audio_metadata_reader/issues/24)) ([e6c5c61](https://github.com/ClementBeal/audio_metadata_reader/commit/e6c5c61a913a8b5044f1653c4a094c6ea6934872))

## 0.0.11

* OGG : fix performance
* ID3v2 : read the lyrics correctly for UTF8-LE
* MP4 : reset the reader when we start the parsing

## 0.0.10

* ID3v2 : read correctly the lyric if we have UTF-16
* Opus  : performance improvement. Back to a few ms per file
* ID3v1 : fix the metadata if we have ASCII
* Add a new exception to differenciate a parse error from an non-implemented parser
* ID3v2 : fix the track number. Seems that it can be defined but empty

## 0.0.9

* OGG   : compute correctly the duration
* ID3v2 : skip correctly the images if we don't want them
* ID3v2 : take care of the extended header
* ID3v2 : use the correct MPEG version and layer

## 0.0.8

* Fix : MP4 day is parsed correctly
* Fix : The `Buffer` skip function is skipping correctly
* Some basic refactoring

## 0.0.7

### BREAKING CHANGE

* `readMetadata` is now synchronous. You may remove some `Future.wait()`
* `InvalidTag` class has beem removed and replace with a real exception `MetadataParserException`
* Remove the writers. They are not working

## Other

* Performance improvement : **70%** faster by using sync IO operations and a File Buffer to read files
* Support `ID3v1`

## 0.0.6

* Fix : the MP4 duration was not accurate (#9). Thanks to @PKiman

## 0.0.5

* A reference to the file is returned with the metadata

## 0.0.4

* Update docs : show what format can be read and written
* Add tests to the projects
* Fix : mp3 can retreive total discs
* Fix : mp4 can retreive lyrics/genre/samplerate/total tracks/total discs
* Fix : OGG and OPUS can retreive lyrics

## 0.0.3

* Remove dependencies to Flutter
* add support for OPUS and OGG

## 0.0.2

* FIX : read correcly a FLAC track. A mistake in the mask was missing the metadata
* FIX : compute correctly the duration of a MP3 track with Variable Bit Rate (VBR)

## 0.0.1

* Release of the first version
