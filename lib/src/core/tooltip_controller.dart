import 'dart:async';

import 'package:flutter/material.dart';

import '../model/tooltip_widget_model.dart';

abstract class TooltipControllerImpl {
  final List<_TooltipRegistration> _playableWidgets = [];
  final StreamController<OverlayTooltipModel?> _widgetsPlayController =
      StreamController.broadcast();

  final Expando<_PendingReadiness> _pendingStarts =
      Expando<_PendingReadiness>();
  _PlaybackState _state = _PlaybackState.idle;
  OverlayTooltipModel? _currentWidget;
  bool _hasStarted = false;
  bool _currentWidgetRemoved = false;
  bool _completionNotified = false;

  bool get _disposed => _state == _PlaybackState.disposed;

  Stream<OverlayTooltipModel?> get widgetsPlayStream =>
      _widgetsPlayController.stream;

  VoidCallback? _onDoneCallback;
  Future<bool> Function(int instantiatedWidgetLength)? _startWhenCallback;
  int _startWhenRevision = 0;

  int _nextPlayIndex = 0;

  int get nextPlayIndex => _nextPlayIndex;

  int get playWidgetLength => _playableWidgets.length;

  void start([int? displayIndex]) {
    if (_disposed) return;
    _nextPlayIndex = 0;
    if (displayIndex != null) {
      _nextPlayIndex = _playableWidgets.indexWhere(
          (registration) => registration.model!.displayIndex == displayIndex);
      if (_nextPlayIndex.isNegative) _nextPlayIndex = 0;
    }

    if (playWidgetLength == 0) {
      throw 'No overlay tooltip item has been '
          'initialized, consider inserting controller.start() in a button '
          'callback or using the startWhen method';
    }

    _hasStarted = true;
    _currentWidgetRemoved = false;
    _completionNotified = false;
    _state = _PlaybackState.playing;
    _emit(_playableWidgets[_nextPlayIndex].model);
  }

  void setStartWhen(
      Future<bool> Function(int initializedWidgetLength) callback) {
    if (_disposed) return;
    if (identical(_startWhenCallback, callback)) return;
    _startWhenRevision++;
    _startWhenCallback = callback;
  }

  /// Releases a callback only while it is still owned by its caller.
  void clearStartWhen(
      Future<bool> Function(int initializedWidgetLength) callback) {
    if (_disposed || !identical(_startWhenCallback, callback)) return;
    _startWhenRevision++;
    _startWhenCallback = null;
  }

  next() {
    if (_disposed) return;
    _hasStarted = true;
    _state = _PlaybackState.playing;
    // A removed step leaves a gap at this index. Its successor is already here.
    if (!_currentWidgetRemoved) _nextPlayIndex++;
    _currentWidgetRemoved = false;
    if (_nextPlayIndex < _playableWidgets.length) {
      _emit(_playableWidgets[_nextPlayIndex].model);
    } else {
      _nextPlayIndex = _playableWidgets.length;
      _complete();
    }
  }

  previous() {
    if (_disposed) return;
    if (_nextPlayIndex > 0) {
      _state = _PlaybackState.playing;
      _nextPlayIndex--;
      _currentWidgetRemoved = false;
      _emit(_playableWidgets[_nextPlayIndex].model);
    }
  }

  pause() {
    if (_disposed) return;
    _state = _PlaybackState.paused;
    _emit(null);
  }

  dismiss() {
    if (_disposed) return;
    _complete();
  }

  void _complete() {
    _state = _PlaybackState.completed;
    _emit(null);
    if (_completionNotified) return;
    _completionNotified = true;
    _onDoneCallback?.call();
  }

  void addPlayableWidget(OverlayTooltipModel model) {
    if (_disposed) return;
    final _TooltipRegistration registration;
    final int prevIndex = _playableWidgets.indexWhere(
      (item) => item.model!.displayIndex == model.displayIndex,
    );
    if (prevIndex >= 0) {
      final previous = _playableWidgets[prevIndex];
      if (identical(previous.model!.widgetKey, model.widgetKey)) {
        registration = previous;
        registration.model = model;
      } else {
        previous.release();
        registration = _TooltipRegistration(this, model);
        _playableWidgets[prevIndex] = registration;
      }
      if (_currentWidget?.displayIndex == model.displayIndex) {
        _emit(model);
      }
    } else {
      registration = _TooltipRegistration(this, model);
      final int followingIndex = _playableWidgets
          .indexWhere((item) => item.model!.displayIndex > model.displayIndex);
      final int index =
          followingIndex < 0 ? _playableWidgets.length : followingIndex;
      _playableWidgets.insert(index, registration);
      if (_hasStarted &&
          (index < _nextPlayIndex ||
              (index == _nextPlayIndex && !_currentWidgetRemoved))) {
        _nextPlayIndex++;
      }
    }

    final startWhen = _startWhenCallback;
    if (startWhen == null || _state != _PlaybackState.idle) return;
    registration.checkStartWhen(
        startWhen, _playableWidgets.length, _startWhenRevision);
  }

  void _startIfReady(int revision) {
    if (_state == _PlaybackState.idle && revision == _startWhenRevision) {
      start();
    }
  }

  void _watchReadiness(
      _TooltipRegistration registration, Future<bool> readiness) {
    var pending = _pendingStarts[readiness];
    final isNew = pending == null;
    if (pending == null) {
      pending = _PendingReadiness(_pendingStarts, readiness);
      _pendingStarts[readiness] = pending;
    }
    registration._readiness = pending;
    pending._registrations.add(registration);
    if (isNew) pending.listen();
  }

  void onDone(Function() onDone) {
    if (_disposed) return;
    _onDoneCallback = onDone;
  }

  /// Releases only the registration owned by this mounted item.
  ///
  /// A replacement with the same display index can have a different key.
  /// Disposing its predecessor must not remove the replacement's model.
  void removePlayableWidget(GlobalKey widgetKey) {
    if (_disposed) return;
    final int index = _playableWidgets.indexWhere(
      (item) => identical(item.model!.widgetKey, widgetKey),
    );
    if (index < 0) return;
    _playableWidgets.removeAt(index).release();
    if (identical(_currentWidget?.widgetKey, widgetKey)) {
      _emit(null);
    }
    if (index < _nextPlayIndex) {
      _nextPlayIndex--;
    } else if (index == _nextPlayIndex && _hasStarted) {
      _currentWidgetRemoved = true;
    }
  }

  void _emit(OverlayTooltipModel? model) {
    if (_disposed) return;
    _currentWidget = model;
    _widgetsPlayController.add(model);
  }

  void dispose() {
    if (_disposed) return;
    _emit(null);
    _state = _PlaybackState.disposed;
    for (final registration in _playableWidgets) {
      registration.release();
    }
    _playableWidgets.clear();
    _currentWidget = null;
    _onDoneCallback = null;
    _startWhenCallback = null;
    _widgetsPlayController.close();
  }
}

enum _PlaybackState { idle, playing, paused, completed, disposed }

/// Only mounted registrations are attached to a pending readiness request.
class _TooltipRegistration {
  TooltipControllerImpl? _controller;
  OverlayTooltipModel? model;
  _PendingReadiness? _readiness;
  int? _pendingRevision;
  int? _pendingCount;

  _TooltipRegistration(this._controller, this.model);

  void release() {
    _readiness?._registrations.remove(this);
    _readiness = null;
    _pendingRevision = null;
    _pendingCount = null;
    _controller = null;
    model = null;
  }

  void checkStartWhen(
      Future<bool> Function(int) callback, int count, int revision) {
    if (_readiness != null &&
        _pendingRevision == revision &&
        _pendingCount == count) {
      return;
    }
    final readiness = Future<bool>.sync(() => callback(count));
    final controller = _controller;
    if (controller == null) return;
    _readiness?._registrations.remove(this);
    _pendingRevision = revision;
    _pendingCount = count;
    controller._watchReadiness(this, readiness);
  }

  void finishReadiness(_PendingReadiness readiness, bool shouldStart) {
    if (!identical(_readiness, readiness)) return;
    final revision = _pendingRevision!;
    _readiness = null;
    _pendingRevision = null;
    _pendingCount = null;
    if (shouldStart) _controller?._startIfReady(revision);
  }
}

/// Expando keys are weak, so the cache does not keep readiness futures alive.
/// Each shared future has one listener per controller and retains current owners.
class _PendingReadiness {
  final Expando<_PendingReadiness> _cache;
  final Future<bool> _future;
  final Set<_TooltipRegistration> _registrations = {};

  _PendingReadiness(this._cache, this._future);

  void listen() {
    _future.then<void>(_complete,
        onError: (Object error, StackTrace stackTrace) {
      _complete(false);
      Zone.current.handleUncaughtError(error, stackTrace);
    });
  }

  void _complete(bool shouldStart) {
    _cache[_future] = null;
    final registrations = _registrations.toList();
    _registrations.clear();
    for (final registration in registrations) {
      registration.finishReadiness(this, shouldStart);
    }
  }
}
