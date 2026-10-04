import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../custom_settings.dart';

class HelperException implements Exception {
  final String message;
  HelperException(this.message);
  @override
  String toString() => message;
}

class RdpEntry {
  final String name;
  final String file;
  final String modified;
  RdpEntry.fromJson(Map m)
      : name = '${m['name'] ?? ''}',
        file = '${m['file'] ?? ''}',
        modified = '${m['modified'] ?? ''}';
}

class LidEvent {
  final bool open;
  final String action;
  final DateTime at;
  LidEvent(this.open, this.action) : at = DateTime.now();
}

class HelperClient {
  HelperClient._();
  static final HelperClient instance = HelperClient._();

  final relayConnected = false.obs;
  final helperOnline = false.obs;
  final lastError = ''.obs;
  final lidEvent = Rxn<LidEvent>();
  final focusText = Rxn<bool>();
  final alert = Rxn<LidEvent>();
  final privacyRequest = Rxn<LidEvent>();

  SecureSocket? _socket;
  StreamSubscription<String>? _sub;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  int _seq = 0;
  bool _wanted = false;
  int _backoff = 2;
  Timer? _reconnect;
  Timer? _ping;

  bool get configured =>
      CustomSettings.helperEnabled &&
      CustomSettings.helperHost.isNotEmpty &&
      CustomSettings.helperToken.isNotEmpty;

  void start() {
    if (!configured || _wanted) return;
    _wanted = true;
    _connect();
  }

  Future<void> stop() async {
    _wanted = false;
    _reconnect?.cancel();
    _ping?.cancel();
    await _close();
    relayConnected.value = false;
    helperOnline.value = false;
  }

  Future<void> restart() async {
    await stop();
    start();
  }

  Future<void> _connect() async {
    if (!_wanted) return;
    final expected = CustomSettings.helperCertSha256
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '')
        .toUpperCase();
    try {
      final socket = await SecureSocket.connect(
        CustomSettings.helperHost,
        CustomSettings.helperPort,
        timeout: const Duration(seconds: 8),
        onBadCertificate: (cert) {
          if (expected.isEmpty) return false;
          final fp = sha256.convert(cert.der).toString().toUpperCase();
          return fp == expected;
        },
      );
      _socket = socket;
      _sub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (e) => _lost('$e'),
            onDone: () => _lost('closed'),
          );
      _send({
        't': 'hello',
        'role': 'phone',
        'token': CustomSettings.helperToken,
        'name': 'phone',
      });
      relayConnected.value = true;
      lastError.value = '';
      _backoff = 2;
      _ping?.cancel();
      _ping = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _send({'t': 'ping'}),
      );
    } catch (e) {
      _lost('$e');
    }
  }

  Future<void> _close() async {
    _ping?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(HelperException('Disconnected'));
    }
    _pending.clear();
  }

  void _lost(String why) {
    debugPrint('helper channel lost: $why');
    lastError.value = why;
    relayConnected.value = false;
    helperOnline.value = false;
    _close();
    if (!_wanted) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _backoff), _connect);
    _backoff = (_backoff * 2).clamp(2, 60).toInt();
  }

  void _send(Map<String, dynamic> m) {
    final s = _socket;
    if (s == null) return;
    try {
      s.write('${jsonEncode(m)}\n');
    } catch (e) {
      _lost('$e');
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'welcome':
        helperOnline.value = m['peer'] == true;
        break;
      case 'peer':
        helperOnline.value = m['online'] == true;
        break;
      case 'res':
        final c = _pending.remove('${m['id']}');
        if (c != null && !c.isCompleted) c.complete(m);
        break;
      case 'evt':
        if (m['name'] == 'lid') {
          lidEvent.value = LidEvent(m['open'] == true, '${m['action'] ?? ''}');
        } else if (m['name'] == 'alert') {
          alert.value = LidEvent(true, '${m['text'] ?? ''}');
        } else if (m['name'] == 'privacy') {
          privacyRequest.value = LidEvent(true, '${m['text'] ?? ''}');
        } else if (m['name'] == 'focus') {
          focusText.trigger(m['text'] == true);
        }
        break;
      case 'ping':
        _send({'t': 'pong'});
        break;
      case 'error':
        lastError.value = '${m['message'] ?? 'relay error'}';
        break;
      default:
        break;
    }
  }

  Future<Map<String, dynamic>> request(
    String cmd, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (!relayConnected.value) {
      throw HelperException(
        lastError.value.isEmpty
            ? 'Not connected to the relay'
            : lastError.value,
      );
    }
    final id = '${++_seq}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _send({'t': 'req', 'id': id, 'cmd': cmd, ...args});
    final res = await c.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw HelperException('The helper did not answer');
      },
    );
    if (res['ok'] == true) {
      return ((res['data'] as Map?) ?? {}).cast<String, dynamic>();
    }
    throw HelperException('${res['error'] ?? 'Helper error'}');
  }

  Future<Map<String, dynamic>> ping() => request('ping');

  Future<List<RdpEntry>> rdpList() async {
    final d = await request('rdp.list');
    return ((d['items'] as List?) ?? [])
        .map((e) => RdpEntry.fromJson(e as Map))
        .toList();
  }

  Future<void> launchRdp(String name) => request('rdp.launch', {'name': name});
  Future<void> lock() => request('lock');
  Future<void> muteToggle() => request('mute.toggle');
  Future<void> displayOff() => request('display.off');
  Future<void> displayOn() => request('display.on');

  Future<void> session(bool connected) async {
    if (!relayConnected.value) return;
    try {
      await request('session', {
        'state': connected ? 'connected' : 'disconnected',
      });
    } catch (_) {}
  }
}
