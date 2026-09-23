import 'package:flutter/material.dart';

/// Explains that cloud copies of files are not switched on yet.
///
/// One dialog, shown from both the vault and the evidence detail
/// screen, so the two cannot drift into telling a survivor different
/// things about what is and is not protected.
///
/// The wording does two jobs. It says what *is* already true, because
/// it is the more important half and it is easy to miss: the record
/// proving this evidence exists is on the server and cannot be removed.
/// And it names the gap without softening it, because a survivor
/// deciding whether this phone is a safe place for her evidence is
/// owed the real answer.
Future<void> showCloudBackupNotice(
  BuildContext context, {
  bool multiple = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF11151D),
      icon: const Icon(
        Icons.cloud_off_outlined,
        color: Color(0xFF9B7BFF),
        size: 32,
      ),
      title: const Text(
        "Cloud backup isn't switched on yet",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 19),
      ),
      content: Text(
        multiple
            ? 'The fingerprints of your evidence are already saved to the '
                  'cloud. Those records cannot be changed or deleted by '
                  'anyone — so it can always be proved these files existed '
                  'and have not been altered.\n\n'
                  'What is not available yet is keeping copies of the files '
                  'themselves. Until that is switched on, they stay on this '
                  'phone only: if the phone is lost, they are lost with it.'
            : 'The fingerprint of this evidence is already saved to the '
                  'cloud. That record cannot be changed or deleted by anyone '
                  '— so it can always be proved this file existed and has '
                  'not been altered.\n\n'
                  'What is not available yet is keeping a copy of the file '
                  'itself. Until that is switched on, it stays on this phone '
                  'only: if the phone is lost, the file is lost with it.',
        style: const TextStyle(color: Color(0xFF9297A3), height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I understand'),
        ),
      ],
    ),
  );
}
