import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_tooltip/overlay_tooltip.dart';

void main() {
  testWidgets('a GlobalKey target releases its old controller when reparented',
      (WidgetTester tester) async {
    final TooltipController first = TooltipController();
    final TooltipController second = TooltipController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final Widget target = _OverlayHarness.item(index: 0, key: GlobalKey());
    Widget host({required bool moved}) => MaterialApp(
          home: Row(
            children: <Widget>[
              Expanded(
                child: OverlayTooltipScaffold(
                    controller: first,
                    builder: (_) => moved ? const SizedBox.shrink() : target),
              ),
              Expanded(
                child: OverlayTooltipScaffold(
                    controller: second,
                    builder: (_) => moved ? target : const SizedBox.shrink()),
              ),
            ],
          ),
        );
    await tester.pumpWidget(host(moved: false));
    expect(first.playWidgetLength, 1);
    expect(second.playWidgetLength, 0);
    final State<StatefulWidget> state =
        tester.state(find.byType(OverlayTooltipItem));
    await tester.pumpWidget(host(moved: true));
    expect(tester.state(find.byType(OverlayTooltipItem)), same(state));
    expect(first.playWidgetLength, 0);
    expect(second.playWidgetLength, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.playWidgetLength, 0);
  });

  testWidgets('unmounted targets do not accumulate in a long-lived controller',
      (WidgetTester tester) async {
    final TooltipController controller = TooltipController();
    addTearDown(controller.dispose);
    for (int visit = 0; visit < 30; visit++) {
      await tester.pumpWidget(_OverlayHarness.build(
          controller, _OverlayHarness.item(index: visit)));
      expect(controller.playWidgetLength, 1);
      await tester.pumpWidget(
          _OverlayHarness.build(controller, const SizedBox.shrink()));
      expect(controller.playWidgetLength, 0);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing display index releases the previous registration',
      (WidgetTester tester) async {
    final TooltipController controller = TooltipController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        _OverlayHarness.build(controller, _OverlayHarness.item(index: 1)));
    await tester.pumpWidget(
        _OverlayHarness.build(controller, _OverlayHarness.item(index: 2)));
    expect(controller.playWidgetLength, 1);
    final List<int?> played = <int?>[];
    final StreamSubscription<OverlayTooltipModel?> subscription =
        controller.widgetsPlayStream.listen(
      (OverlayTooltipModel? model) => played.add(model?.displayIndex),
    );
    addTearDown(subscription.cancel);
    controller.start(2);
    await tester.pump();
    expect(played, <int?>[2]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.playWidgetLength, 0);
  });

  testWidgets('disposing a replaced item does not remove its successor',
      (WidgetTester tester) async {
    final TooltipController controller = TooltipController();
    addTearDown(controller.dispose);
    final Widget oldItem =
        _OverlayHarness.item(index: 0, key: const ValueKey<String>('old'));
    final Widget newItem =
        _OverlayHarness.item(index: 0, key: const ValueKey<String>('new'));
    await tester.pumpWidget(_OverlayHarness.build(
        controller, Column(children: <Widget>[oldItem, newItem])));
    expect(controller.playWidgetLength, 1);
    await tester.pumpWidget(
        _OverlayHarness.build(controller, Column(children: <Widget>[newItem])));
    expect(controller.playWidgetLength, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.playWidgetLength, 0);
  });

  testWidgets(
      'removing an active target hides the overlay without completing the tutorial',
      (
    WidgetTester tester,
  ) async {
    final TooltipController controller = TooltipController();
    addTearDown(controller.dispose);
    int completed = 0;
    controller.onDone(() => completed++);
    await tester.pumpWidget(
        _OverlayHarness.build(controller, _OverlayHarness.item(index: 0)));
    final List<OverlayTooltipModel?> played = <OverlayTooltipModel?>[];
    final StreamSubscription<OverlayTooltipModel?> subscription =
        controller.widgetsPlayStream.listen(played.add);
    addTearDown(subscription.cancel);
    controller.start();
    await tester.pumpAndSettle();
    await tester
        .pumpWidget(_OverlayHarness.build(controller, const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(controller.playWidgetLength, 0);
    expect(played.last, isNull);
    expect(completed, 0);
    expect(tester.takeException(), isNull);
  });

  test('a pending automatic start cannot revive a disposed controller',
      () async {
    final TooltipController controller = TooltipController();
    final Completer<bool> ready = Completer<bool>();
    controller
      ..setStartWhen((_) => ready.future)
      ..addPlayableWidget(_OverlayHarness.model());
    expect(controller.playWidgetLength, 1);
    controller.dispose();
    ready.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.playWidgetLength, 0);
    controller.dispose();
  });

  test('next visits the successor of a removed active step', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2]);
    final played = _record(controller);
    int completed = 0;
    controller.onDone(() => completed++);
    controller.start(1);
    controller.removePlayableWidget(models[1].widgetKey);
    controller.next();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[1, null, 2]);
    expect(controller.nextPlayIndex, 1);
    expect(completed, 0);
  });

  test('previous visits the predecessor of a removed active step', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2]);
    final played = _record(controller);
    controller.start(1);
    controller.removePlayableWidget(models[1].widgetKey);
    controller.previous();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[1, null, 0]);
  });

  test('removing the first step preserves the gap when previous cannot move',
      () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1]);
    final played = _record(controller);
    controller.start();
    controller.removePlayableWidget(models[0].widgetKey);
    controller.previous();
    controller.next();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[0, null, 1]);
  });

  test('removing the last active step still permits previous', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2]);
    final played = _record(controller);
    controller.start(2);
    controller.removePlayableWidget(models[2].widgetKey);
    controller.previous();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[2, null, 1]);
  });

  test('removing an earlier step preserves the active cursor', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2, 3]);
    final played = _record(controller);
    controller.start(2);
    controller.removePlayableWidget(models[0].widgetKey);
    expect(controller.nextPlayIndex, 1);
    controller.next();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[2, 3]);
  });

  test('removing a successor at the gap does not skip the remaining step',
      () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2, 3]);
    final played = _record(controller);
    controller.start(1);
    controller.removePlayableWidget(models[1].widgetKey);
    controller.removePlayableWidget(models[2].widgetKey);
    controller.next();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[1, null, 3]);
  });

  test('removing a paused step resumes at its successor', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1, 2]);
    final played = _record(controller);
    controller.start(1);
    controller.pause();
    controller.removePlayableWidget(models[1].widgetKey);
    controller.next();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[1, null, 2]);
  });

  test('new registrations remain sorted without moving the active step',
      () async {
    final controller = _controller();
    _register(controller, <int>[3, 0, 2]);
    final played = _record(controller);
    controller.start(2);
    controller.addPlayableWidget(_OverlayHarness.model(index: 1));
    expect(controller.nextPlayIndex, 2);
    controller.previous();
    await _flush();
    expect(played.map((model) => model?.displayIndex), <int?>[2, 1]);
  });

  test('a new target can fill the removed active step gap', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0]);
    final played = _record(controller);
    controller.start();
    controller.removePlayableWidget(models.single.widgetKey);
    final replacement = _OverlayHarness.model(index: 0);
    controller.addPlayableWidget(replacement);
    controller.next();
    await _flush();
    expect(played.last, same(replacement));
    expect(controller.nextPlayIndex, 0);
  });

  test('previous remains in bounds after repeated next at the end', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1]);
    final played = _record(controller);
    controller.start(1);
    controller.next();
    controller.next();
    controller.previous();
    await _flush();
    expect(played.last, same(models.last));
  });

  test('an active replacement is emitted and survives predecessor removal',
      () async {
    final controller = _controller();
    final original = _OverlayHarness.model();
    final replacement = _OverlayHarness.model();
    final played = _record(controller);
    controller.addPlayableWidget(original);
    controller.start();
    controller.addPlayableWidget(replacement);
    controller.removePlayableWidget(original.widgetKey);
    await _flush();
    expect(controller.playWidgetLength, 1);
    expect(played.length, 2);
    expect(played.last, same(replacement));
    controller.removePlayableWidget(replacement.widgetKey);
    await _flush();
    expect(controller.playWidgetLength, 0);
    expect(played.last, isNull);
  });

  test('a pending automatic start for a removed target is ignored', () async {
    final controller = _controller();
    final first = Completer<bool>(), second = Completer<bool>();
    int calls = 0;
    controller.setStartWhen((_) => calls++ == 0 ? first.future : second.future);
    final models = _register(controller, <int>[0, 1]);
    final played = _record(controller);
    controller.removePlayableWidget(models.first.widgetKey);
    first.complete(true);
    second.complete(false);
    await _flush();
    expect(played, isEmpty);
    expect(controller.playWidgetLength, 1);
  });

  test('a pending automatic start for a replaced model is ignored', () async {
    final controller = _controller();
    final first = Completer<bool>(), second = Completer<bool>();
    int calls = 0;
    controller.setStartWhen((_) => calls++ == 0 ? first.future : second.future);
    _register(controller, <int>[0, 0]);
    final played = _record(controller);
    first.complete(true);
    second.complete(false);
    await _flush();
    expect(played, isEmpty);
    expect(controller.playWidgetLength, 1);
  });

  test('a result from a replaced readiness callback is ignored', () async {
    final controller = _controller();
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    _register(controller, <int>[0]);
    final played = _record(controller);
    controller.setStartWhen((_) async => false);
    ready.complete(true);
    await _flush();
    expect(played, isEmpty);
  });

  test('concurrent readiness results start once despite repeated stream reads',
      () async {
    final controller = _controller();
    final ready = List<Completer<bool>>.generate(4, (_) => Completer<bool>());
    int calls = 0;
    controller.setStartWhen((_) => ready[calls++].future);
    _register(controller, <int>[0, 1, 2, 3]);
    final played = _record(controller);
    for (int read = 0; read < 30; read++) {
      expect(controller.widgetsPlayStream.isBroadcast, isTrue);
    }
    for (final result in ready) {
      result.complete(true);
    }
    await _flush();
    expect(played.length, 1);
    expect(played.single?.displayIndex, 0);
  });

  for (final action in <String>['pause', 'dismiss', 'completion']) {
    test('late readiness respects $action and subsequent target updates',
        () async {
      final controller = _controller();
      final first = Completer<bool>(), second = Completer<bool>();
      int checks = 0;
      controller
          .setStartWhen((_) => checks++ == 0 ? first.future : second.future);
      final models = _register(controller, <int>[0, 1]);
      final played = _record(controller);
      first.complete(true);
      await _flush();
      expect(played.single, same(models.first));

      if (action == 'pause') {
        controller.pause();
      } else if (action == 'dismiss') {
        controller.dismiss();
      } else {
        controller.next();
        controller.next();
      }
      await _flush();
      final events = List<OverlayTooltipModel?>.of(played);
      expect(events.last, isNull);
      controller.setStartWhen((_) {
        checks++;
        return second.future;
      });
      controller.addPlayableWidget(_OverlayHarness.model(index: 2));
      controller.addPlayableWidget(
          _OverlayHarness.model(widgetKey: models.first.widgetKey));
      second.complete(true);
      await _flush();
      expect(played, events);
      expect(checks, 2);
    });
  }

  for (final action in <String>['pause', 'dismiss']) {
    test('$action before readiness prevents the first automatic start',
        () async {
      final controller = _controller();
      final ready = Completer<bool>();
      controller.setStartWhen((_) => ready.future);
      _register(controller, <int>[0]);
      final played = _record(controller);
      if (action == 'pause') {
        controller.pause();
      } else {
        controller.dismiss();
      }
      ready.complete(true);
      await _flush();
      expect(played, <OverlayTooltipModel?>[null]);
    });
  }

  test('late readiness preserves a manually selected restart step', () async {
    final controller = _controller();
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    final models = _register(controller, <int>[0, 1]);
    final played = _record(controller);
    controller.pause();
    controller.start(1);
    ready.complete(true);
    await _flush();
    expect(played, <OverlayTooltipModel?>[null, models.last]);
    expect(controller.nextPlayIndex, 1);
  });

  test('completion is notified once until an explicit restart', () {
    final controller = _controller();
    _register(controller, <int>[0]);
    int completed = 0;
    controller.onDone(() => completed++);
    controller.start();
    controller.next();
    controller.next();
    controller.dismiss();
    controller.previous();
    controller.next();
    expect(completed, 1);
    controller.start();
    controller.dismiss();
    controller.dismiss();
    expect(completed, 2);
  });

  test('completion callbacks can dismiss or advance without recursive onDone',
      () {
    final controller = _controller();
    _register(controller, <int>[0]);
    int completed = 0;
    controller.onDone(() {
      completed++;
      controller.dismiss();
      controller.next();
    });
    controller.start();
    controller.next();
    expect(completed, 1);
  });

  test('onDone can explicitly start a new run', () async {
    final controller = _controller();
    final models = _register(controller, <int>[0, 1]);
    final played = _record(controller);
    int completed = 0;
    controller.onDone(() {
      if (++completed == 1) controller.start(1);
    });
    controller.start();
    controller.dismiss();
    await _flush();
    expect(played.last, same(models.last));
    controller.next();
    expect(completed, 2);
  });

  test('unchanged owners share a pending check and start their latest model',
      () async {
    final controller = _controller();
    final ready = Completer<bool>();
    final key = GlobalKey();
    int checks = 0;
    controller.setStartWhen((_) {
      checks++;
      return ready.future;
    });
    late OverlayTooltipModel latest;
    for (int update = 0; update < 100; update++) {
      latest = _OverlayHarness.model(widgetKey: key);
      controller.addPlayableWidget(latest);
    }
    final played = _record(controller);
    expect(checks, 1);
    ready.complete(true);
    await _flush();
    expect(played.single, same(latest));
  });

  test('a false readiness result permits a later check for the same owner',
      () async {
    final controller = _controller();
    final first = Completer<bool>(), second = Completer<bool>();
    final key = GlobalKey();
    int checks = 0;
    controller
        .setStartWhen((_) => checks++ == 0 ? first.future : second.future);
    controller.addPlayableWidget(_OverlayHarness.model(widgetKey: key));
    final played = _record(controller);
    first.complete(false);
    await _flush();
    expect(played, isEmpty);
    final latest = _OverlayHarness.model(widgetKey: key);
    controller.addPlayableWidget(latest);
    second.complete(true);
    await _flush();
    expect(checks, 2);
    expect(played.single, same(latest));
  });

  test('replacing owners and callbacks on one future starts only the latest',
      () async {
    final controller = _controller();
    final ready = Completer<bool>();
    late OverlayTooltipModel latest;
    for (int update = 0; update < 100; update++) {
      controller.setStartWhen((_) => ready.future);
      latest = _OverlayHarness.model();
      controller.addPlayableWidget(latest);
    }
    final played = _record(controller);
    ready.complete(true);
    await _flush();
    expect(controller.playWidgetLength, 1);
    expect(played.single, same(latest));
  });

  test('count changes replace a check without a stale result clearing it',
      () async {
    final controller = _controller();
    final ready = List<Completer<bool>>.generate(3, (_) => Completer<bool>());
    final counts = <int>[];
    controller.setStartWhen((count) {
      counts.add(count);
      return ready[counts.length - 1].future;
    });
    final models = _register(controller, <int>[0, 1]);
    final latest = _OverlayHarness.model(widgetKey: models.first.widgetKey);
    controller.addPlayableWidget(latest);
    final played = _record(controller);
    ready[0].complete(true);
    ready[1].complete(false);
    await _flush();
    expect(played, isEmpty);
    controller.addPlayableWidget(latest);
    expect(counts, <int>[1, 2, 2]);
    ready[2].complete(true);
    await _flush();
    expect(played.single, same(latest));
  });

  test('callback changes replace pending checks for an unchanged owner',
      () async {
    final controller = _controller();
    final first = Completer<bool>(), second = Completer<bool>();
    final key = GlobalKey();
    controller.setStartWhen((_) => first.future);
    controller.addPlayableWidget(_OverlayHarness.model(widgetKey: key));
    controller.setStartWhen((_) => second.future);
    final latest = _OverlayHarness.model(widgetKey: key);
    controller.addPlayableWidget(latest);
    final played = _record(controller);
    first.complete(true);
    await _flush();
    expect(played, isEmpty);
    second.complete(true);
    await _flush();
    expect(played.single, same(latest));
  });

  test('a synchronous readiness error is forwarded and permits a retry',
      () async {
    final controller = _controller();
    final errors = <Object>[];
    final error = StateError('readiness failed');
    final ready = Completer<bool>();
    final key = GlobalKey();
    int checks = 0;
    runZonedGuarded(() {
      controller.setStartWhen((_) {
        if (++checks == 1) throw error;
        return ready.future;
      });
      controller.addPlayableWidget(_OverlayHarness.model(widgetKey: key));
    }, (error, _) => errors.add(error));
    await _flush();
    expect(errors, <Object>[error]);
    final latest = _OverlayHarness.model(widgetKey: key);
    final played = _record(controller);
    controller.addPlayableWidget(latest);
    ready.complete(true);
    await _flush();
    expect(checks, 2);
    expect(played.single, same(latest));
  });

  test('a shared readiness error is forwarded once and releases all checks',
      () async {
    final controller = _controller();
    final errors = <Object>[];
    final error = StateError('shared readiness failed');
    late Completer<bool> failed;
    late List<OverlayTooltipModel> models;
    runZonedGuarded(() {
      failed = Completer<bool>();
      controller.setStartWhen((_) => failed.future);
      models = _register(controller, <int>[0, 1]);
    }, (error, _) => errors.add(error));
    failed.completeError(error);
    await _flush();
    expect(errors, <Object>[error]);
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    final latest = _OverlayHarness.model(widgetKey: models.first.widgetKey);
    controller.addPlayableWidget(latest);
    final played = _record(controller);
    ready.complete(true);
    await _flush();
    expect(played.single, same(latest));
  });

  testWidgets('target rebuilds keep one readiness check and the latest tooltip',
      (tester) async {
    final controller = _controller();
    final ready = Completer<bool>();
    int checks = 0;
    Future<bool> startWhen(int count) {
      checks++;
      return ready.future;
    }

    for (int update = 0; update < 30; update++) {
      await tester.pumpWidget(_OverlayHarness.build(
          controller, _OverlayHarness.item(index: 0, label: 'tooltip $update'),
          startWhen: startWhen));
    }
    expect(checks, 1);
    ready.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('tooltip 29'), findsOneWidget);
    expect(controller.playWidgetLength, 1);
  });

  test(
      'dispose clears playback before closing and all later mutations are inert',
      () async {
    final controller = _controller();
    final models = _register(controller, <int>[0]);
    final played = <OverlayTooltipModel?>[];
    final closed = Completer<void>();
    final sub = controller.widgetsPlayStream
        .listen(played.add, onDone: closed.complete);
    addTearDown(sub.cancel);
    int completed = 0;
    controller.onDone(() => completed++);
    controller.start();
    controller.dispose();
    await closed.future;
    expect(played.first, same(models.single));
    expect(played.last, isNull);
    expect(controller.playWidgetLength, 0);
    controller
      ..addPlayableWidget(_OverlayHarness.model())
      ..removePlayableWidget(models.single.widgetKey)
      ..setStartWhen((_) async => true)
      ..onDone(() => completed++)
      ..start()
      ..next()
      ..previous()
      ..pause()
      ..dismiss()
      ..dispose();
    await _flush();
    expect(completed, 0);
    expect(played.length, 2);
    expect(controller.playWidgetLength, 0);
  });

  testWidgets(
      'changing controllers transfers a reused target and drops the old snapshot',
      (tester) async {
    final first = _controller(), second = _controller();
    final target = _OverlayHarness.item(index: 0, label: 'tooltip');
    await tester.pumpWidget(_OverlayHarness.build(first, target));
    final state = tester.state(find.byType(OverlayTooltipItem));
    first.start();
    await tester.pumpAndSettle();
    expect(find.text('tooltip'), findsOneWidget);
    await tester.pumpWidget(_OverlayHarness.build(second, target));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(OverlayTooltipItem)), same(state));
    expect(first.playWidgetLength, 0);
    expect(second.playWidgetLength, 1);
    expect(find.text('tooltip'), findsNothing);
    second.start();
    await tester.pumpAndSettle();
    expect(find.text('tooltip'), findsOneWidget);
  });

  testWidgets('repeated controller swaps do not accumulate registrations',
      (tester) async {
    final controllers = <TooltipController>[_controller(), _controller()];
    final target = _OverlayHarness.item(index: 0);
    for (int visit = 0; visit < 30; visit++) {
      final active = visit % 2;
      await tester
          .pumpWidget(_OverlayHarness.build(controllers[active], target));
      expect(controllers[active].playWidgetLength, 1);
      expect(controllers[1 - active].playWidgetLength, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controllers.map((controller) => controller.playWidgetLength),
        <int>[0, 0]);
  });

  testWidgets(
      'replacement releases the active snapshot of its disposed predecessor',
      (tester) async {
    final controller = _controller();
    final old = _OverlayHarness.item(
        index: 0, key: const ValueKey('old'), label: 'old tooltip');
    final replacement = _OverlayHarness.item(
        index: 0, key: const ValueKey('new'), label: 'new tooltip');
    final played = _record(controller);
    await tester.pumpWidget(
        _OverlayHarness.build(controller, Column(children: <Widget>[old])));
    controller.start();
    await tester.pumpAndSettle();
    expect(find.text('old tooltip'), findsOneWidget);
    await tester.pumpWidget(_OverlayHarness.build(
        controller, Column(children: <Widget>[old, replacement])));
    await tester.pumpAndSettle();
    expect(find.text('new tooltip'), findsOneWidget);
    await tester.pumpWidget(_OverlayHarness.build(
        controller, Column(children: <Widget>[replacement])));
    await tester.pumpAndSettle();
    expect(controller.playWidgetLength, 1);
    expect(played.last?.widgetKey.currentContext, isNotNull);
    expect(find.text('old tooltip'), findsNothing);
    expect(find.text('new tooltip'), findsOneWidget);
  });

  testWidgets(
      'updating an active item replaces its child and tooltip without a rebuild loop',
      (tester) async {
    final controller = _controller();
    await tester.pumpWidget(_OverlayHarness.build(
        controller, _OverlayHarness.item(index: 0, label: 'old')));
    controller.start();
    await tester.pumpAndSettle();
    await tester.pumpWidget(_OverlayHarness.build(
        controller, _OverlayHarness.item(index: 0, label: 'new')));
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(find.text('new'), findsOneWidget);
    expect(controller.playWidgetLength, 1);
  });

  testWidgets('playback does not rebuild or re-register targets',
      (tester) async {
    final controller = _controller();
    int contentBuilds = 0, readinessChecks = 0;
    await tester.pumpWidget(MaterialApp(
      home: OverlayTooltipScaffold(
        controller: controller,
        startWhen: (_) async {
          readinessChecks++;
          return false;
        },
        builder: (_) {
          contentBuilds++;
          return Column(children: <Widget>[
            _OverlayHarness.item(index: 0),
            _OverlayHarness.item(index: 1),
          ]);
        },
      ),
    ));
    await tester.pumpAndSettle();
    controller.start();
    await tester.pumpAndSettle();
    controller.next();
    await tester.pumpAndSettle();
    controller.previous();
    await tester.pumpAndSettle();
    controller.pause();
    await tester.pumpAndSettle();
    expect(contentBuilds, 1);
    expect(readinessChecks, 2);
    expect(controller.playWidgetLength, 2);
  });

  testWidgets('reparenting outside a scaffold releases the old registration',
      (tester) async {
    final controller = _controller();
    final target = _OverlayHarness.item(index: 0, key: GlobalKey());
    Widget host(bool moved) => MaterialApp(
            home: Row(children: <Widget>[
          Expanded(
              child: OverlayTooltipScaffold(
                  controller: controller,
                  builder: (_) => moved ? const SizedBox.shrink() : target)),
          if (moved) target,
        ]));
    await tester.pumpWidget(host(false));
    final state = tester.state(find.byType(OverlayTooltipItem));
    expect(controller.playWidgetLength, 1);
    await tester.pumpWidget(host(true));
    expect(tester.state(find.byType(OverlayTooltipItem)), same(state));
    expect(controller.playWidgetLength, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting a scaffold releases its readiness callback',
      (tester) async {
    final controller = _controller();
    final ready = Completer<bool>();
    int checks = 0;
    await tester.pumpWidget(_OverlayHarness.build(
        controller, _OverlayHarness.item(index: 0), startWhen: (_) {
      checks++;
      return ready.future;
    }));
    await tester.pumpWidget(const SizedBox.shrink());
    final played = _record(controller);
    controller.addPlayableWidget(_OverlayHarness.model());
    ready.complete(true);
    await tester.pump();
    expect(checks, 1);
    expect(played, isEmpty);
  });

  testWidgets('removing startWhen invalidates a pending result',
      (tester) async {
    final controller = _controller();
    final target = _OverlayHarness.item(index: 0);
    final ready = Completer<bool>();
    final played = _record(controller);
    await tester.pumpWidget(_OverlayHarness.build(controller, target,
        startWhen: (_) => ready.future));
    await tester.pumpWidget(_OverlayHarness.build(controller, target));
    ready.complete(true);
    await tester.pump();
    expect(played, isEmpty);
    expect(controller.playWidgetLength, 1);
  });

  testWidgets(
      'scaffold cleanup preserves an externally replaced readiness callback',
      (tester) async {
    final controller = _controller();
    int checks = 0;
    await tester.pumpWidget(_OverlayHarness.build(
        controller, _OverlayHarness.item(index: 0),
        startWhen: (_) async => false));
    controller.setStartWhen((_) async {
      checks++;
      return false;
    });
    await tester.pumpWidget(const SizedBox.shrink());
    controller.addPlayableWidget(_OverlayHarness.model());
    await tester.pump();
    expect(checks, 1);
  });

  test(
      'constructing an unmounted scaffold does not retain its callback in the controller',
      () async {
    final controller = _controller();
    int checks = 0;
    OverlayTooltipScaffold(
      controller: controller,
      startWhen: (_) async {
        checks++;
        return false;
      },
      builder: (_) => const SizedBox.shrink(),
    );
    controller.addPlayableWidget(_OverlayHarness.model());
    await _flush();
    expect(checks, 0);
  });
}

class _OverlayHarness {
  static Widget build(TooltipController controller, Widget child,
          {Future<bool> Function(int)? startWhen}) =>
      MaterialApp(
        home: OverlayTooltipScaffold(
            controller: controller,
            startWhen: startWhen,
            builder: (_) => child),
      );

  static OverlayTooltipItem item(
          {required int index, Key? key, String? label}) =>
      OverlayTooltipItem(
        key: key,
        displayIndex: index,
        child: const SizedBox(width: 24, height: 24),
        tooltip: (_) => label == null ? const SizedBox.shrink() : Text(label),
      );

  static OverlayTooltipModel model({int index = 0, GlobalKey? widgetKey}) =>
      OverlayTooltipModel(
        absorbPointer: true,
        child: const SizedBox.shrink(),
        tooltip: (_) => const SizedBox.shrink(),
        widgetKey: widgetKey ?? GlobalKey(),
        vertPosition: TooltipVerticalPosition.BOTTOM,
        horPosition: TooltipHorizontalPosition.WITH_WIDGET,
        displayIndex: index,
      );
}

TooltipController _controller() {
  final controller = TooltipController();
  addTearDown(controller.dispose);
  return controller;
}

List<OverlayTooltipModel> _register(
        TooltipController controller, List<int> indexes) =>
    indexes.map((index) {
      final model = _OverlayHarness.model(index: index);
      controller.addPlayableWidget(model);
      return model;
    }).toList();

List<OverlayTooltipModel?> _record(TooltipController controller) {
  final played = <OverlayTooltipModel?>[];
  final subscription = controller.widgetsPlayStream.listen(played.add);
  addTearDown(subscription.cancel);
  return played;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
