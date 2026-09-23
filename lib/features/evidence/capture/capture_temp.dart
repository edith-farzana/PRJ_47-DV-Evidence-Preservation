import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../services/storage/secure_delete.dart';

/// The one place plaintext captures exist, and only between capture
/// and encryption.
///
/// Keeping them in their own directory, rather than loose in the cache,
/// means anything left behind by a crash or a force-stop can be found
/// and destroyed on the next launch ([sweep]) without guessing which
/// cache files are ours.
class CaptureTemp {
  CaptureTemp._();

  static const Uuid _uuid = Uuid();

  static Future<Directory> _directory() async {
    final temp = await getTemporaryDirectory();
    final directory = Directory('${temp.path}/capture');

    await directory.create(recursive: true);

    return directory;
  }

  /// A fresh path for a recorder to write to.
  static Future<File> newFile(String extension) async {
    final directory = await _directory();

    return File('${directory.path}/${_uuid.v4()}.$extension');
  }

  /// Moves a file a plugin wrote elsewhere in the cache into the
  /// capture directory, so [sweep] covers it too.
  static Future<File> adopt(String path) async {
    final source = File(path);
    final extension = path.contains('.') ? path.split('.').last : 'bin';
    final target = await newFile(extension);

    try {
      return await source.rename(target.path);
    } on FileSystemException {
      // Different filesystem: copy, then destroy the original.
      final copy = await source.copy(target.path);
      await destroyPlaintext(source);
      return copy;
    }
  }

  /// Files camera_android_camerax writes straight into the cache root,
  /// before [adopt] can move them: `CAP*.jpg` photos, `REC*.mp4` video.
  static final RegExp _cameraXFile = RegExp(r'^(CAP.*\.jpg|REC.*\.mp4)$');

  /// Destroys everything in the capture directory, and any camera files
  /// a killed capture left in the cache root. Called at launch, before
  /// anything can be capturing.
  static Future<void> sweep() async {
    final directory = await _directory();

    await for (final entity in directory.list()) {
      if (entity is File) {
        await destroyPlaintext(entity);
      }
    }

    await for (final entity in directory.parent.list()) {
      final name = entity.uri.pathSegments.last;

      if (entity is File && _cameraXFile.hasMatch(name)) {
        await destroyPlaintext(entity);
      }
    }
  }
}
