import 'dart:io';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  test(
    'sharpen-saw and sharpen-later Python scripts pass unit tests',
    () async {
      final scriptPath =
          Directory.current.path.split(Platform.pathSeparator).last == 'tool'
          ? 'test/sharpen_test.py'
          : 'tool/test/sharpen_test.py';
      final process = await TestProcess.start('python3', [scriptPath]);
      await process.shouldExit(0);
    },
  );
}
