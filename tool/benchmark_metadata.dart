import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Compares this package with FFmpeg's `ffprobe` metadata reader.
///
/// The default directory is `~/Music` on macOS. A different directory can be
/// supplied with `--music`. Files are filtered with the same list of
/// extensions exposed by the package, so image files and unrelated documents
/// are never passed to either reader.
///
/// Cover images are deliberately disabled for the Dart reader with
/// `getImage: false`. For ffprobe, only `format_tags` are requested: attached
/// picture streams are not part of the requested output. The container still
/// has to be inspected to find its metadata, but image bytes are not returned
/// or decoded by this benchmark.
///
/// Example:
///
///   dart run tool/benchmark_metadata.dart --backend both --runs 3
///   dart run tool/benchmark_metadata.dart --music ~/Music/Jazz --backend library
///
/// Important: the ffprobe backend starts one external process per file. Its
/// result includes process-startup overhead and must not be read as a direct
/// in-process libavformat benchmark. It is useful as a real-world baseline.
void main(List<String> arguments) {
  final options = _Options.parse(arguments);

  if (options.showHelp) {
    _printUsage();
    return;
  }

  final musicDirectory = Directory(options.musicPath);
  if (!musicDirectory.existsSync()) {
    stderr.writeln('Music directory does not exist: ${musicDirectory.path}');
    exitCode = 2;
    return;
  }

  final files = _findAudioFiles(musicDirectory);
  if (files.isEmpty) {
    stdout.writeln('No supported audio files found in ${musicDirectory.path}.');
    return;
  }

  stdout.writeln('Directory: ${musicDirectory.path}');
  stdout.writeln('Audio files: ${files.length}');
  stdout.writeln('Images: skipped (metadata only, no cover bytes requested)');
  stdout.writeln('Runs: ${options.runs}');

  final backends = switch (options.backend) {
    _Backend.library => <_Backend>[_Backend.library],
    _Backend.ffprobe => <_Backend>[_Backend.ffprobe],
    _Backend.both => <_Backend>[_Backend.library, _Backend.ffprobe],
  };

  for (final backend in backends) {
    if (backend == _Backend.ffprobe && !_commandIsAvailable(options.ffprobe)) {
      stderr.writeln(
        'Skipping ffprobe: command not found (${options.ffprobe}). '
        'Install FFmpeg or pass --ffprobe /path/to/ffprobe.',
      );
      continue;
    }

    _runBenchmark(
      backend: backend,
      files: files,
      runs: options.runs,
      ffprobe: options.ffprobe,
    );
  }
}

List<File> _findAudioFiles(Directory directory) {
  final supportedExtensions = supportedFileExtensions
      .map((extension) => extension.toLowerCase())
      .toSet();

  final files = <File>[];
  try {
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final path = entity.path.toLowerCase();
      if (supportedExtensions.any(path.endsWith)) {
        files.add(entity);
      }
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Could not enumerate ${directory.path}: $error');
  }

  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

void _runBenchmark({
  required _Backend backend,
  required List<File> files,
  required int runs,
  required String ffprobe,
}) {
  final durations = <Duration>[];
  var totalErrors = 0;

  stdout.writeln('\n${backend.label}');
  for (var run = 1; run <= runs; run++) {
    final stopwatch = Stopwatch()..start();
    var errors = 0;

    for (final file in files) {
      try {
        switch (backend) {
          case _Backend.library:
            // This is the package's high-level API used by applications.
            // `false` is important: cover images can be several megabytes.
            readMetadata(file, getImage: false);
          case _Backend.ffprobe:
            _readWithFfprobe(ffprobe, file);
          case _Backend.both:
            throw StateError('The combined backend cannot run by itself.');
        }
      } catch (error) {
        errors++;
        if (errors <= 3) {
          stderr.writeln('  ${file.path}: $error');
        }
      }
    }

    stopwatch.stop();
    final duration = stopwatch.elapsed;
    durations.add(duration);
    totalErrors += errors;

    stdout.writeln(
      '  run $run: ${_formatDuration(duration)} '
      '(${_formatRate(files.length, duration)}, errors: $errors)',
    );
  }

  final minimum = durations.reduce(_minDuration);
  final maximum = durations.reduce(_maxDuration);
  final averageMicros = durations
          .map((duration) => duration.inMicroseconds)
          .reduce((a, b) => a + b) /
      durations.length;

  stdout.writeln(
    '  summary: min ${_formatDuration(minimum)}, '
    'avg ${_formatDuration(Duration(microseconds: averageMicros.round()))}, '
    'max ${_formatDuration(maximum)}, total errors: $totalErrors',
  );
}

void _readWithFfprobe(String command, File file) {
  final result = Process.runSync(
    command,
    <String>[
      '-v',
      'error',
      '-of',
      'json',
      // Request tags only. In particular, do not request attached-picture
      // streams or packet data, which would make this an image benchmark too.
      '-show_entries',
      'format_tags',
      file.path,
    ],
    runInShell: false,
  );

  if (result.exitCode != 0) {
    final message = result.stderr.toString().trim();
    throw ProcessException(
        command, <String>[file.path], message, result.exitCode);
  }
}

bool _commandIsAvailable(String command) {
  if (command.contains(Platform.pathSeparator)) {
    return File(command).existsSync();
  }

  final result = Process.runSync('which', <String>[command]);
  return result.exitCode == 0;
}

Duration _minDuration(Duration left, Duration right) =>
    left <= right ? left : right;

Duration _maxDuration(Duration left, Duration right) =>
    left >= right ? left : right;

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMicroseconds / 1000;
  return '${milliseconds.toStringAsFixed(2)} ms';
}

String _formatRate(int fileCount, Duration duration) {
  if (duration.inMicroseconds == 0) {
    return 'unlimited files/s';
  }

  final filesPerSecond =
      fileCount * Duration.microsecondsPerSecond / duration.inMicroseconds;
  return '${filesPerSecond.toStringAsFixed(1)} files/s';
}

void _printUsage() {
  stdout.write('''
Usage: dart run tool/benchmark_metadata.dart [options]

Options:
  --music PATH       Directory to scan (default: ~/Music)
  --backend NAME     library, ffprobe, or both (default: both)
  --runs N           Number of passes per backend (default: 1)
  --ffprobe PATH     ffprobe executable (default: ffprobe)
  -h, --help         Show this help

Examples:
  dart run tool/benchmark_metadata.dart
  dart run tool/benchmark_metadata.dart --backend library --runs 3
  dart run tool/benchmark_metadata.dart --music ~/Music --backend both
''');
}

enum _Backend { library, ffprobe, both }

extension on _Backend {
  String get label => switch (this) {
        _Backend.library => 'Dart package (getImage: false)',
        _Backend.ffprobe => 'FFmpeg/libavformat through ffprobe',
        _Backend.both => 'both',
      };
}

class _Options {
  _Options({
    required this.musicPath,
    required this.backend,
    required this.runs,
    required this.ffprobe,
    required this.showHelp,
  });

  factory _Options.parse(List<String> arguments) {
    final home = Platform.environment['HOME'];
    var musicPath =
        home == null ? '${Directory.current.path}/Music' : '$home/Music';
    var backend = _Backend.both;
    var runs = 1;
    var ffprobe = 'ffprobe';
    var showHelp = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
        continue;
      }

      final option = argument.startsWith('--') && argument.contains('=')
          ? argument.substring(0, argument.indexOf('='))
          : argument;
      final inlineValue = argument.startsWith('--') && argument.contains('=')
          ? argument.substring(argument.indexOf('=') + 1)
          : null;

      String nextValue() {
        if (inlineValue != null) {
          return inlineValue;
        }
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value for $option');
        }
        index++;
        return arguments[index];
      }

      switch (option) {
        case '--music':
          musicPath = _expandHome(nextValue());
        case '--backend':
          backend = _parseBackend(nextValue());
        case '--runs':
          runs = int.parse(nextValue());
          if (runs < 1) {
            throw FormatException('--runs must be at least 1');
          }
        case '--ffprobe':
          ffprobe = _expandHome(nextValue());
        default:
          throw FormatException('Unknown option: $argument');
      }
    }

    return _Options(
      musicPath: musicPath,
      backend: backend,
      runs: runs,
      ffprobe: ffprobe,
      showHelp: showHelp,
    );
  }

  final String musicPath;
  final _Backend backend;
  final int runs;
  final String ffprobe;
  final bool showHelp;
}

_Backend _parseBackend(String value) => switch (value.toLowerCase()) {
      'library' || 'dart' => _Backend.library,
      'ffprobe' || 'ffmpeg' || 'c' => _Backend.ffprobe,
      'both' => _Backend.both,
      _ => throw FormatException(
          'Invalid --backend "$value" (expected library, ffprobe, or both)',
        ),
    };

String _expandHome(String path) {
  final home = Platform.environment['HOME'];
  if (home != null && (path == '~' || path.startsWith('~/'))) {
    return '$home${path.substring(1)}';
  }
  return path;
}
