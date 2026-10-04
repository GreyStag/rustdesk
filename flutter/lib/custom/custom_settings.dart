import 'dart:convert';

import 'package:flutter_hbb/models/platform_model.dart';

class CustomSettings {
  CustomSettings._();

  static const prefix = 'custom-';

  static String _raw(String key) => bind.mainGetLocalOption(key: '$prefix$key');
  static Future<void> _write(String key, String value) =>
      bind.mainSetLocalOption(key: '$prefix$key', value: value);

  static bool _bool(String key, bool fallback) {
    final v = _raw(key);
    if (v.isEmpty) return fallback;
    return v == 'Y';
  }

  static Future<void> _setBool(String key, bool value) =>
      _write(key, value ? 'Y' : 'N');
  static double _double(String key, double fallback) =>
      double.tryParse(_raw(key)) ?? fallback;
  static int _int(String key, int fallback) =>
      int.tryParse(_raw(key)) ?? fallback;
  static String _string(String key, String fallback) {
    final v = _raw(key);
    return v.isEmpty ? fallback : v;
  }

  static bool get customUi => _bool('ui', true);
  static Future<void> setCustomUi(bool v) => _setBool('ui', v);

  static double get zoomInFactor => _double('zoom-in', 2.0);
  static Future<void> setZoomInFactor(double v) => _write('zoom-in', '$v');
  static double get zoomOutFactor => _double('zoom-out', 0.5);
  static Future<void> setZoomOutFactor(double v) => _write('zoom-out', '$v');

  static String get minimumView => _string('min-view', 'auto');
  static Future<void> setMinimumView(String v) => _write('min-view', v);

  static int get holdDelayMs => _int('hold-ms', 500);
  static bool get holdDragMouse => _bool('hold-mouse', true);
  static Future<void> setHoldDragMouse(bool v) => _setBool('hold-mouse', v);
  static Future<void> setHoldDelayMs(int v) => _write('hold-ms', '$v');
  static int get tapTimeoutMs => _int('tap-ms', 300);
  static bool get debugOverlay => _bool('debug', false);
  static Future<void> setDebugOverlay(bool v) => _setBool('debug', v);
  static Future<void> setTapTimeoutMs(int v) => _write('tap-ms', '$v');
  static double get scrollSensitivity => _double('scroll', 1.0);
  static Future<void> setScrollSensitivity(double v) => _write('scroll', '$v');

  static double get keyboardOpacity => _double('kb-opacity', 0.85);
  static Future<void> setKeyboardOpacity(double v) =>
      _write('kb-opacity', '$v');
  static bool get enterAfterSend => _bool('enter-after-send', true);
  static Future<void> setEnterAfterSend(bool v) =>
      _setBool('enter-after-send', v);
  static bool get autoKeyboard => _bool('auto-keyboard', true);
  static Future<void> setAutoKeyboard(bool v) => _setBool('auto-keyboard', v);
  static bool get autocorrect => _bool('autocorrect', false);
  static Future<void> setAutocorrect(bool v) => _setBool('autocorrect', v);
  static bool get keepTextAfterSend => _bool('keep-text', false);
  static Future<void> setKeepTextAfterSend(bool v) => _setBool('keep-text', v);

  static const defaultSpecialKeys = [
    'Ctrl',
    'Alt',
    'Shift',
    'Win',
    'Tab',
    'PrtSc',
    'Esc',
    'RClick',
    'Drag',
  ];
  static List<String> get specialKeys {
    final v = _raw('special-keys');
    if (v.isEmpty) return List.of(defaultSpecialKeys);
    try {
      return (jsonDecode(v) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return List.of(defaultSpecialKeys);
    }
  }

  static Future<void> setSpecialKeys(List<String> keys) =>
      _write('special-keys', jsonEncode(keys));
  static bool get showSpecialKeys => _bool('show-keys', true);
  static Future<void> setShowSpecialKeys(bool v) => _setBool('show-keys', v);
  static bool get oneShotModifiers => _bool('one-shot', false);
  static Future<void> setOneShotModifiers(bool v) => _setBool('one-shot', v);

  static bool get connectionIndicator => _bool('conn-indicator', false);
  static Future<void> setConnectionIndicator(bool v) =>
      _setBool('conn-indicator', v);
  static bool get privacyOnConnect => _bool('privacy-on-connect', false);
  static Future<void> setPrivacyOnConnect(bool v) =>
      _setBool('privacy-on-connect', v);
  static String get privacyImpl =>
      _string('privacy-impl', 'privacy_mode_impl_mag');
  static Future<void> setPrivacyImpl(String v) => _write('privacy-impl', v);
  static bool get privacyControl => _bool('privacy-control', false);
  static Future<void> setPrivacyControl(bool v) =>
      _setBool('privacy-control', v);

  static String get pinSalt => _raw('pin-salt');
  static Future<void> setPinSalt(String v) => _write('pin-salt', v);
  static String get pinHash => _raw('pin-hash');
  static Future<void> setPinHash(String v) => _write('pin-hash', v);
  static bool get pinSet => pinHash.isNotEmpty;
  static bool get biometric => _bool('biometric', true);
  static Future<void> setBiometric(bool v) => _setBool('biometric', v);
  static bool get autoLockOnDisconnect => _bool('auto-lock', false);
  static Future<void> setAutoLockOnDisconnect(bool v) =>
      _setBool('auto-lock', v);
  static int get idleTimeoutMinutes => _int('idle-min', 0);
  static Future<void> setIdleTimeoutMinutes(int v) => _write('idle-min', '$v');
  static String get oneTapPeerId => _raw('one-tap-id');
  static Future<void> setOneTapPeerId(String v) => _write('one-tap-id', v);

  static bool get helperEnabled => _bool('helper', false);
  static Future<void> setHelperEnabled(bool v) => _setBool('helper', v);
  static String get helperHost => _raw('helper-host');
  static Future<void> setHelperHost(String v) => _write('helper-host', v);
  static int get helperPort => _int('helper-port', 8765);
  static Future<void> setHelperPort(int v) => _write('helper-port', '$v');
  static String get helperToken => _raw('helper-token');
  static Future<void> setHelperToken(String v) => _write('helper-token', v);
  static String get helperCertSha256 => _raw('helper-cert');
  static Future<void> setHelperCertSha256(String v) => _write('helper-cert', v);
}
