import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gallery pages can also contain horizontal selectors and charts. Operations
/// on the document must target its vertical scrollable explicitly.
Finder galleryVerticalScroll({Finder? within}) {
  final vertical = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  return within == null
      ? vertical.last
      : find.descendant(of: within, matching: vertical).first;
}
