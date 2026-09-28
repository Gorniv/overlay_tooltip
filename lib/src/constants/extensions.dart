import 'package:flutter/material.dart';

extension GlobalKeyEx on GlobalKey {
  Rect? get globalPaintBounds {
    // A streamed model can outlive target deactivation by one frame.
    // Element.renderObject also handles inactive/defunct elements safely.
    final BuildContext? context = currentContext;
    final RenderObject? renderObject = context is Element ? context.renderObject : null;
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
      return null;
    }
    final translation = renderObject.getTransformTo(null).getTranslation();
    return renderObject.paintBounds.shift(Offset(translation.x, translation.y));
  }
}
