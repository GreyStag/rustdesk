import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/input_model.dart';
import '../../models/model.dart';
import '../custom_settings.dart';

class TapZoomRegion extends StatefulWidget {
  final FFI ffi;
  final Widget child;
  final RxBool dragLatched;
  final VoidCallback? onActivity;
  final ValueNotifier<String>? debug;
  const TapZoomRegion({
    Key? key,
    required this.ffi,
    required this.child,
    required this.dragLatched,
    this.onActivity,
    this.debug,
  }) : super(key: key);

  @override
  State<TapZoomRegion> createState() => _TapZoomRegionState();
}

abstract class TapZoomRegionController {
  void fitView();
}

class _TapZoomRegionState extends State<TapZoomRegion>
    with SingleTickerProviderStateMixin
    implements TapZoomRegionController {
  static const _slop = 12.0;
  static const _twoFingerTapMs = 300;
  static const _scrollStepPx = 28.0;

  final _pointers = <int, Offset>{};

  int? _primary;
  Offset? _downPos;
  Offset? _lastPos;
  bool _moved = false;
  bool _holding = false;
  bool _dragging = false;
  bool _scrolling = false;
  double _scrollAccum = 0;
  Timer? _holdTimer;

  Timer? _tapTimer;
  int _tapCount = 0;
  Offset? _tapPos;

  bool _twoFingerActive = false;
  bool _twoFingerMoved = false;
  DateTime? _twoDownAt;
  double _pinchLastDist = 0;
  Offset _pinchLastFocal = Offset.zero;
  bool _ignoreUntilAllUp = false;

  late final AnimationController _anim;
  double _animFrom = 1;
  double _animTo = 1;
  Offset _animFocal = Offset.zero;
  bool _clampScheduled = false;
  String _lastImageDims = '';

  void _onImageFrame() {
    final img = image.image;
    final dims = img == null ? '' : '${img.width}x${img.height}';
    if (dims != _lastImageDims) _scheduleClamp();
  }

  CanvasModel get canvas => widget.ffi.canvasModel;
  ImageModel get image => widget.ffi.imageModel;
  CursorModel get cursor => widget.ffi.cursorModel;
  InputModel get input => widget.ffi.inputModel;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addListener(_onAnimTick);
    canvas.addListener(_scheduleClamp);
    image.addListener(_onImageFrame);
  }

  @override
  void dispose() {
    canvas.removeListener(_scheduleClamp);
    image.removeListener(_onImageFrame);
    _holdTimer?.cancel();
    _tapTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  bool _isTouch(PointerEvent e) =>
      e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;

  double? _minScale() {
    final img = image.image;
    if (img == null) return null;
    final size = canvas.getSize();
    if (size.width <= 0 || size.height <= 0) return null;
    final xs = size.width / img.width;
    final ys = size.height / img.height;
    final mode = CustomSettings.minimumView;
    final fit = mode == 'fit' || (mode == 'auto' && size.height > size.width);
    return fit ? min(xs, ys) : max(xs, ys);
  }

  void _scheduleClamp() {
    if (_clampScheduled) return;
    _clampScheduled = true;
    scheduleMicrotask(() {
      _clampScheduled = false;
      if (mounted) _clamp();
    });
  }

  void _clamp() {
    final img = image.image;
    if (img == null) return;
    final size = canvas.getSize();
    if (size.width <= 0 || size.height <= 0) return;
    final minS = _minScale();
    final dims = '${img.width}x${img.height}';
    final newDisplay = dims != _lastImageDims;
    _lastImageDims = dims;
    if (minS != null &&
        (newDisplay || canvas.scale < minS - 1e-6) &&
        (canvas.scale - minS).abs() > 1e-6) {
      canvas.updateScale(
        minS / canvas.scale,
        Offset(size.width / 2, size.height / 2),
      );
    }
    final s = canvas.scale;
    final w = img.width * s;
    final h = img.height * s;
    final adjust = canvas.getAdjustY();

    double targetX;
    if (w <= size.width) {
      targetX = (size.width - w) / 2;
    } else {
      targetX = canvas.x.clamp(size.width - w, 0.0);
    }
    final top = canvas.y + adjust;
    double targetTop;
    if (h <= size.height) {
      targetTop = (size.height - h) / 2;
    } else {
      targetTop = top.clamp(size.height - h, 0.0);
    }
    final targetY = targetTop - adjust;
    if ((targetX - canvas.x).abs() > 0.01) canvas.panX(targetX - canvas.x);
    if ((targetY - canvas.y).abs() > 0.01) canvas.panY(targetY - canvas.y);
  }

  void _zoomAt(Offset focal, double factor) {
    if (image.image == null) return;
    final minS = _minScale() ?? canvas.scale;
    final maxS = max(image.maxScale, minS);
    _animFrom = canvas.scale;
    _animTo = (_animFrom * factor).clamp(minS, maxS);
    _animFocal = focal;
    _log(
        'zoom ${_animFrom.toStringAsFixed(2)} to ${_animTo.toStringAsFixed(2)}');
    _anim.forward(from: 0);
  }

  void _onAnimTick() {
    final t = Curves.easeOut.transform(_anim.value);
    final target = _animFrom + (_animTo - _animFrom) * t;
    final cur = canvas.scale;
    if (cur <= 0) return;
    canvas.updateScale(target / cur, _animFocal);
    _clamp();
  }

  @override
  void fitView() {
    final minS = _minScale();
    if (minS == null) return;
    _animFrom = canvas.scale;
    _animTo = minS;
    final size = canvas.getSize();
    _animFocal = Offset(size.width / 2, size.height / 2);
    _anim.forward(from: 0);
  }

  void _log(String msg) {
    final d = widget.debug;
    if (d == null) return;
    final img = image.image;
    final size = canvas.getSize();
    final minS = _minScale();
    d.value =
        '$msg | img ${img?.width}x${img?.height} view ${size.width.round()}x${size.height.round()} scale ${canvas.scale.toStringAsFixed(2)} min ${minS?.toStringAsFixed(2)} kb ${input.keyboardPerm}';
  }

  Future<bool> _placeCursor(Offset pos) async {
    final remote = cursor.getRemotePosInRect(pos);
    if (remote == null) return false;
    cursor.moveLocal(pos.dx, pos.dy, adjust: canvas.getAdjustY());
    await cursor.syncCursorPosition();
    return true;
  }

  Future<void> _click(Offset pos, MouseButtons button) async {
    final moved = await _placeCursor(pos);
    _log(
        '${button.name} click at ${pos.dx.round()},${pos.dy.round()} inRect=$moved');
    if (!moved) return;
    await input.tap(button);
  }

  void _resolveTaps() {
    final n = _tapCount;
    final pos = _tapPos;
    _tapCount = 0;
    _tapPos = null;
    if (pos == null) return;
    _log('tap x$n');
    if (n == 1) {
      _click(pos, MouseButtons.left);
    } else if (n == 2) {
      _zoomAt(pos, CustomSettings.zoomInFactor);
    } else {
      _zoomAt(pos, CustomSettings.zoomOutFactor);
    }
  }

  void _registerTap(Offset pos) {
    _tapCount++;
    _tapPos = pos;
    _tapTimer?.cancel();
    _tapTimer = Timer(
      Duration(milliseconds: CustomSettings.tapTimeoutMs),
      _resolveTaps,
    );
  }

  void _resetSingle() {
    _holdTimer?.cancel();
    _primary = null;
    _downPos = null;
    _lastPos = null;
    _moved = false;
    _holding = false;
    _dragging = false;
    _scrolling = false;
    _scrollAccum = 0;
  }

  Future<void> _beginHold() async {
    if (_primary == null || _moved || _holding) return;
    _holding = true;
    _tapTimer?.cancel();
    _tapCount = 0;
    HapticFeedback.selectionClick();
    final mouseDrag = CustomSettings.holdDragMouse != widget.dragLatched.value;
    if (mouseDrag && _downPos != null) {
      final moved = await _placeCursor(_downPos!);
      if (moved && _holding) {
        _dragging = true;
        await input.tapDown(MouseButtons.left);
      }
    }
  }

  Future<void> _doubleClick(Offset pos) async {
    final moved = await _placeCursor(pos);
    _log('double click at ${pos.dx.round()},${pos.dy.round()} inRect=$moved');
    if (!moved) return;
    await input.tap(MouseButtons.left);
    await input.tap(MouseButtons.left);
  }

  void _onDown(PointerDownEvent e) {
    if (!_isTouch(e)) {
      _log('ignored pointer kind ${e.kind.name}');
      return;
    }
    _log('down ${e.kind.name} fingers ${_pointers.length + 1}');
    widget.onActivity?.call();
    _pointers[e.pointer] = e.localPosition;
    if (_ignoreUntilAllUp) return;

    if (_pointers.length == 1) {
      _resetSingle();
      _primary = e.pointer;
      _downPos = e.localPosition;
      _lastPos = e.localPosition;
      _holdTimer = Timer(
        Duration(milliseconds: CustomSettings.holdDelayMs),
        _beginHold,
      );
      return;
    }
    if (_pointers.length == 2) {
      if (_dragging) input.tapUp(MouseButtons.left);
      _resetSingle();
      _tapTimer?.cancel();
      _tapCount = 0;
      _twoFingerActive = true;
      _twoFingerMoved = false;
      _twoDownAt = DateTime.now();
      final pts = _pointers.values.toList();
      _pinchLastDist = (pts[0] - pts[1]).distance;
      _pinchLastFocal = (pts[0] + pts[1]) / 2;
      return;
    }
    _ignoreUntilAllUp = true;
    _twoFingerActive = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_ignoreUntilAllUp) return;

    if (_twoFingerActive && _pointers.length == 2) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (!_twoFingerMoved &&
          ((dist - _pinchLastDist).abs() > _slop ||
              (focal - _pinchLastFocal).distance > _slop)) {
        _twoFingerMoved = true;
      }
      if (_twoFingerMoved) {
        if (_pinchLastDist > 0 && dist > 0) {
          canvas.updateScale(dist / _pinchLastDist, focal);
        }
        final d = focal - _pinchLastFocal;
        canvas.panX(d.dx);
        canvas.panY(d.dy);
        _pinchLastDist = dist;
        _pinchLastFocal = focal;
        _clamp();
      }
      return;
    }

    if (e.pointer != _primary || _downPos == null || _lastPos == null) return;
    final pos = e.localPosition;
    final delta = pos - _lastPos!;
    _lastPos = pos;
    if (!_moved && (pos - _downPos!).distance > _slop) {
      _moved = true;
      if (!_holding) {
        _holdTimer?.cancel();
        _scrolling = true;
        _tapTimer?.cancel();
        _tapCount = 0;
      }
    }
    if (_holding) {
      if (_dragging) {
        cursor.updatePan(delta, pos, true);
      } else {
        canvas.panX(delta.dx);
        canvas.panY(delta.dy);
        _clamp();
      }
      return;
    }
    if (_scrolling) {
      _scrollAccum += delta.dy;
      final step = _scrollStepPx / max(CustomSettings.scrollSensitivity, 0.1);
      while (_scrollAccum.abs() >= step) {
        input.scroll(_scrollAccum > 0 ? 1 : -1);
        _scrollAccum -= _scrollAccum > 0 ? step : -step;
      }
    }
  }

  void _onUp(PointerEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final wasTwo = _pointers.length == 2;
    _pointers.remove(e.pointer);

    if (_ignoreUntilAllUp) {
      if (_pointers.isEmpty) _ignoreUntilAllUp = false;
      return;
    }

    if (_twoFingerActive && wasTwo) {
      _twoFingerActive = false;
      final quick = _twoDownAt != null &&
          DateTime.now().difference(_twoDownAt!).inMilliseconds <
              _twoFingerTapMs;
      if (!_twoFingerMoved && quick && e is! PointerCancelEvent) {
        _click(e.localPosition, MouseButtons.right);
      }
      _ignoreUntilAllUp = _pointers.isNotEmpty;
      return;
    }

    if (e.pointer == _primary) {
      final tap = !_moved && !_holding && e is! PointerCancelEvent;
      final holdRelease = _holding && !_moved && e is! PointerCancelEvent;
      if (_dragging) input.tapUp(MouseButtons.left);
      final pos = _downPos;
      _resetSingle();
      if (tap && pos != null) _registerTap(pos);
      if (holdRelease && pos != null) _doubleClick(pos);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
