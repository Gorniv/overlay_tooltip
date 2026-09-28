import 'package:flutter/material.dart';
import '../constants/enums.dart';
import '../impl.dart';
import '../model/tooltip_widget_model.dart';
import 'overlay_tooltip_scaffold.dart';

abstract class OverlayTooltipItemImpl extends StatefulWidget {
  final bool absorbPointer;
  final Widget child;
  final Widget Function(TooltipController) tooltip;
  final TooltipVerticalPosition tooltipVerticalPosition;
  final TooltipHorizontalPosition tooltipHorizontalPosition;
  final int displayIndex;

  OverlayTooltipItemImpl(
      {Key? key,
      required this.absorbPointer,
      required this.displayIndex,
      required this.child,
      required this.tooltip,
      required this.tooltipVerticalPosition,
      required this.tooltipHorizontalPosition})
      : super(key: key);

  @override
  _OverlayTooltipItemImplState createState() => _OverlayTooltipItemImplState();
}

class _OverlayTooltipItemImplState extends State<OverlayTooltipItemImpl> {
  final GlobalKey widgetKey = GlobalKey();
  TooltipController? _controller;
  bool _registrationScheduled = false;

  @override
  void didUpdateWidget(covariant OverlayTooltipItemImpl oldWidget) {
    if (oldWidget.displayIndex != widget.displayIndex) {
      _controller?.removePlayableWidget(widgetKey);
    }
    _addToPlayableWidget();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = OverlayTooltipControllerScope.maybeOf(context);
    if (!identical(_controller, controller)) {
      _controller?.removePlayableWidget(widgetKey);
      _controller = controller;
    }
    _addToPlayableWidget();
  }

  @override
  void activate() {
    super.activate();
    _addToPlayableWidget();
  }

  @override
  void dispose() {
    _controller?.removePlayableWidget(widgetKey);
    _controller = null;
    super.dispose();
  }

  void _addToPlayableWidget() {
    if (_registrationScheduled) return;
    _registrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _registrationScheduled = false;
      if (!mounted) return;
      _controller?.addPlayableWidget(OverlayTooltipModel(
          absorbPointer: widget.absorbPointer,
          child: widget.child,
          tooltip: widget.tooltip,
          widgetKey: widgetKey,
          vertPosition: widget.tooltipVerticalPosition,
          horPosition: widget.tooltipHorizontalPosition,
          displayIndex: widget.displayIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: widgetKey,
      color: Colors.transparent,
      child: widget.child,
    );
  }
}
