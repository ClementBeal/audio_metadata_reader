import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Finds the exact audio files that cannot be parsed by this package.
///
/// This diagnostic intentionally uses the same file discovery rules as the
/// benchmark, but reports every failure instead of folding failures into one
/// counter. It is useful when a large music library contains a few malformed,
/// truncated, encrypted, or unsupported files.
///
/// No picture payload is requested: the Dart reader always receives
/// `getImage: false`. The parser may still inspect the tag headers needed to
/// locate fields, but it does not materialize embedded cover bytes.
///
/// Examples:
///
///   dart run tool/find_metadata_errors.dart
///   dart run tool/find_metadata_errors.dart --music ~/Music --stack-traces
///   dart run tool/find_metadata_errors.dart --backend ffprobe
void main(List<String> arguments) {
  final options = _Options.parse(arguments);

  if (options.showHelp) {
    _printUsage();
    return;
  }

  final directory = Directory(options.musicPath);
  if (!directory.existsSync()) {
    stderr.writeln('Music directory does not exist: ${directory.path}');
    exitCode = 2;
    return;
  }

  final files = _findAudioFiles(directory);
  stdout.writeln('Directory: ${directory.path}');
  stdout.writeln('Supported audio files: ${files.length}');
  stdout.writeln('Cover images: disabled');

  if (files.isEmpty) {
    stdout.writeln('No supported audio files found.');
    return;
  }

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

    _inspectFiles(
      files: files,
      backend: backend,
      ffprobe: options.ffprobe,
      includeStackTraces: options.includeStackTraces,
    );
  }
}

List<File> _findAudioFiles(Directory directory) {
  final extensions = supportedFileExtensions
      .map((extension) => extension.toLowerCase())
      .toSet();
  final files = <File>[];

  try {
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is File &&
          extensions.any(entity.path.toLowerCase().endsWith)) {
        files.add(entity);
      }
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Could not enumerate ${directory.path}: $error');
  }

  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

void _inspectFiles({
  required List<File> files,
  required _Backend backend,
  required String ffprobe,
  required bool includeStackTraces,
}) {
  final errorsByType = <String, int>{};
  var failureCount = 0;

  stdout.writeln('\n${backend.label}');
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    try {
      switch (backend) {
        case _Backend.library:
          readMetadata(file, getImage: false);
        case _Backend.ffprobe:
          _readWithFfprobe(ffprobe, file);
        case _Backend.both:
          throw StateError('The combined backend cannot run by itself.');
      }
    } catch (error, stackTrace) {
      failureCount++;
      final type = error.runtimeType.toString();
      errorsByType[type] = (errorsByType[type] ?? 0) + 1;

      stdout.writeln('ERROR $failureCount: ${file.path}');
      stdout.writeln('  $type: ${_singleLine(error)}');
      if (includeStackTraces) {
        stdout.writeln(stackTrace);
      }
    }
  }

  stdout.writeln('\nSummary for ${backend.label}:');
  stdout.writeln('  Successful: ${files.length - failureCount}');
  stdout.writeln('  Errors: $failureCount');

  if (errorsByType.isNotEmpty) {
    stdout.writeln('  Errors by type:');
    for (final entry in errorsByType.entries) {
      stdout.writeln('    ${entry.key}: ${entry.value}');
    }
  }

  if (failureCount > 0) {
    stdout.writeln(
      '\nThe complete list above can be saved with shell redirection, for example:',
    );
    stdout.writeln(
      '  dart run tool/find_metadata_errors.dart > metadata-errors.txt',
    );
  }
}

String _singleLine(Object error) =>
    error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

void _readWithFfprobe(String command, File file) {
  final result = Process.runSync(
    command,
    <String>[
      '-v',
      'error',
      '-of',
      'json',
      '-show_entries',
      'format_tags',
      file.path,
    ],
    runInShell: false,
  );

  if (result.exitCode != 0) {
    throw ProcessException(
      command,
      <String>[file.path],
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }
}

bool _commandIsAvailable(String command) {
  if (command.contains(Platform.pathSeparator)) {
    return File(command).existsSync();
  }
  return Process.runSync('which', <String>[command]).exitCode == 0;
}

void _printUsage() {
  stdout.write('''
Usage: dart run tool/find_metadata_errors.dart [options]

Options:
  --music PATH       Directory to scan (default: ~/Music)
  --backend NAME     library, ffprobe, or both (default: library)
  --ffprobe PATH     ffprobe executable (default: ffprobe)
  --stack-traces     Print a Dart stack trace for every library error
  -h, --help         Show this help

Examples:
  dart run tool/find_metadata_errors.dart
  dart run tool/find_metadata_errors.dart --music ~/Music --stack-traces
  dart run tool/find_metadata_errors.dart --backend both
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
    required this.ffprobe,
    required this.includeStackTraces,
    required this.showHelp,
  });

  factory _Options.parse(List<String> arguments) {
    final home = Platform.environment['HOME'];
    var musicPath =
        home == null ? '${Directory.current.path}/Music' : '$home/Music';
    var backend = _Backend.library;
    var ffprobe = 'ffprobe';
    var includeStackTraces = false;
    var showHelp = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '-h' || argument == '--help') {
        showHelp = true;
        continue;
      }
      if (argument == '--stack-traces') {
        includeStackTraces = true;
        continue;
      }

      final hasInlineValue =
          argument.startsWith('--') && argument.contains('=');
      final option = hasInlineValue
          ? argument.substring(0, argument.indexOf('='))
          : argument;
      final inlineValue =
          hasInlineValue ? argument.substring(argument.indexOf('=') + 1) : null;

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
        case '--ffprobe':
          ffprobe = _expandHome(nextValue());
        default:
          throw FormatException('Unknown option: $argument');
      }
    }

    return _Options(
      musicPath: musicPath,
      backend: backend,
      ffprobe: ffprobe,
      includeStackTraces: includeStackTraces,
      showHelp: showHelp,
    );
  }

  final String musicPath;
  final _Backend backend;
  final String ffprobe;
  final bool includeStackTraces;
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
