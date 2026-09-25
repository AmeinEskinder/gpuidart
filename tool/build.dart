import 'src/commands.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--release')) {
    throw ArgumentError('Usage: dart run tool/build.dart [--release]');
  }
  await buildNative(release: args.contains('--release'));
}
