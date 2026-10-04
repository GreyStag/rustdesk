import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import 'custom_settings.dart';
import 'gestures/tap_zoom_region.dart';
import 'helper/helper_client.dart';
import 'widgets/custom_toolbar.dart';
import 'widgets/special_keys_stack.dart';
import 'widgets/staging_box.dart';

class CustomRemoteOverlay extends StatefulWidget {
  final FFI ffi;
  final String id;
  final Widget body;
  const CustomRemoteOverlay({
    Key? key,
    required this.ffi,
    required this.id,
    required this.body,
  }) : super(key: key);

  static final _active = <String, _CustomRemoteOverlayState>{};

  static Future<void> beforeClose(FFI ffi) async {
    final s = _active[ffi.id];
    if (s != null) await s._prepareClose();
  }

  @override
  State<CustomRemoteOverlay> createState() => _CustomRemoteOverlayState();
}

class _CustomRemoteOverlayState extends State<CustomRemoteOverlay> {
  final dragLatched = false.obs;
  final _regionKey = GlobalKey();
  final _debug = ValueNotifier<String>('debug on: waiting for a touch');
  bool _toolbarOpen = false;
  bool _keyboardOpen = false;
  bool _sessionAnnounced = false;
  bool _closing = false;
  String? _lidBanner;
  Timer? _idle;
  Timer? _focusTimer;
  Worker? _lidWorker;
  Worker? _focusWorker;
  Worker? _onlineWorker;
  Worker? _alertWorker;
  Worker? _privacyWorker;

  void _onFocusChanged(bool? text) {
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !CustomSettings.autoKeyboard || text == null) return;
      if (text == _keyboardOpen) return;
      setState(() {
        _keyboardOpen = text;
        if (text) _toolbarOpen = false;
      });
    });
  }

  FFI get ffi => widget.ffi;

  @override
  void initState() {
    super.initState();
    CustomRemoteOverlay._active[widget.id] = this;
    HelperClient.instance.start();
    ffi.imageModel.addCallbackOnFirstImage((_) => _onFirstImage());
    _focusWorker =
        ever<bool?>(HelperClient.instance.focusText, _onFocusChanged);
    _onlineWorker = ever<bool>(HelperClient.instance.helperOnline, (online) {
      if (online && _sessionAnnounced && !_closing) {
        HelperClient.instance.session(true);
      }
    });
    _lidWorker = ever<LidEvent?>(HelperClient.instance.lidEvent, (e) {
      if (e == null || !mounted) return;
      final hm = TimeOfDay.fromDateTime(e.at).format(context);
      setState(() => _lidBanner = 'Laptop lid opened at $hm (${e.action})');
      HapticFeedback.vibrate();
    });
    _alertWorker = ever<LidEvent?>(HelperClient.instance.alert, (e) {
      if (e == null || !mounted) return;
      final hm = TimeOfDay.fromDateTime(e.at).format(context);
      setState(() => _lidBanner = '$hm: ${e.action}');
      HapticFeedback.vibrate();
    });
    _privacyWorker = ever<LidEvent?>(HelperClient.instance.privacyRequest, (e) {
      if (e == null || !mounted || _closing) return;
      setPrivacyMode(ffi, widget.id, e.action == 'on');
    });
    _resetIdle();
  }

  @override
  void dispose() {
    CustomRemoteOverlay._active.remove(widget.id);
    _idle?.cancel();
    _lidWorker?.dispose();
    _focusWorker?.dispose();
    _onlineWorker?.dispose();
    _alertWorker?.dispose();
    _privacyWorker?.dispose();
    _focusTimer?.cancel();
    if (!_closing && _sessionAnnounced) {
      HelperClient.instance.session(false);
    }
    super.dispose();
  }

  void _onFirstImage() {
    if (!mounted) return;
    _sessionAnnounced = true;
    HelperClient.instance.session(true);
    _applyAutoLockOption();
    if (CustomSettings.privacyOnConnect) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_closing) setPrivacyMode(ffi, widget.id, true);
      });
    }
  }

  void _applyAutoLockOption() {
    final want = CustomSettings.autoLockOnDisconnect;
    final cur = bind.sessionGetToggleOptionSync(
      sessionId: ffi.sessionId,
      arg: 'lock-after-session-end',
    );
    if (cur != want) {
      bind.sessionToggleOption(
        sessionId: ffi.sessionId,
        value: 'lock-after-session-end',
      );
    }
    final after = bind.sessionGetToggleOptionSync(
      sessionId: ffi.sessionId,
      arg: 'lock-after-session-end',
    );
    _debug.value = 'lock-after-session-end: was $cur, wanted $want, now $after';
  }

  void _resetIdle() {
    _idle?.cancel();
    final minutes = CustomSettings.idleTimeoutMinutes;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), _onIdle);
  }

  Future<void> _onIdle() async {
    if (!mounted || _closing) return;
    if (CustomSettings.autoLockOnDisconnect) {
      bind.sessionLockScreen(sessionId: ffi.sessionId);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _disconnect();
  }

  Future<void> _prepareClose() async {
    if (_closing) return;
    _closing = true;
    _idle?.cancel();
    if (_sessionAnnounced) await HelperClient.instance.session(false);
  }

  Future<void> _disconnect() async {
    await _prepareClose();
    closeConnection();
  }

  void _fitView() {
    final s = _regionKey.currentState;
    if (s is! TapZoomRegionController) return;
    (s as TapZoomRegionController).fitView();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdle(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TapZoomRegion(
            key: _regionKey,
            ffi: ffi,
            dragLatched: dragLatched,
            onActivity: _resetIdle,
            debug: CustomSettings.debugOverlay ? _debug : null,
            child: widget.body,
          ),
          if (CustomSettings.debugOverlay)
            Positioned(
              top: 4,
              left: 4,
              right: 4,
              child: IgnorePointer(
                child: ValueListenableBuilder<String>(
                  valueListenable: _debug,
                  builder: (_, text, __) => Container(
                    color: const Color(0xAA000000),
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (CustomSettings.connectionIndicator) ConnectionIndicator(ffi: ffi),
          if (CustomSettings.privacyControl)
            PrivacyBlankButton(ffi: ffi, id: widget.id),
          if (!_keyboardOpen)
            SpecialKeysStack(ffi: ffi, dragLatched: dragLatched),
          if (_keyboardOpen)
            StagingBox(
              ffi: ffi,
              onClose: () => setState(() => _keyboardOpen = false),
            ),
          if (!_keyboardOpen)
            CustomToolbar(
              ffi: ffi,
              id: widget.id,
              open: _toolbarOpen,
              keyboardOpen: _keyboardOpen,
              onToggleOpen: () => setState(() => _toolbarOpen = !_toolbarOpen),
              onToggleKeyboard: () => setState(() {
                _keyboardOpen = !_keyboardOpen;
                _toolbarOpen = false;
              }),
              onDisconnect: _disconnect,
              onFitView: _fitView,
              onSettingsChanged: () => setState(() {}),
            ),
          if (_lidBanner != null)
            Positioned(
              top: 56,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.laptop, color: Colors.white),
                  title: Text(
                    _lidBanner!,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _lidBanner = null),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
