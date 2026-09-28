import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../example/terminal/app.dart';
import 'accessibility/terminal_track.dart';

Future<void> main(List<String> args) async {
  final semantics = args.contains('--semantics');
  final output = File(args.first);
  if (output.existsSync()) {
    throw StateError('Refusing to replace ${output.path}');
  }
  output.parent.createSync(recursive: true);
  final rows = int.parse(
    args.where((a) => a.startsWith('--rows=')).firstOrNull?.substring(7) ??
        '100000',
  );
  final steps = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'passed': false,
    'platform': Platform.operatingSystem,
    'dart': Platform.version,
    'mode': const bool.fromEnvironment('dart.vm.product') ? 'aot' : 'jit',
    'rows': rows,
    'scope': 'Real native window and GPUI key dispatch. External OS queries when requested; no visual, screen-reader or latency claim.',
    'semantics': semantics,
    'steps': steps,
  };
  TerminalApplication? app;
  try {
    app = await TerminalApplication.open(rows: rows);
    final terminal = app;
    final host = terminal.host;
    final process =
        (await host.diagnose('inspect'))['native_process_id'] as int;
    Future<Map<String, dynamic>> observe() async {
      await terminal.idle;
      if (terminal.failure != null) {
        throw StateError('App failure: ${terminal.failure}');
      }
      return {
        'app': terminal.describe(),
        'native': await host.diagnose('inspect'),
        'metrics': host.metrics.read(),
      };
    }

    Future<Map<String, dynamic>> until(
      String name,
      bool Function(Map<String, dynamic>) ready,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      Map<String, dynamic>? last;
      do {
        last = await observe();
        if (ready(last)) {
          if (semantics) {
            last['platform'] = await terminalSemantics(process, last);
          }
          steps.add({'step': name, 'observed': last});
          return last;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      } while (DateTime.now().isBefore(deadline));
      steps.add({'step': name, 'observed': last, 'failed': true});
      throw StateError('Terminal step did not settle: $name');
    }

    Future<void> key(String key) async {
      await terminal.idle;
      await host.diagnose('repaint', {'frames': 1});
      await host.diagnose('key', {'key': key});
      await host.diagnose('repaint', {'frames': 1});
      await terminal.idle;
    }

    final mod = Platform.isMacOS ? 'cmd' : 'ctrl';
    await host.diagnose('repaint', {'frames': 2});
    final initial = await until(
      '100k initial table and navigation',
      (s) => s['native']['tables']['watchlist']['row_count'] == rows,
    );
    final visible = initial['native']['tables']['watchlist']['visible_rows'];
    if ((visible['end'] as int) - (visible['start'] as int) >= 100) {
      throw StateError('Table viewport exceeded bound');
    }
    await host.diagnose('select_row', {'table': 'watchlist', 'row': 25});
    await until(
      'stable selected record loads history once',
      (s) =>
          s['app']['selected'] == 'BRK0025' &&
          s['app']['history_revision'] == 2,
    );
    // A large dataset uploads in slices, so its revision after open depends
    // on the slice count; the tick must advance it by exactly one.
    final instrumentsRevision = initial['app']['instruments_revision'] as int;
    await host.diagnose('focus', {'input': 'search'});
    await key('tab');
    await key('space');
    await until(
      'button tick edits selected record',
      (s) =>
          s['app']['ticks'] == 1 &&
          s['app']['instruments_revision'] == instrumentsRevision + 1,
    );
    if (semantics) {
      report['tooltip'] = await verifyTerminalTooltip(process);
    }
    // The native row menu opens from the table's selection and dispatches a record action.
    await host.diagnose('focus', {'input': 'search'});
    for (var i = 0; i < 5; i++) {
      await key('tab');
    }
    await until(
      'table focus after toolbar',
      (s) => s['native']['tables']['watchlist']['focused'] == true,
    );
    await key('shift-f10');
    if (semantics) {
      report['context_menu'] = await terminalMenuSemantics(
        process,
        context: true,
      );
    }
    await key('down');
    await key('enter');
    await until(
      'row context command opens captured instrument',
      (s) =>
          s['app']['page'] == 'instrument' &&
          s['native']['charts']['price-chart']?['points'].length == 20,
    );
    // Navigate through tabs so the focus handoff to the radio group is observed.
    await key('$mod-1');
    await until(
      'global watchlist action',
      (s) => s['app']['page'] == 'watchlist',
    );
    await host.diagnose('focus', {'input': 'search'});
    await key('shift-tab');
    await key('right');
    await key('enter');
    await until(
      'tab keyboard navigation',
      (s) => s['app']['page'] == 'instrument',
    );
    await key('tab');
    await key('right');
    final all = await until(
      'radio expands both dataset views',
      (s) =>
          s['app']['period'] == '48' &&
          s['native']['charts']['volume-chart']?['points'].length == 48,
    );
    if (all['app']['history_revision'] != 3) {
      throw StateError('Range navigation republished history');
    }
    if (semantics) {
      report['app_menu'] = await invokeTerminalSettingsMenu(process);
    } else {
      await key('$mod-,');
    }
    await until(
      'application menu opens settings',
      (s) => s['app']['page'] == 'settings',
    );
    await host.diagnose('focus', {'input': 'display-name'});
    for (final k in ['$mod-a', 'backspace', 'a', 'd', 'a']) {
      await key(k);
    }
    await until(
      'native input updates application draft',
      (s) => s['app']['display_name'] == 'ada',
    );
    await key('tab');
    await key('right');
    final dark = await until(
      'dark theme snapshot',
      (s) =>
          s['app']['theme'] == 'dark' &&
          s['native']['theme']['descriptor']['mode'] == 'dark',
    );
    await key('tab');
    await key('space');
    final custom = await until(
      'bounded custom accent',
      (s) =>
          s['app']['custom_accent'] == true &&
          s['native']['theme']['resolved']['primary'] == '#93C5FD',
    );
    report['contrast'] = [
      for (final state in [initial, dark, custom])
        contrast(state['native']['theme']['resolved'] as Map),
    ];
    for (final entry in report['contrast'] as List) {
      if ((entry['foreground_background'] as double) < 4.5 ||
          (entry['primary_pair'] as double) < 4.5) {
        throw StateError(
          'Declared terminal text token contrast below 4.5: $entry',
        );
      }
    }
    await key('$mod-1');
    await until('return to watchlist', (s) => s['app']['page'] == 'watchlist');
    await key('$mod-,');
    await until(
      'draft and theme survive tab remount',
      (s) =>
          s['app']['page'] == 'settings' &&
          s['native']['inputs']['display-name']?['text'] == 'ada' &&
          s['app']['theme'] == 'dark',
    );
    await host.diagnose('focus', {'input': 'display-name'});
    await key('left');
    await key('shift-left');
    final before = await observe();
    await host.rebuild();
    await host.diagnose('repaint', {'frames': 2});
    final after = await observe();
    if (jsonEncode(before['native']['inputs']) !=
            jsonEncode(after['native']['inputs']) ||
        before['metrics']['data_bytes'] != after['metrics']['data_bytes']) {
      throw StateError(
        'Unchanged snapshot changed native draft or republished datasets',
      );
    }
    steps.add({
      'step': 'snapshot retains input and datasets',
      'before': before,
      'after': after,
    });
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    if (semantics &&
        Platform.isLinux &&
        Platform.environment['GPUIDART_CAPTURE_FAILURE'] == '1') {
      // Capture the private Xvfb test desktop before closing the failed fixture.
      // This is diagnostic evidence, not an automated visual-quality assertion.
      try {
        final capture = await Process.run('scrot', ['${output.path}.png']);
        report['failure_capture'] = {
          'exit': capture.exitCode,
          'stderr': '${capture.stderr}',
          'path': '${output.path}.png',
        };
      } catch (captureError) {
        report['failure_capture'] = {'error': '$captureError'};
      }
    }
    rethrow;
  } finally {
    await app?.close();
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
}

Map<String, double> contrast(Map colors) {
  double luminance(String hex) {
    final value = int.parse(hex.substring(1), radix: 16);
    double channel(int shift) {
      final c = ((value >> shift) & 255) / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
  }

  double ratio(String a, String b) {
    final x = luminance(colors[a] as String),
        y = luminance(colors[b] as String);
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  return {
    'foreground_background': ratio('foreground', 'background'),
    'primary_pair': ratio('primary_foreground', 'primary'),
  };
}
