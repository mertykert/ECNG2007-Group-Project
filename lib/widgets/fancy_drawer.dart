// lib/widgets/fancy_drawer.dart
import 'dart:ui';

import 'package:flutter/material.dart';

class FancyDrawerScaffold extends StatefulWidget {
  const FancyDrawerScaffold({
    super.key,
    required this.drawer,
    required this.body,
    this.drawerWidthFraction = 0.84,
    this.backgroundColor = const Color(0xFF2d59f0),
    this.scrimColor = Colors.transparent, // no dark overlay
    this.animationMs = 260,
    this.scale = 0.84,                    // how much the body shrinks when open
    this.borderRadius = 22.0,
    this.startOpen = false,
    this.bodyBackgroundColor = Colors.white,
  });

  final Widget drawer;
  final Widget body;
  final double drawerWidthFraction;
  final Color backgroundColor;
  final Color scrimColor;
  final int animationMs;
  final double scale;
  final double borderRadius;
  final bool startOpen;
  final Color bodyBackgroundColor;

  static FancyDrawerScaffoldState? of(BuildContext context) =>
      context.findAncestorStateOfType<FancyDrawerScaffoldState>();

  @override
  State<FancyDrawerScaffold> createState() => FancyDrawerScaffoldState();
}

class FancyDrawerScaffoldState extends State<FancyDrawerScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  // Flags
  bool get _isOpen => _controller.value > 0.001; // any progress
  bool get _fullyOpen =>
      _controller.status == AnimationStatus.completed; // 100% open

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.animationMs),
    );
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    if (widget.startOpen) _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void open() {
    debugPrint('FancyDrawer: open()');
    _controller.forward().whenComplete(() {
      debugPrint('FancyDrawer: opened value=${_controller.value}');
    });
  }

  void close() {
    debugPrint('FancyDrawer: close()');
    _controller.reverse();
  }

  void toggle() {
    debugPrint('FancyDrawer: toggle()');
    _isOpen ? close() : open();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        const double revealPeek = 100; // 92–120 to taste
        final size    = MediaQuery.of(context).size;
        final drawerW = size.width * widget.drawerWidthFraction;

        final slide  = (drawerW - revealPeek) * _t.value;
        final scale  = 1.0 - (1 - widget.scale) * _t.value;
        final radius = (widget.borderRadius + 12) * _t.value;

        return Stack(
          children: [
            // BACKDROP (frosted glass)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 12 + 10 * _t.value,
                      sigmaY: 12 + 10 * _t.value,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.backgroundColor.withOpacity(0.99),
                            widget.backgroundColor.withOpacity(0.95),
                          ],
                        ),
                        border: Border(
                          right: BorderSide(
                            color: Colors.white.withOpacity(0.28),
                            width: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // DRAWER CONTENT (interactive)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: drawerW,
                  child: Material(
                    type: MaterialType.transparency,
                    child: SafeArea(child: widget.drawer),
                  ),
                ),
              ),
            ),

            // MAIN CONTENT (card) — tap/drag to close only on the card
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(slide, 0),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.centerRight,
                  child: Stack(
                    children: [
                      // card with vertical-ish shadow
                      Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.22 * _t.value),
                              blurRadius: 28,
                              spreadRadius: 1,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.10 * _t.value),
                              blurRadius: 18,
                              spreadRadius: 0,
                              offset: const Offset(0, -10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: Material(
                            color: widget.bodyBackgroundColor,
                            child: widget.body,
                          ),
                        ),
                      ),

                      // when open, catch taps/drags *only* on the card
                      if (_isOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: close,
                            onHorizontalDragUpdate: (d) {
                              _controller.value =
                                  (_controller.value - d.primaryDelta! / drawerW)
                                      .clamp(0.0, 1.0);
                            },
                            onHorizontalDragEnd: (_) {
                              _controller.value < 0.5 ? close() : open();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // EDGE DRAG TO OPEN (keep as top-level sibling, not inside the card)
            if (!_isOpen)
              Positioned(
                left: 0, top: 0, bottom: 0, width: 24,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) {
                    if (d.primaryDelta != null && d.primaryDelta! > 0) {
                      _controller.value =
                          (_controller.value + d.primaryDelta! / drawerW)
                              .clamp(0.0, 1.0);
                    }
                  },
                  onHorizontalDragEnd: (_) =>
                  _controller.value > 0.15 ? open() : close(),
                ),
              ),
          ],
        );
      },
    );
  }
}

// (Kept for parity; not strictly needed unless you want a public controller via scope)
class _FancyDrawerScope extends InheritedWidget {
  const _FancyDrawerScope({
    required this.controller,
    required super.child,
  });
  final _FancyDrawerController controller;

  @override
  bool updateShouldNotify(covariant _FancyDrawerScope oldWidget) =>
      oldWidget.controller != controller;
}

class _FancyDrawerController {
  const _FancyDrawerController._(this.open, this.close, this.toggle, this.isOpen);
  final void Function() open;
  final void Function() close;
  final void Function() toggle;
  final bool Function() isOpen;
}
