import 'package:flutter/material.dart';

import 'app_scope.dart';

/// One tap: save any running capture, lock, and return to a cleared
/// calculator. Placed in the top bar of every unlocked screen.
///
/// Deliberately a plain, unlabelled "close" icon: a red button saying
/// PANIC would itself tell an onlooker what the app is.
class PanicButton extends StatelessWidget {
  const PanicButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Close',
      icon: Icon(Icons.close, color: color ?? Colors.white),
      onPressed: () => AppScope.of(context).lock.panic(),
    );
  }
}
