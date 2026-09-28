// leak_tracker requires Dart >=3.2 for these dev-only GC tests. Keep the
// published library's Dart 2.12 constraint instead of raising it for tests.
// ignore_for_file: sdk_version_since

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate' as isolates;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart';
import 'package:overlay_tooltip/overlay_tooltip.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

OverlayTooltipModel _model(int index, {GlobalKey? widgetKey}) =>
    OverlayTooltipModel(
      absorbPointer: true,
      child: const SizedBox.shrink(),
      tooltip: (_) => const SizedBox.shrink(),
      widgetKey: widgetKey ?? GlobalKey(),
      vertPosition: TooltipVerticalPosition.BOTTOM,
      horPosition: TooltipHorizontalPosition.WITH_WIDGET,
      displayIndex: index,
    );

WeakReference<OverlayTooltipModel> _removeModel(TooltipController controller) {
  final model = _model(0);
  final ref = WeakReference(model);
  controller.addPlayableWidget(model);
  controller.removePlayableWidget(model.widgetKey);
  return ref;
}

WeakReference<OverlayTooltipModel> _replaceModel(TooltipController controller) {
  final model = _model(0);
  final ref = WeakReference(model);
  controller.addPlayableWidget(model);
  controller.addPlayableWidget(_model(0));
  return ref;
}

List<WeakReference<OverlayTooltipModel>> _updateModels(
    TooltipController controller) {
  final key = GlobalKey();
  final refs = <WeakReference<OverlayTooltipModel>>[];
  for (int update = 0; update < 100; update++) {
    final model = _model(0, widgetKey: key);
    refs.add(WeakReference(model));
    controller.addPlayableWidget(model);
  }
  controller.addPlayableWidget(_model(0, widgetKey: key));
  return refs;
}

WeakReference<TooltipController> _disposePendingController(
    Completer<bool> ready) {
  final controller = TooltipController();
  final ref = WeakReference(controller);
  controller.setStartWhen((_) => ready.future);
  controller.addPlayableWidget(_model(0));
  controller.dispose();
  return ref;
}

Stream<OverlayTooltipModel?>? _heldStream;
WeakReference<TooltipController> _exposeStream() {
  final controller = TooltipController();
  _heldStream = controller.widgetsPlayStream;
  for (int i = 0; i < 30; i++) {
    controller.widgetsPlayStream;
  }
  return WeakReference(controller);
}

Widget _host(TooltipController controller, Widget child,
        {Future<bool> Function(int)? startWhen}) =>
    MaterialApp(
      home: OverlayTooltipScaffold(
          controller: controller, startWhen: startWhen, builder: (_) => child),
    );

Future<WeakReference<OverlayTooltipModel>> _observeModel(
    TooltipController controller) async {
  final model = await controller.widgetsPlayStream.first;
  return WeakReference(model!);
}

Future<WeakReference<Object>> _mountCapturedCallback(WidgetTester tester,
    TooltipController controller, Future<bool> readiness) async {
  final captured = _ReadinessCapture(readiness);
  await tester.pumpWidget(_host(
      controller,
      OverlayTooltipItem(
        displayIndex: 0,
        child: const SizedBox(width: 24, height: 24),
        tooltip: (_) => const SizedBox.shrink(),
      ),
      startWhen: (_) => captured.readiness));
  return WeakReference(captured);
}

class _ReadinessCapture {
  final Future<bool> readiness;

  _ReadinessCapture(this.readiness);
}

Future<void> main() async {
  final serviceUri = (await developer.Service.getInfo()).serverWebSocketUri;

  test('a removed model is collectible while startWhen never completes',
      () async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    final ref = _removeModel(controller);
    await forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);
    expect(ref.target, isNull);
    expect(ready.isCompleted, isFalse);
  });

  test('a replaced model is collectible while its startWhen never completes',
      () async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    final ref = _replaceModel(controller);
    await forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);
    expect(ref.target, isNull);
    expect(ready.isCompleted, isFalse);
  });

  test('same-owner updates release every superseded model during readiness',
      () async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    final ready = Completer<bool>();
    controller.setStartWhen((_) => ready.future);
    final refs = _updateModels(controller);
    await forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);
    expect(refs.map((ref) => ref.target), everyElement(isNull));
    expect(controller.playWidgetLength, 1);
    expect(ready.isCompleted, isFalse);
  });

  test('a disposed controller is collectible while startWhen never completes',
      () async {
    final ready = Completer<bool>();
    final ref = _disposePendingController(ready);
    await Future<void>.delayed(Duration.zero);
    await forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);
    expect(ref.target, isNull);
    expect(ready.isCompleted, isFalse);
  });

  test('reading and retaining the stream does not retain its owner', () async {
    addTearDown(() => _heldStream = null);
    final ref = _exposeStream();
    await forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);
    expect(ref.target, isNull);
    expect(_heldStream, isNotNull);
  });

  testWidgets(
      'a previous controller snapshot is collectible with its target still mounted',
      (tester) async {
    final first = TooltipController(), second = TooltipController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final target = OverlayTooltipItem(
      displayIndex: 0,
      child: const SizedBox(width: 24, height: 24),
      tooltip: (_) => const Text('tooltip'),
    );
    await tester.pumpWidget(_host(first, target));
    final modelRef = _observeModel(first);
    first.start();
    await tester.pumpAndSettle();
    final ref = await modelRef;
    await tester.pumpWidget(_host(second, target));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2));
    expect(ref.target, isNull);
    expect(second.playWidgetLength, 1);
    expect(find.byType(OverlayTooltipItem), findsOneWidget);
  });

  testWidgets(
      'scaffold cleanup frees objects captured by its readiness callback',
      (tester) async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    final ready = Completer<bool>();
    final ref = await _mountCapturedCallback(tester, controller, ready.future);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
        () => forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2));
    expect(ref.target, isNull);
    expect(controller.playWidgetLength, 0);
    expect(ready.isCompleted, isFalse);
  });

  group('pending readiness heap counts', () {
    late _ReadinessHeap heap;
    VmService? connection;
    setUpAll(() async {
      if (serviceUri == null) return;
      connection = await vmServiceConnectUri(serviceUri.toString());
      heap = _ReadinessHeap(connection!);
    });
    tearDownAll(() async => connection?.dispose());
    final skip = serviceUri == null
        ? 'Run flutter test --enable-vmservice to count live objects.'
        : false;

    test('same-owner updates keep one registration and one readiness listener',
        () async {
      final controller = TooltipController();
      addTearDown(controller.dispose);
      final ready = Completer<bool>();
      controller.setStartWhen((_) => ready.future);
      final key = GlobalKey();
      controller.addPlayableWidget(_model(0, widgetKey: key));
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 1);
      expect(await heap.count('_PendingReadiness'), 1);
      for (int update = 0; update < 100; update++) {
        controller.addPlayableWidget(_model(0, widgetKey: key));
      }
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 1);
      expect(await heap.count('_PendingReadiness'), 1);
      expect(controller.playWidgetLength, 1);
      expect(ready.isCompleted, isFalse);
    }, skip: skip);

    test('owner and callback replacements detach obsolete registrations',
        () async {
      final controller = TooltipController();
      addTearDown(controller.dispose);
      final ready = Completer<bool>();
      for (int update = 0; update < 100; update++) {
        controller.setStartWhen((_) => ready.future);
        controller.addPlayableWidget(_model(0));
      }
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 1);
      expect(await heap.count('_PendingReadiness'), 1);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 0);
      // The external future keeps only its single listener's metadata alive.
      expect(await heap.count('_PendingReadiness'), 1);
      expect(ready.isCompleted, isFalse);
    }, skip: skip);

    test('count changes on one future do not accumulate listeners or owners',
        () async {
      final controller = TooltipController();
      addTearDown(controller.dispose);
      final ready = Completer<bool>();
      controller.setStartWhen((_) => ready.future);
      final key = GlobalKey();
      controller.addPlayableWidget(_model(0, widgetKey: key));
      for (int update = 0; update < 100; update++) {
        final extra = _model(1);
        controller.addPlayableWidget(extra);
        controller.addPlayableWidget(_model(0, widgetKey: key));
        controller.removePlayableWidget(extra.widgetKey);
        controller.addPlayableWidget(_model(0, widgetKey: key));
      }
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 1);
      expect(await heap.count('_PendingReadiness'), 1);
      controller.removePlayableWidget(key);
      await heap.collect();
      expect(await heap.count('_TooltipRegistration'), 0);
      expect(await heap.count('_PendingReadiness'), 1);
      expect(ready.isCompleted, isFalse);
    }, skip: skip);
  });
}

/// Query counts without retrieving instances, which would retain test objects.
class _ReadinessHeap {
  final VmService service;
  final String isolateId =
      developer.Service.getIsolateId(isolates.Isolate.current)!;
  final Map<String, String> _classIds = {};

  _ReadinessHeap(this.service);

  Future<void> collect() =>
      forceGC(timeout: const Duration(seconds: 10), fullGcCycles: 2);

  Future<int> count(String name) async {
    var classId = _classIds[name];
    if (classId == null) {
      final classes = await service.getClassList(isolateId);
      classId = classes.classes!.singleWhere((item) => item.name == name).id!;
      _classIds[name] = classId;
    }
    return (await service.getInstances(isolateId, classId, 0)).totalCount!;
  }
}
