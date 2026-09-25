import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import 'src/commands.dart';

Future<void> main(List<String> args) async {
  if (!Platform.isLinux || args.length != 2) {
    throw ArgumentError('Usage on X11: verify_x11_display.dart SCALE REPORT');
  }
  final scale = double.parse(args[0]);
  final report = <String, dynamic>{
    'passed': false,
    'expected_scale': scale,
    'scale_override': Platform.environment['GPUI_X11_SCALE_FACTOR'],
    'scope': 'X11 native client geometry and resize at a forced scale. No physical monitor, IME or mixed-monitor claim.',
  };
  final title = 'GPUI-Dart display check $pid';
  GpuiHost? host;
  try {
    host = await GpuiHost.open(
      const UiText('message', 'Display geometry check'),
      window: GpuiWindowOptions(title: title, width: 960, height: 720),
    );
    final id = (await command('xdotool', [
      'search',
      '--onlyvisible',
      '--name',
      '^$title\$',
    ])).split('\n').single;
    Future<Map<String, dynamic>> inspect(int width, int height) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        final state = await host!.diagnose('repaint', {'frames': 2});
        final window = state['window'] as Map;
        if (window['width'] == width &&
            window['height'] == height &&
            window['scale_factor'] == scale) {
          final geometry = await command('xdotool', [
            'getwindowgeometry',
            '--shell',
            id,
          ]);
          final fields = {
            for (final line in geometry.split('\n'))
              line.split('=').first: line.split('=').last,
          };
          if (int.parse(fields['WIDTH']!) != (width * scale).round() ||
              int.parse(fields['HEIGHT']!) != (height * scale).round()) {
            throw StateError(
              'Physical client geometry differs from logical size times scale: $geometry',
            );
          }
          return {'native': window, 'x11': fields};
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError(
        'Native geometry did not reach $width x $height at $scale',
      );
    }

    report['initial'] = await inspect(960, 720);
    await command('xdotool', [
      'windowsize',
      '--sync',
      id,
      '${(800 * scale).round()}',
      '${(600 * scale).round()}',
    ]);
    report['resized'] = await inspect(800, 600);
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await host?.close();
    } catch (error) {
      report['passed'] = false;
      report['close_error'] = '$error';
      exitCode = 1;
    }
    final output = File(args[1]);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
  stdout.writeln('X11 display check at $scale: ${report['passed']}');
}
