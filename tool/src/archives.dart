import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

Future<void> createZip(Directory directory, File destination) async {
  await destination.parent.create(recursive: true);
  final encoder = ZipFileEncoder()..create(destination.path);
  try {
    await encoder.addDirectory(directory, includeDirName: false);
  } finally {
    await encoder.close();
  }
}

Future<void> extractZip(File archive, Directory destination) async {
  final input = InputFileStream(archive.path);
  try {
    final decoded = ZipDecoder().decodeStream(input, verify: true);
    await destination.create(recursive: true);
    final root = await destination.resolveSymbolicLinks();
    // Validate every member before writing any of the archive contents.
    final names = <String>{};
    for (final member in decoded) {
      final name = member.name.replaceAll('\\', '/');
      final target = p.normalize(p.join(root, name));
      if (member.isSymbolicLink ||
          name.startsWith('/') ||
          name.contains(':') ||
          name.split('/').contains('..') ||
          !p.isWithin(root, target) ||
          !names.add(Platform.isWindows ? target.toLowerCase() : target)) {
        throw FormatException('Unsafe archive path: ${member.name}');
      }
      var existing = target;
      while (p.isWithin(root, existing)) {
        if (FileSystemEntity.isLinkSync(existing)) {
          throw FormatException(
            'Archive destination contains a link: $existing',
          );
        }
        existing = p.dirname(existing);
      }
    }
    for (final member in decoded) {
      final target = p.join(root, member.name.replaceAll('\\', '/'));
      if (!member.isFile) {
        await Directory(target).create(recursive: true);
        continue;
      }
      await File(target).parent.create(recursive: true);
      final output = OutputFileStream(target);
      try {
        member.writeContent(output);
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
}

Future<void> extractCrt(File archive, File destination) async {
  final input = InputFileStream(archive.path);
  try {
    final decoded = ZipDecoder().decodeStream(input, verify: true);
    final matches = decoded.files
        .where(
          (file) =>
              file.name.endsWith('/x64/Microsoft.VC143.CRT/vcruntime140.dll'),
        )
        .toList();
    if (matches.length != 1) {
      throw StateError('Expected one release x64 CRT entry');
    }
    await destination.parent.create(recursive: true);
    final output = OutputFileStream(destination.path);
    try {
      matches.single.writeContent(output);
    } finally {
      await output.close();
    }
  } finally {
    await input.close();
  }
}
