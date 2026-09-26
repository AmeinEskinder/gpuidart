import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/tracing.dart';

import '../example/settings/app.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/verify_settings.dart REPORT.json',
    );
  }
  final output = File(args.single);
  if (output.existsSync()) {
    throw StateError('Refusing to overwrite settings evidence: ${output.path}');
  }
  output.parent.createSync(recursive: true);
  final steps = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'started_utc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dart': Platform.version,
    'mode': const bool.fromEnvironment('dart.vm.product') ? 'aot' : 'jit',
    'scope': 'Real native window, GPUI key dispatch and native controls; no OS input injection, hardware IME, or presentation timing.',
    'steps': steps,
    'passed': false,
  };
  final trace = GpuiTrace(capacity: 8192);
  SettingsApplication? app;
  try {
    app = await SettingsApplication.open(trace: trace);
    final settings = app;
    report['native_runtime'] = await settings.host.diagnose('runtime');
    Future<Map<String, dynamic>> observe() async {
      await settings.idle;
      if (settings.failure != null) {
        throw StateError('Application failed: ${settings.failure}');
      }
      final native = await settings.host.diagnose('inspect');
      return {
        'app': settings.describe(),
        'native': {
          'revision': native['revision'],
          'inputs': native['inputs'],
          'controls': native['controls'],
          'focus_handle': native['focus_handle'],
        },
      };
    }

    Future<Map<String, dynamic>> until(
      String name,
      bool Function(Map<String, dynamic>) ready,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      Map<String, dynamic>? last;
      while (DateTime.now().isBefore(deadline)) {
        last = await observe();
        if (ready(last)) {
          steps.add({'name': name, 'observed': last});
          return last;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      throw StateError('$name did not settle: ${jsonEncode(last)}');
    }

    Future<void> key(String key) async {
      // A snapshot acknowledgement precedes rendering. Build its focus tree
      // before dispatching the next key (including after a dialog closes).
      await settings.idle;
      await settings.host.diagnose('repaint', {'frames': 1});
      final reply = await settings.host.diagnose('key', {'key': key});
      if (reply['ok'] != true) {
        throw StateError('Key failed: $reply');
      }
      // A completed content redraw gives deferred native callbacks a chance
      // to run; expected application outcomes are still checked explicitly.
      await settings.host.diagnose('repaint', {'frames': 1});
      await settings.idle;
    }

    Future<void> focusName() async {
      await settings.host.diagnose('focus', {'input': 'name'});
      await settings.host.diagnose('repaint', {'frames': 1});
    }

    await settings.host.diagnose('repaint', {'frames': 2});
    final initial = await until(
      'initial controlled name',
      (s) => s['native']['inputs']['name']['text'] == 'Dart user',
    );
    final firstEntity = initial['native']['inputs']['name']['entity'];
    await focusName();
    await key(Platform.isMacOS ? 'cmd-a' : 'ctrl-a');
    await key('backspace');
    await until(
      'empty-name validation disables notifications',
      (s) =>
          s['app']['draft']['name'] == '' &&
          s['native']['controls']['notifications']['disabled'] == true,
    );
    for (final letter in ['a', 'd', 'a']) {
      await key(letter);
    }
    await until(
      'native typing reaches Dart',
      (s) =>
          s['app']['draft']['name'] == 'ada' &&
          s['native']['inputs']['name']['text'] == 'ada',
    );
    await key('tab');
    await key('space');
    await until(
      'checkbox request acknowledged',
      (s) =>
          s['app']['draft']['notifications'] == false &&
          s['native']['controls']['notifications']['checked'] == false,
    );
    await focusName();
    await key('shift-tab');
    await key('enter');
    await until(
      'appearance navigation',
      (s) =>
          s['app']['section'] == 'appearance' &&
          s['native']['controls']['accent']?['selected'] == 'ocean',
    );
    await key('tab');
    await key('down');
    await key('down');
    await key('enter');
    await until(
      'select native keyboard commit',
      (s) =>
          s['app']['draft']['accent'] == 'forest' &&
          s['native']['controls']['accent']['selected'] == 'forest',
    );
    await key('tab');
    await key('right');
    await until(
      'slider native keyboard step',
      (s) =>
          s['app']['draft']['spacing'] == 18 &&
          s['native']['controls']['spacing']['number'] == 18,
    );
    await key('shift-tab');
    await key('shift-tab');
    await key('shift-tab');
    await key('enter');
    await until(
      'general navigation restores controlled name',
      (s) =>
          s['app']['section'] == 'general' &&
          s['native']['inputs']['name']?['text'] == 'ada',
    );
    await focusName();
    await key('left');
    await key('shift-left');
    final before = await observe();
    await settings.host.rebuild();
    final after = await until(
      'snapshot preserves native text selection and focus',
      (s) =>
          s['native']['inputs']['name']['entity'] ==
              before['native']['inputs']['name']['entity'] &&
          jsonEncode(s['native']['inputs']['name']['selection']) ==
              jsonEncode(before['native']['inputs']['name']['selection']) &&
          s['native']['inputs']['name']['focused'] == true &&
          s['native']['inputs']['name']['text'] == 'ada',
    );
    if (after['native']['inputs']['name']['entity'] == firstEntity) {
      throw StateError('Section unmount did not dispose the old input');
    }
    await key('tab');
    await key('tab');
    await key('tab');
    await key('enter');
    await until(
      'apply saves edited preferences',
      (s) =>
          s['app']['dirty'] == false &&
          s['app']['saved']['name'] == 'ada' &&
          s['app']['saved']['accent'] == 'forest' &&
          s['app']['saved']['spacing'] == 18 &&
          s['app']['saved']['notifications'] == false,
    );
    await key('shift-tab');
    final resetFocus = (await observe())['native']['focus_handle'];
    await key('enter');
    await until(
      'confirmation opens',
      (s) => s['native']['controls']['reset']['open'] == true,
    );
    await key('escape');
    await until(
      'cancel keeps draft and saved preferences',
      (s) =>
          s['native']['controls']['reset']['open'] == false &&
          s['app']['draft']['name'] == 'ada' &&
          s['app']['saved']['name'] == 'ada' &&
          s['app']['events']['dialog_result'] == 1 &&
          s['native']['focus_handle'] == resetFocus,
    );
    await key('enter');
    await until(
      'confirmation reopens',
      (s) => s['native']['controls']['reset']['open'] == true,
    );
    await key('enter');
    await until(
      'confirm resets draft through controlled write',
      (s) =>
          s['native']['controls']['reset']['open'] == false &&
          s['app']['draft']['name'] == 'Dart user' &&
          s['native']['inputs']['name']['text'] == 'Dart user' &&
          s['app']['saved']['name'] == 'ada' &&
          s['app']['dirty'] == true &&
          s['app']['events']['dialog_result'] == 2 &&
          s['native']['focus_handle'] == resetFocus,
    );
    await key('tab');
    await key('enter');
    await until(
      'apply saves reset draft',
      (s) =>
          s['app']['dirty'] == false &&
          s['app']['saved']['name'] == 'Dart user',
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await app?.close();
    } catch (error) {
      report['close_error'] = '$error';
      report['passed'] = false;
      exitCode = 1;
    }
    if (app != null) {
      final capture = trace.toJson();
      report['trace_metadata'] = capture['metadata'];
      if ((capture['metadata'] as Map)['capture_complete'] != true) {
        report['passed'] = false;
        exitCode = 1;
      }
      File(
        '${output.path}.trace.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(capture));
    }
    report['finished_utc'] = DateTime.now().toUtc().toIso8601String();
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln(
      'Saved ${output.path}: passed=${report['passed']}, steps=${steps.length}',
    );
  }
}
