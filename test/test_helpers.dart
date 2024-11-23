import 'dart:io';

File createTemporaryFile(String filename) {
  final dir = Directory.systemTemp.createTempSync();

  final tempFile = File('${dir.path}/$filename');
  tempFile.createSync();

  return tempFile;
}
