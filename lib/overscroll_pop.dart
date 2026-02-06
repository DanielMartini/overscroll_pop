library overscroll_pop;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:overscroll_pop/drag_to_pop.dart';

/////////////////////////////////////////////////////////////////////////////
export 'package:overscroll_pop/drag_to_pop.dart';
//////////////////////////////////////////////////////////////////////////////

enum ScrollToPopOption { start, end, both, none }

enum DragToPopDirection {
  toTop,
  toBottom,
  toLeft,
  toRight,
  horizontal,
  vertical
}

class OverscrollPop extends StatefulWidget {
  final Widget child;
  final bool enable;
  final DragToPopDirection? dragToPopDirection;
  final ScrollToPopOption scrollToPopOption;
  final double friction;
  final BorderRadius? borderRadius;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragStop;
  final VoidCallback? onDismiss;

  const OverscrollPop({
    Key? key,
    required this.child,
    this.dragToPopDirection,
    this.scrollToPopOption = ScrollToPopOption.start,
    this.enable = true,
    this.friction = 1.0,
    this.borderRadius,
    this.onDragStart,
    this.onDragStop,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<OverscrollPop> createState() => _OverscrollPopState();
}

class _OverscrollPopState extends State<OverscrollPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late Animation<Offset> _animation;

  Offset? _dragOffset;
  Offset? _previousPosition;
  bool _isDraggingToPopStart = false;
  bool _isDraggingToPop = false;
  bool _hasTriggeredStart = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addStatusListener(_onAnimationEnd);
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.removeStatusListener(_onAnimationEnd);
    _animationController.dispose();
    super.dispose();
  }

  void _onAnimationEnd(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (_hasTriggeredStart) {
        widget.onDragStop?.call();
      }
      _animationController.reset();
      setState(() {
        _dragOffset = null;
        _previousPosition = null;
        _isDraggingToPop = false;
        _isDraggingToPopStart = false;
        _hasTriggeredStart = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget childWidget = widget.child;

    if (!widget.enable) return childWidget;

    if (widget.dragToPopDirection != null) {
      childWidget = GestureDetector(
        onHorizontalDragStart: getOnHorizontalDragStartFunction(),
        onHorizontalDragUpdate: getOnHorizontalDragUpdateFunction(),
        onHorizontalDragEnd: getOnHorizontalDragEndFunction(),
        onVerticalDragStart: getOnVerticalDragStartFunction(),
        onVerticalDragUpdate: getOnVerticalDragUpdateFunction(),
        onVerticalDragEnd: getOnVerticalDragEndFunction(),
        child: widget.child,
      );
    }

    if (widget.scrollToPopOption != ScrollToPopOption.none) {
      childWidget = NotificationListener<OverscrollNotification>(
        onNotification: _onOverScrollDragUpdate,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: childWidget,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (_, Widget? child) {
        Offset finalOffset = _dragOffset ?? const Offset(0.0, 0.0);
        if (_animation.status == AnimationStatus.forward) {
          finalOffset = _animation.value;
        }

        const maxOpacityWhenDrag = 0.75;
        final bgOpacity = finalOffset.distance == 0.0
            ? 1.0
            : math.min(
                maxOpacityWhenDrag - (finalOffset.dy / 100 / 6).abs(),
                maxOpacityWhenDrag - (finalOffset.dx / 100 / 8).abs(),
              );

        final scale = finalOffset.distance == 0.0
            ? 1.0
            : math.min(
                1.0 - (finalOffset.dy / 3000).abs(),
                1.0 - (finalOffset.dx / 1200).abs(),
              );

        final hasBorderRadius = widget.borderRadius != null;
        final opacity = bgOpacity.clamp(0.0, 1.0);

        return ColoredBox(
          color: Colors.black.withOpacity(opacity),
          child: Transform.scale(
            scale: scale,
            child: Transform.translate(
              offset: finalOffset,
              child: ClipRRect(
                borderRadius: hasBorderRadius
                    ? widget.borderRadius! * (1.0 - opacity)
                    : BorderRadius.zero,
                child: child,
              ),
            ),
          ),
        );
      },
      child: childWidget,
    );
  }

  bool _onScroll(ScrollNotification scrollNotification) {
    if (scrollNotification is ScrollEndNotification) {
      return _onOverScrollDragEnd(scrollNotification.dragDetails);
    }

    // If we have already started the pop gesture (locked), ANY scroll update
    // should drive the window, not just overscrolls. This ensures we don't
    // lose control if the framework reports a normal update during the lock.
    if (_hasTriggeredStart && scrollNotification is ScrollUpdateNotification) {
      if (scrollNotification.dragDetails != null) {
        return _setDragOffset(scrollNotification.dragDetails!);
      }
    }

    return false;
  }

  bool _onOverScrollDragEnd(DragEndDetails? dragEndDetails) {
    if (_dragOffset == null) return false;

    // Ignore phantom end notifications (null details) to prevent premature unlocking
    // while the user might still be interacting or switching directions.
    if (dragEndDetails == null) return false;

    final dragOffset = _dragOffset!;

    final screenSize = MediaQuery.of(context).size;

    // Check direction consistency
    bool isValidDirection = true;
    if (widget.scrollToPopOption == ScrollToPopOption.start &&
        dragOffset.dy < 0) {
      isValidDirection = false;
    } else if (widget.scrollToPopOption == ScrollToPopOption.end &&
        dragOffset.dy > 0) {
      isValidDirection = false;
    }

    if (isValidDirection &&
        (dragOffset.dy.abs() >= screenSize.height / 3 ||
            dragOffset.dx.abs() >= screenSize.width / 1.8)) {
      widget.onDismiss?.call();
      Navigator.of(context).pop();
      return false;
    }

    final velocity = dragEndDetails.velocity.pixelsPerSecond;
    final velocityY = velocity.dy / widget.friction / widget.friction;
    final velocityX = velocity.dx / widget.friction / widget.friction;

    // Also check direction for velocity dismiss
    bool isValidVelocityDirection = true;
    if (widget.scrollToPopOption == ScrollToPopOption.start && velocityY < 0) {
      isValidVelocityDirection = false;
    } else if (widget.scrollToPopOption == ScrollToPopOption.end &&
        velocityY > 0) {
      isValidVelocityDirection = false;
    }

    if (isValidVelocityDirection &&
        (velocityY.abs() > 150.0 || velocityX.abs() > 200.0)) {
      widget.onDismiss?.call();
      Navigator.of(context).pop();
      return false;
    }

    setState(() {
      _animation = Tween<Offset>(
        begin: Offset(dragOffset.dx, dragOffset.dy),
        end: const Offset(0.0, 0.0),
      ).animate(_animationController);
    });

    _animationController.forward(from: 0.0);
    return false;
  }

  bool _onScrollDragUpdate(DragUpdateDetails? dragUpdateDetails) {
    if (_dragOffset == null) return false;
    if (dragUpdateDetails == null) return false;

    if (_previousPosition == null) {
      _previousPosition = dragUpdateDetails.globalPosition;
      return false;
    }

    return _setDragOffset(dragUpdateDetails);
  }

  bool _onOverScrollDragUpdate(OverscrollNotification overscrollNotification) {
    final scrollToPopOption = widget.scrollToPopOption;

    // Allow updates IF we have already triggered start, enabling reverse drag (back to origin).
    if (!_hasTriggeredStart) {
      if (scrollToPopOption == ScrollToPopOption.start &&
          overscrollNotification.overscroll > 0) return false;

      if (scrollToPopOption == ScrollToPopOption.end &&
          overscrollNotification.overscroll < 0) return false;
    }

    final dragUpdateDetails = overscrollNotification.dragDetails;
    if (dragUpdateDetails == null) return false;
    return _setDragOffset(dragUpdateDetails);
  }

  bool _setDragOffset(DragUpdateDetails dragUpdateDetails) {
    if (_previousPosition == null) {
      _previousPosition = dragUpdateDetails.globalPosition;
      return false;
    }

    if (_dragOffset == null && !_hasTriggeredStart) {
      widget.onDragStart?.call();
      _hasTriggeredStart = true;
    }

    // Safety check
    if (!_hasTriggeredStart && _dragOffset == null) {
      _previousPosition = dragUpdateDetails.globalPosition;
      return false;
    }

    final currentPosition = dragUpdateDetails.globalPosition;
    final previousPosition = _previousPosition!;

    final newX = (_dragOffset?.dx ?? 0.0) +
        (currentPosition.dx - previousPosition.dx) / widget.friction;
    final newY = (_dragOffset?.dy ?? 0.0) +
        (currentPosition.dy - previousPosition.dy) / widget.friction;
    _previousPosition = currentPosition;

    // Auto-reset removed to maintain lock during reverse drag.
    // The window will visually rubber-band, but the inner scroll will remain locked.

    setState(() {
      _dragOffset = Offset(newX, newY);
    });
    return false;
  }

  bool _onDragUpdate(DragUpdateDetails dragUpdateDetails) {
    if (!_isDraggingToPop) return false;
    final previousPosition = _previousPosition!;

    if (_isDraggingToPopStart) {
      _isDraggingToPopStart = false;

      final currentPosition = dragUpdateDetails.globalPosition;
      final dragToPopDirection = widget.dragToPopDirection;

      if (dragToPopDirection == DragToPopDirection.toRight &&
          previousPosition.dx > currentPosition.dx) {
        _isDraggingToPop = false;
        return false;
      }

      if (dragToPopDirection == DragToPopDirection.toLeft &&
          previousPosition.dx < currentPosition.dx) {
        _isDraggingToPop = false;
        return false;
      }

      if (dragToPopDirection == DragToPopDirection.toTop &&
          previousPosition.dy < currentPosition.dy) {
        _isDraggingToPop = false;
        return false;
      }

      if (dragToPopDirection == DragToPopDirection.toBottom &&
          previousPosition.dy > currentPosition.dy) {
        _isDraggingToPop = false;
        return false;
      }
    }

    return _setDragOffset(dragUpdateDetails);
  }

  /////////////////////////////////////////////////////////////////////////////

  GestureDragStartCallback? getOnHorizontalDragStartFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.horizontal:
      case DragToPopDirection.toLeft:
      case DragToPopDirection.toRight:
        return (DragStartDetails dragDetails) {
          if (!_hasTriggeredStart) {
            widget.onDragStart?.call();
            _hasTriggeredStart = true;
          }
          _isDraggingToPopStart = true;
          _isDraggingToPop = true;
          _previousPosition = dragDetails.globalPosition;
        };
      default:
        return null;
    }
  }

  GestureDragUpdateCallback? getOnHorizontalDragUpdateFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.horizontal:
      case DragToPopDirection.toLeft:
      case DragToPopDirection.toRight:
        return _onDragUpdate;
      default:
        return null;
    }
  }

  GestureDragEndCallback? getOnHorizontalDragEndFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.horizontal:
      case DragToPopDirection.toLeft:
      case DragToPopDirection.toRight:
        return _onOverScrollDragEnd;
      default:
        return null;
    }
  }

  ////////////////////////

  GestureDragStartCallback? getOnVerticalDragStartFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.vertical:
      case DragToPopDirection.toTop:
      case DragToPopDirection.toBottom:
        return (DragStartDetails dragDetails) {
          if (!_hasTriggeredStart) {
            widget.onDragStart?.call();
            _hasTriggeredStart = true;
          }
          _isDraggingToPopStart = true;
          _isDraggingToPop = true;
          _previousPosition = dragDetails.globalPosition;
        };
      default:
        return null;
    }
  }

  GestureDragUpdateCallback? getOnVerticalDragUpdateFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.vertical:
      case DragToPopDirection.toTop:
      case DragToPopDirection.toBottom:
        return _onDragUpdate;
      default:
        return null;
    }
  }

  GestureDragEndCallback? getOnVerticalDragEndFunction() {
    switch (widget.dragToPopDirection) {
      case DragToPopDirection.vertical:
      case DragToPopDirection.toTop:
      case DragToPopDirection.toBottom:
        return _onOverScrollDragEnd;
      default:
        return null;
    }
  }
}

Future<dynamic> pushOverscrollRoute({
  required BuildContext context,
  required Widget child,
  BorderRadius? borderRadius,
  ScrollToPopOption scrollToPopOption = ScrollToPopOption.start,
  DragToPopDirection? dragToPopDirection,
  bool fullscreenDialog = false,
  RouteSettings? settings,
  Duration transitionDuration = const Duration(milliseconds: 250),
  Duration reverseTransitionDuration = const Duration(milliseconds: 250),
  Color? barrierColor,
  String? barrierLabel,
  bool barrierDismissible = false,
  bool maintainState = true,
  VoidCallback? onDragStart,
  VoidCallback? onDragStop,
  VoidCallback? onDismiss,
}) async =>
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: transitionDuration,
        reverseTransitionDuration: reverseTransitionDuration,
        fullscreenDialog: fullscreenDialog,
        opaque: false,
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          _,
          Widget child,
        ) {
          if (animation.status == AnimationStatus.reverse ||
              animation.status == AnimationStatus.dismissed) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInCirc,
              ),
              child: child,
            );
          }

          return FadeTransition(opacity: animation, child: child);
        },
        pageBuilder: (_, __, ___) => OverscrollPop(
          dragToPopDirection: dragToPopDirection,
          scrollToPopOption: scrollToPopOption,
          borderRadius: borderRadius,
          onDragStart: onDragStart,
          onDragStop: onDragStop,
          onDismiss: onDismiss,
          child: child,
        ),
        maintainState: maintainState,
        barrierColor: barrierColor,
        barrierLabel: barrierLabel,
        barrierDismissible: barrierDismissible,
        settings: settings,
      ),
    );

Future<dynamic> pushDragToPopRoute({
  required BuildContext context,
  required Widget child,
  bool fullscreenDialog = false,
  RouteSettings? settings,
  Duration transitionDuration = const Duration(milliseconds: 250),
  Duration reverseTransitionDuration = const Duration(milliseconds: 250),
  Color? barrierColor,
  String? barrierLabel,
  bool barrierDismissible = false,
  bool maintainState = true,
}) async =>
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: transitionDuration,
        reverseTransitionDuration: reverseTransitionDuration,
        fullscreenDialog: fullscreenDialog,
        opaque: false,
        transitionsBuilder: (
          BuildContext context,
          Animation<double> animation,
          _,
          Widget child,
        ) {
          if (animation.status == AnimationStatus.reverse ||
              animation.status == AnimationStatus.dismissed) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInExpo,
              ),
              child: child,
            );
          }

          return FadeTransition(opacity: animation, child: child);
        },
        pageBuilder: (_, __, ___) => DragToPop(child: child),
        maintainState: maintainState,
        barrierColor: barrierColor,
        barrierLabel: barrierLabel,
        barrierDismissible: barrierDismissible,
        settings: settings,
      ),
    );
