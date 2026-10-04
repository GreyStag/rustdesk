import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/shared_state.dart';
import '../../consts.dart';
import '../../mobile/pages/remote_page.dart' show showOptions;
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../custom_settings.dart';
import '../helper/helper_client.dart';
import 'staging_box.dart';

class CustomToolbar extends StatelessWidget {
  final FFI ffi;
  final String id;
  final bool open;
  final bool keyboardOpen;
  final VoidCallback onToggleOpen;
  final VoidCallback onToggleKeyboard;
  final Future<void> Function() onDisconnect;
  final VoidCallback onFitView;
  final VoidCallback onSettingsChanged;

  const CustomToolbar({
    Key? key,
    required this.ffi,
    required this.id,
    required this.open,
    required this.keyboardOpen,
    required this.onToggleOpen,
    required this.onToggleKeyboard,
    required this.onDisconnect,
    required this.onFitView,
    required this.onSettingsChanged,
  }) : super(key: key);

  Widget _round(
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
    String? tip,
  }) {
    return Material(
      color: active ? MyTheme.accent.withOpacity(0.9) : const Color(0xAA000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Tooltip(
            message: tip ?? '',
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
    bool active = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        backgroundColor: color ??
            (active
                ? MyTheme.accent.withOpacity(0.9)
                : const Color(0xCC222222)),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }

  Future<void> _sendStaging(BuildContext context) async {
    final text = StagingBox.controller.text;
    if (text.isEmpty) {
      _toast(context, 'Nothing in the staging box');
      return;
    }
    await sendTextToRemote(ffi, text);
    if (CustomSettings.enterAfterSend) ffi.inputModel.inputKey('VK_RETURN');
    if (!CustomSettings.keepTextAfterSend) StagingBox.controller.clear();
  }

  Future<void> _typeClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      _toast(context, 'Phone clipboard is empty');
      return;
    }
    await sendTextToRemote(ffi, text);
  }

  void _toast(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _mute(BuildContext context) async {
    try {
      await HelperClient.instance.muteToggle();
    } on HelperException catch (e) {
      _toast(context, 'Mute: ${e.message}');
    }
  }

  Future<void> _toggleIndicator() async {
    final next = !CustomSettings.connectionIndicator;
    await CustomSettings.setConnectionIndicator(next);
    if (next) {
      final shown = bind.sessionGetToggleOptionSync(
        sessionId: ffi.sessionId,
        arg: 'show-quality-monitor',
      );
      if (!shown) {
        bind.sessionToggleOption(
          sessionId: ffi.sessionId,
          value: 'show-quality-monitor',
        );
      }
      ffi.qualityMonitorModel.checkShowQualityMonitor(ffi.sessionId);
    }
    onSettingsChanged();
  }

  Future<void> _togglePrivacyControl() async {
    await CustomSettings.setPrivacyControl(!CustomSettings.privacyControl);
    onSettingsChanged();
  }

  Widget _chips(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        runSpacing: 4,
        children: [
          _chip(
            context,
            Icons.power_settings_new,
            'Disconnect',
            () => onDisconnect(),
            color: Colors.red.shade700,
          ),
          _chip(context, Icons.send, 'Send', () => _sendStaging(context)),
          _chip(
            context,
            Icons.content_paste_go,
            'Type clipboard',
            () => _typeClipboard(context),
          ),
          _chip(context, Icons.fit_screen, 'Fit', onFitView),
          _chip(
            context,
            Icons.desktop_windows,
            'RDP',
            () => showRdpPicker(context),
          ),
          _chip(context, Icons.volume_off, 'Mute', () => _mute(context)),
          _chip(
            context,
            Icons.network_check,
            'Signal',
            _toggleIndicator,
            active: CustomSettings.connectionIndicator,
          ),
          _chip(
            context,
            Icons.visibility_off,
            'Privacy',
            _togglePrivacyControl,
            active: CustomSettings.privacyControl,
          ),
          _chip(
            context,
            Icons.spellcheck,
            'Autocorrect',
            () async {
              await CustomSettings.setAutocorrect(!CustomSettings.autocorrect);
              onSettingsChanged();
            },
            active: CustomSettings.autocorrect,
          ),
          _chip(
            context,
            Icons.tune,
            'Options',
            () => showOptions(context, id, ffi.dialogManager),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 6,
      right: 60,
      bottom: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (open) _chips(context),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _round(
                open ? Icons.close : Icons.menu,
                onToggleOpen,
                active: open,
                tip: 'Toolbar',
              ),
              const SizedBox(width: 6),
              _round(
                Icons.keyboard,
                onToggleKeyboard,
                active: keyboardOpen,
                tip: 'Keyboard',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showRdpPicker(BuildContext context) async {
  final helper = HelperClient.instance;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: FutureBuilder<List<RdpEntry>>(
        future: helper.rdpList(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Helper unavailable'),
              subtitle: Text('${snap.error}'),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const ListTile(title: Text('No .rdp files in the folder'));
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Open RDP on the laptop',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final e in items)
                ListTile(
                  leading: const Icon(Icons.desktop_windows),
                  title: Text(e.name),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await helper.launchRdp(e.name);
                    } on HelperException catch (err) {
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(content: Text('RDP: ${err.message}')),
                        );
                      }
                    }
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

class ConnectionIndicator extends StatelessWidget {
  final FFI ffi;
  const ConnectionIndicator({Key? key, required this.ffi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      top: 8,
      child: AnimatedBuilder(
        animation: Listenable.merge([ffi.ffiModel, ffi.qualityMonitorModel]),
        builder: (ctx, _) {
          final direct = ffi.ffiModel.direct;
          final delay = ffi.qualityMonitorModel.data.delay;
          final path = direct == null ? '...' : (direct ? 'Direct' : 'Relay');
          final ms = (delay == null || delay.isEmpty) ? '' : ' $delay ms';
          final good = direct == true;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xAA000000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: good ? Colors.greenAccent : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  '$path$ms',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> setPrivacyMode(FFI ffi, String id, bool on) async {
  final state = PrivacyModeState.find(id);
  if (!on) {
    if (state.value.isEmpty) return;
    await bind.sessionTogglePrivacyMode(
      sessionId: ffi.sessionId,
      implKey: state.value,
      on: false,
    );
    return;
  }
  if (state.value.isNotEmpty) return;
  final offered = (ffi.ffiModel.pi
              .platformAdditions[kPlatformAdditionsSupportedPrivacyModeImpl]
          as List?)
      ?.map((e) => '${(e as List)[0]}')
      .toList();
  String implKey;
  if (offered == null || offered.isEmpty) {
    implKey = kPrivacyModeImplMag;
  } else {
    final preferred = CustomSettings.privacyImpl;
    implKey = offered.contains(preferred) ? preferred : offered.first;
  }
  await bind.sessionTogglePrivacyMode(
    sessionId: ffi.sessionId,
    implKey: implKey,
    on: true,
  );
}

class PrivacyBlankButton extends StatelessWidget {
  final FFI ffi;
  final String id;
  const PrivacyBlankButton({Key? key, required this.ffi, required this.id})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = PrivacyModeState.find(id);
    return Positioned(
      right: 8,
      top: 8,
      child: Obx(() {
        final on = state.value.isNotEmpty;
        return Material(
          color: on ? Colors.red.shade700 : const Color(0xAA000000),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (!ffi.ffiModel.pi.features.privacyMode && !on) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('The laptop does not offer privacy mode'),
                  ),
                );
                return;
              }
              setPrivacyMode(ffi, id, !on);
            },
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                on ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        );
      }),
    );
  }
}
