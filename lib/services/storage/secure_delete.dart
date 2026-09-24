import 'dart:io';

import 'package:flutter/foundation.dart';

/// Best effort: overwrite [file] with zeros, then delete it.
///
/// Flash wear levelling means the old blocks may survive the
/// overwrite. Never throws: failures are logged,
/// because every caller is cleaning up after the fact and has nothing
/// better to do with the error.
Future<void> destroyPlaintext(File file) async {
  try {
    if (!await file.exists()) return;

    final length = await file.length();
    // Append mode, then seek to 0: this overwrites the existing bytes
    // in place. FileMode.writeOnly would truncate first, freeing the
    // old blocks without ever overwriting them.
    final handle = await file.open(mode: FileMode.writeOnlyAppend);

    try {
      await handle.setPosition(0);

      const chunk = 64 * 1024;
      final zeros = Uint8List(chunk);

      for (var written = 0; written < length; written += chunk) {
        final size = length - written < chunk ? length - written : chunk;
        await handle.writeFrom(zeros, 0, size);
      }

      await handle.flush();
    } finally {
      await handle.close();
    }

    await file.delete();
  } catch (error) {
    debugPrint('Could not destroy plaintext ${file.path}: $error');
  }
}
