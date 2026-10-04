import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';

import 'custom_settings.dart';
import 'helper/helper_client.dart';
import 'security/pin_gate.dart';

class CustomSettingsPage extends StatefulWidget {
  const CustomSettingsPage({Key? key}) : super(key: key);

  @override
  State<CustomSettingsPage> createState() => _CustomSettingsPageState();
}

class _CustomSettingsPageState extends State<CustomSettingsPage> {
  Future<String?> _editText(
    String title,
    String initial, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
  }) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: type,
          obscureText: obscure,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editDouble(
    String title,
    double current,
    Future<void> Function(double) save, {
    double min = 0.1,
    double max = 10,
  }) async {
    final v = await _editText(
      title,
      '$current',
      type: const TextInputType.numberWithOptions(decimal: true),
    );
    if (v == null) return;
    final d = double.tryParse(v.trim());
    if (d == null || d < min || d > max) {
      _msg('Enter a number between $min and $max');
      return;
    }
    await save(d);
    setState(() {});
  }

  Future<void> _editInt(
    String title,
    int current,
    Future<void> Function(int) save, {
    int min = 0,
    int max = 100000,
  }) async {
    final v = await _editText(title, '$current', type: TextInputType.number);
    if (v == null) return;
    final i = int.tryParse(v.trim());
    if (i == null || i < min || i > max) {
      _msg('Enter a whole number between $min and $max');
      return;
    }
    await save(i);
    setState(() {});
  }

  Future<void> _editString(
    String title,
    String current,
    Future<void> Function(String) save, {
    bool obscure = false,
  }) async {
    final v = await _editText(title, current, obscure: obscure);
    if (v == null) return;
    await save(v.trim());
    setState(() {});
  }

  String _privacyImplLabel(String key) {
    switch (key) {
      case 'privacy_mode_impl_mag':
        return 'Magnifier';
      case 'privacy_mode_impl_exclude_from_capture':
        return 'Exclude from capture';
      case 'privacy_mode_impl_virtual_display':
        return 'Virtual display';
    }
    return key;
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _setPin() async {
    if (CustomSettings.pinSet) {
      final ok = await CustomPinGate.askPin(context, title: 'Current PIN');
      if (!ok) return;
    }
    if (!mounted) return;
    final pin = await CustomPinGate.promptNewPin(context);
    if (pin == null) return;
    await CustomPinGate.setPin(pin);
    setState(() {});
  }

  Future<void> _removePin() async {
    final ok = await CustomPinGate.askPin(context, title: 'Current PIN');
    if (!ok) return;
    await CustomPinGate.clearPin();
    setState(() {});
  }

  Future<void> _toggleAutoLock(bool v) async {
    if (v) {
      final ok = await _confirm(
        'Auto-lock on disconnect',
        'The laptop will lock every time the session ends. To get back in, '
            'type the PIN or the account password at the lock screen with the '
            'staging box and Send. Keep the account password somewhere safe '
            'for the times Windows asks for it instead of the PIN.',
      );
      if (!ok) return;
    }
    await CustomSettings.setAutoLockOnDisconnect(v);
    setState(() {});
  }

  Future<void> _testHelper() async {
    final h = HelperClient.instance;
    await h.restart();
    await Future.delayed(const Duration(seconds: 3));
    try {
      final r = await h.ping();
      _msg(
        'Helper answered. Lid: ${r['lidOpen'] == 1 ? 'open' : r['lidOpen'] == 0 ? 'closed' : 'unknown'}',
      );
    } on HelperException catch (e) {
      _msg('Helper: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spanreed')),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('General'),
            tiles: [
              SettingsTile.switchTile(
                title: const Text('Custom remote screen'),
                description: const Text(
                  'Off restores the stock RustDesk remote page',
                ),
                initialValue: CustomSettings.customUi,
                onToggle: (v) async {
                  await CustomSettings.setCustomUi(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Show gesture debug line'),
                description: const Text(
                  'Yellow readout at the top of the remote screen',
                ),
                initialValue: CustomSettings.debugOverlay,
                onToggle: (v) async {
                  await CustomSettings.setDebugOverlay(v);
                  setState(() {});
                },
              ),
              SettingsTile(
                title: const Text('One-tap connect ID'),
                value: Text(
                  CustomSettings.oneTapPeerId.isEmpty
                      ? 'Not set'
                      : CustomSettings.oneTapPeerId,
                ),
                onPressed: (_) => _editString(
                  'Laptop RustDesk ID',
                  CustomSettings.oneTapPeerId,
                  CustomSettings.setOneTapPeerId,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('View and gestures'),
            tiles: [
              SettingsTile(
                title: const Text('Zoom in per tap'),
                value: Text('x${CustomSettings.zoomInFactor}'),
                onPressed: (_) => _editDouble(
                  'Zoom in factor',
                  CustomSettings.zoomInFactor,
                  CustomSettings.setZoomInFactor,
                  min: 1.05,
                  max: 4,
                ),
              ),
              SettingsTile(
                title: const Text('Zoom out per triple tap'),
                value: Text('x${CustomSettings.zoomOutFactor}'),
                onPressed: (_) => _editDouble(
                  'Zoom out factor',
                  CustomSettings.zoomOutFactor,
                  CustomSettings.setZoomOutFactor,
                  min: 0.1,
                  max: 0.95,
                ),
              ),
              SettingsTile(
                title: const Text('Minimum view'),
                value: Text(
                  CustomSettings.minimumView == 'fit'
                      ? 'Fit (may letterbox)'
                      : CustomSettings.minimumView == 'fill'
                          ? 'Fill the screen'
                          : 'Auto: fit upright, fill sideways',
                ),
                onPressed: (_) async {
                  final cur = CustomSettings.minimumView;
                  await CustomSettings.setMinimumView(
                    cur == 'auto'
                        ? 'fit'
                        : cur == 'fit'
                            ? 'fill'
                            : 'auto',
                  );
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Hold then drag moves the mouse'),
                description: const Text(
                  'On: drag files, select text, move windows; the Pan key in the stack switches to panning the view. Off: hold-drag pans and the Drag key switches to the mouse. Two fingers always pan. Hold and release without moving is a double click.',
                ),
                initialValue: CustomSettings.holdDragMouse,
                onToggle: (v) async {
                  await CustomSettings.setHoldDragMouse(v);
                  setState(() {});
                },
              ),
              SettingsTile(
                title: const Text('Hold delay'),
                value: Text('${CustomSettings.holdDelayMs} ms'),
                onPressed: (_) => _editInt(
                  'Hold delay (ms)',
                  CustomSettings.holdDelayMs,
                  CustomSettings.setHoldDelayMs,
                  min: 100,
                  max: 1000,
                ),
              ),
              SettingsTile(
                title: const Text('Tap grouping window'),
                description: const Text(
                  'How long to wait for a second or third tap. Lower is snappier, higher is more forgiving.',
                ),
                value: Text('${CustomSettings.tapTimeoutMs} ms'),
                onPressed: (_) => _editInt(
                  'Tap window (ms)',
                  CustomSettings.tapTimeoutMs,
                  CustomSettings.setTapTimeoutMs,
                  min: 120,
                  max: 600,
                ),
              ),
              SettingsTile(
                title: const Text('Scroll sensitivity'),
                value: Text('x${CustomSettings.scrollSensitivity}'),
                onPressed: (_) => _editDouble(
                  'Scroll sensitivity',
                  CustomSettings.scrollSensitivity,
                  CustomSettings.setScrollSensitivity,
                  min: 0.2,
                  max: 5,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Typing'),
            tiles: [
              SettingsTile(
                title: const Text('Staging box opacity'),
                value: Text(
                  '${(CustomSettings.keyboardOpacity * 100).round()}%',
                ),
                onPressed: (_) => _editDouble(
                  'Opacity (0.2 to 1.0)',
                  CustomSettings.keyboardOpacity,
                  CustomSettings.setKeyboardOpacity,
                  min: 0.2,
                  max: 1.0,
                ),
              ),
              SettingsTile.switchTile(
                title: const Text('Keep text after Send'),
                initialValue: CustomSettings.keepTextAfterSend,
                onToggle: (v) async {
                  await CustomSettings.setKeepTextAfterSend(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text(
                    'Keyboard opens when the laptop focuses a text box'),
                description: const Text(
                  'Needs the helper. Works for laptop apps, not inside an RDP window; the keyboard button always works.',
                ),
                initialValue: CustomSettings.autoKeyboard,
                onToggle: (v) async {
                  await CustomSettings.setAutoKeyboard(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Send presses Enter afterwards'),
                description: const Text(
                  'Submits chat messages. Line breaks inside the text are sent as Shift+Enter either way.',
                ),
                initialValue: CustomSettings.enterAfterSend,
                onToggle: (v) async {
                  await CustomSettings.setEnterAfterSend(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Autocorrect in the staging box'),
                description: const Text(
                  'Lets the phone keyboard correct and suggest as you type',
                ),
                initialValue: CustomSettings.autocorrect,
                onToggle: (v) async {
                  await CustomSettings.setAutocorrect(v);
                  setState(() {});
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Special keys'),
            tiles: [
              SettingsTile.switchTile(
                title: const Text('Show the key stack'),
                initialValue: CustomSettings.showSpecialKeys,
                onToggle: (v) async {
                  await CustomSettings.setShowSpecialKeys(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Modifiers release after one key'),
                description: const Text(
                  'Off: Ctrl, Alt, Shift and Win stay pressed until tapped again',
                ),
                initialValue: CustomSettings.oneShotModifiers,
                onToggle: (v) async {
                  await CustomSettings.setOneShotModifiers(v);
                  setState(() {});
                },
              ),
              SettingsTile(
                title: const Text('Keys in the stack'),
                value: Text(CustomSettings.specialKeys.join(', ')),
                description: const Text(
                  'Edit with the ... button at the top of the stack',
                ),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Security'),
            tiles: [
              SettingsTile(
                title: Text(CustomSettings.pinSet ? 'Change PIN' : 'Set PIN'),
                description: Text(
                  CustomSettings.pinSet
                      ? 'A PIN is required before every connection'
                      : 'No PIN: connections are not gated',
                ),
                onPressed: (_) => _setPin(),
              ),
              if (CustomSettings.pinSet)
                SettingsTile(
                  title: const Text('Remove PIN'),
                  onPressed: (_) => _removePin(),
                ),
              SettingsTile.switchTile(
                title: const Text('Try fingerprint or face first'),
                description: const Text('Falls back to the PIN'),
                initialValue: CustomSettings.biometric,
                onToggle: (v) async {
                  await CustomSettings.setBiometric(v);
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: const Text('Auto-lock on disconnect'),
                description: const Text(
                  'Unlock again with the PIN or password via the staging box',
                ),
                initialValue: CustomSettings.autoLockOnDisconnect,
                onToggle: _toggleAutoLock,
              ),
              SettingsTile(
                title: const Text('Idle timeout'),
                value: Text(
                  CustomSettings.idleTimeoutMinutes <= 0
                      ? 'Off'
                      : '${CustomSettings.idleTimeoutMinutes} min',
                ),
                description: const Text(
                  'Disconnects after this long with no touch. 0 turns it off.',
                ),
                onPressed: (_) => _editInt(
                  'Idle minutes (0 = off)',
                  CustomSettings.idleTimeoutMinutes,
                  CustomSettings.setIdleTimeoutMinutes,
                  max: 720,
                ),
              ),
              SettingsTile.switchTile(
                title: const Text('Privacy mode on every connection'),
                description: const Text(
                  'Blanks the laptop screens and blocks its keyboard and mouse while you are connected. Ends with the session.',
                ),
                initialValue: CustomSettings.privacyOnConnect,
                onToggle: (v) async {
                  await CustomSettings.setPrivacyOnConnect(v);
                  setState(() {});
                },
              ),
              SettingsTile(
                title: const Text('Privacy mode method'),
                value: Text(_privacyImplLabel(CustomSettings.privacyImpl)),
                description: const Text(
                  'Magnifier paints the screens black and stays smooth. Virtual display switches the real outputs off but lags. If the laptop does not offer the chosen one, the first it offers is used.',
                ),
                onPressed: (_) async {
                  const order = [
                    'privacy_mode_impl_mag',
                    'privacy_mode_impl_exclude_from_capture',
                    'privacy_mode_impl_virtual_display',
                  ];
                  final i = order.indexOf(CustomSettings.privacyImpl);
                  await CustomSettings.setPrivacyImpl(
                    order[(i + 1) % order.length],
                  );
                  setState(() {});
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Laptop helper'),
            tiles: [
              SettingsTile.switchTile(
                title: const Text('Use the helper'),
                description: const Text(
                  'RDP launcher, mute, lid alerts via the relay',
                ),
                initialValue: CustomSettings.helperEnabled,
                onToggle: (v) async {
                  await CustomSettings.setHelperEnabled(v);
                  if (v) {
                    HelperClient.instance.start();
                  } else {
                    await HelperClient.instance.stop();
                  }
                  setState(() {});
                },
              ),
              SettingsTile(
                title: const Text('Relay host'),
                value: Text(
                  CustomSettings.helperHost.isEmpty
                      ? 'Not set'
                      : CustomSettings.helperHost,
                ),
                onPressed: (_) => _editString(
                  'Relay host or IP',
                  CustomSettings.helperHost,
                  CustomSettings.setHelperHost,
                ),
              ),
              SettingsTile(
                title: const Text('Relay port'),
                value: Text('${CustomSettings.helperPort}'),
                onPressed: (_) => _editInt(
                  'Relay port',
                  CustomSettings.helperPort,
                  CustomSettings.setHelperPort,
                  min: 1,
                  max: 65535,
                ),
              ),
              SettingsTile(
                title: const Text('Token'),
                value: Text(
                  CustomSettings.helperToken.isEmpty ? 'Not set' : '****',
                ),
                onPressed: (_) => _editString(
                  'Shared token',
                  CustomSettings.helperToken,
                  CustomSettings.setHelperToken,
                  obscure: true,
                ),
              ),
              SettingsTile(
                title: const Text('Certificate fingerprint (SHA-256)'),
                value: Text(
                  CustomSettings.helperCertSha256.isEmpty
                      ? 'Not set'
                      : '${CustomSettings.helperCertSha256.substring(0, 12)}...',
                ),
                onPressed: (_) => _editString(
                  'Fingerprint from gen-cert.sh',
                  CustomSettings.helperCertSha256,
                  CustomSettings.setHelperCertSha256,
                ),
              ),
              SettingsTile(
                title: const Text('Test helper connection'),
                onPressed: (_) => _testHelper(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
