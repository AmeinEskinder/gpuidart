import 'dart:io';

void main() {
  // Resolve the runtime even when PATH points to Flutter's dart wrapper.
  stdout.writeln(File(Platform.resolvedExecutable).parent.parent.path);
}
