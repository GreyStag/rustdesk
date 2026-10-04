import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/input_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../custom_settings.dart';

enum SpecialKeyKind { modifier, key, drag, action }

class SpecialKeyDef {
  final String label;
  final SpecialKeyKind kind;
  final String code;
  const SpecialKeyDef(this.label, this.kind, this.code);
}

const specialKeyCatalog = <SpecialKeyDef>[
  SpecialKeyDef('Ctrl', SpecialKeyKind.modifier, 'ctrl'),
  SpecialKeyDef('Alt', SpecialKeyKind.modifier, 'alt'),
  SpecialKeyDef('Shift', SpecialKeyKind.modifier, 'shift'),
  SpecialKeyDef('Win', SpecialKeyKind.modifier, 'command'),
  SpecialKeyDef('Drag', SpecialKeyKind.drag, ''),
  SpecialKeyDef('Tab', SpecialKeyKind.key, 'VK_TAB'),
  SpecialKeyDef('PrtSc', SpecialKeyKind.key, 'VK_SNAPSHOT'),
  SpecialKeyDef('Esc', SpecialKeyKind.key, 'VK_ESCAPE'),
  SpecialKeyDef('Enter', SpecialKeyKind.key, 'VK_RETURN'),
  SpecialKeyDef('Del', SpecialKeyKind.key, 'VK_DELETE'),
  SpecialKeyDef('Bksp', SpecialKeyKind.key, 'VK_BACK'),
  SpecialKeyDef('Ins', SpecialKeyKind.key, 'VK_INSERT'),
  SpecialKeyDef('Home', SpecialKeyKind.key, 'VK_HOME'),
  SpecialKeyDef('End', SpecialKeyKind.key, 'VK_END'),
  SpecialKeyDef('PgUp', SpecialKeyKind.key, 'VK_PRIOR'),
  SpecialKeyDef('PgDn', SpecialKeyKind.key, 'VK_NEXT'),
  SpecialKeyDef('Up', SpecialKeyKind.key, 'VK_UP'),
  SpecialKeyDef('Down', SpecialKeyKind.key, 'VK_DOWN'),
  SpecialKeyDef('Left', SpecialKeyKind.key, 'VK_LEFT'),
  SpecialKeyDef('Right', SpecialKeyKind.key, 'VK_RIGHT'),
  SpecialKeyDef('Menu', SpecialKeyKind.key, 'Apps'),
  SpecialKeyDef('F1', SpecialKeyKind.key, 'VK_F1'),
  SpecialKeyDef('F2', SpecialKeyKind.key, 'VK_F2'),
  SpecialKeyDef('F3', SpecialKeyKind.key, 'VK_F3'),
  SpecialKeyDef('F4', SpecialKeyKind.key, 'VK_F4'),
  SpecialKeyDef('F5', SpecialKeyKind.key, 'VK_F5'),
  SpecialKeyDef('F11', SpecialKeyKind.key, 'VK_F11'),
  SpecialKeyDef('F12', SpecialKeyKind.key, 'VK_F12'),
  SpecialKeyDef('C+A+D', SpecialKeyKind.action, 'cad'),
  SpecialKeyDef('Lock', SpecialKeyKind.action, 'lock'),
  SpecialKeyDef('RClick', SpecialKeyKind.action, 'rclick'),
  SpecialKeyDef('DblClk', SpecialKeyKind.action, 'dblclick'),
];

class SpecialKeysStack extends StatefulWidget {
  final FFI ffi;
  final RxBool dragLatched;
  const SpecialKeysStack({
    Key? key,
    required this.ffi,
    required this.dragLatched,
  }) : super(key: key);

  @override
  State<SpecialKeysStack> createState() => _SpecialKeysStackState();
}

class _SpecialKeysStackState extends State<SpecialKeysStack> {
  bool _collapsed = false;

  InputModel get input => widget.ffi.inputModel;

  bool _modifierOn(String code) {
    switch (code) {
      case 'ctrl':
        return input.ctrl;
      case 'alt':
        return input.alt;
      case 'shift':
        return input.shift;
      case 'command':
        return input.command;
    }
    return false;
  }

  void _toggleModifier(String code) {
    switch (code) {
      case 'ctrl':
        input.ctrl = !input.ctrl;
        break;
      case 'alt':
        input.alt = !input.alt;
        break;
      case 'shift':
        input.shift = !input.shift;
        break;
      case 'command':
        input.command = !input.command;
        break;
    }
    setState(() {});
  }

  void _press(SpecialKeyDef def) {
    switch (def.kind) {
      case SpecialKeyKind.modifier:
        _toggleModifier(def.code);
        return;
      case SpecialKeyKind.drag:
        widget.dragLatched.toggle();
        return;
      case SpecialKeyKind.key:
        input.inputKey(def.code);
        break;
      case SpecialKeyKind.action:
        if (def.code == 'cad') {
          bind.sessionCtrlAltDel(sessionId: widget.ffi.sessionId);
        } else if (def.code == 'lock') {
          bind.sessionLockScreen(sessionId: widget.ffi.sessionId);
        } else if (def.code == 'rclick') {
          input.tap(MouseButtons.right);
        } else if (def.code == 'dblclick') {
          input
              .tap(MouseButtons.left)
              .then((_) => input.tap(MouseButtons.left));
        }
        break;
    }
    if (CustomSettings.oneShotModifiers) {
      input.resetModifiers();
      setState(() {});
    }
  }

  Future<void> _editList() async {
    final selected = CustomSettings.specialKeys.toSet();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text(
                    'Special keys',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Tick the keys to show in the stack'),
                ),
                for (final def in specialKeyCatalog)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(def.label),
                    title: Text(
                      def.kind == SpecialKeyKind.drag
                          ? 'Pan / Drag toggle'
                          : def.label,
                    ),
                    onChanged: (v) {
                      setSheet(() {
                        if (v == true) {
                          selected.add(def.label);
                        } else {
                          selected.remove(def.label);
                        }
                      });
                      CustomSettings.setSpecialKeys(
                        specialKeyCatalog
                            .where((d) => selected.contains(d.label))
                            .map((d) => d.label)
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _button(String label, VoidCallback onTap, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color:
            active ? MyTheme.accent.withOpacity(0.9) : const Color(0x99000000),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 34,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _monitorKey() {
    final pi = widget.ffi.ffiModel.pi;
    final n = pi.displays.length;
    if (n <= 1) return const SizedBox.shrink();
    final cur = pi.currentDisplay;
    final label = cur == kAllDisplayValue ? 'All' : '${cur + 1}/$n';
    return _button(label, () {
      final next = cur == kAllDisplayValue ? 0 : (cur + 1) % n;
      openMonitorInTheSameTab(next, widget.ffi, pi);
      setState(() {});
    }, active: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!CustomSettings.showSpecialKeys) return const SizedBox.shrink();
    final labels = CustomSettings.specialKeys;
    final defs = specialKeyCatalog.where((d) => labels.contains(d.label));
    return Positioned(
      right: 6,
      top: 8,
      bottom: 72,
      child: Obx(() {
        final drag = widget.dragLatched.value;
        return Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!_collapsed)
              Flexible(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final def in defs)
                        _button(
                          def.kind == SpecialKeyKind.drag
                              ? (CustomSettings.holdDragMouse ? 'Pan' : 'Drag')
                              : def.label,
                          () => _press(def),
                          active: def.kind == SpecialKeyKind.modifier
                              ? _modifierOn(def.code)
                              : def.kind == SpecialKeyKind.drag
                                  ? drag
                                  : false,
                        ),
                    ],
                  ),
                ),
              ),
            if (!_collapsed) _monitorKey(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_collapsed) _button('...', _editList),
                if (!_collapsed) const SizedBox(width: 4),
                _button(_collapsed ? '+' : '-', () {
                  setState(() => _collapsed = !_collapsed);
                }),
              ],
            ),
          ],
        );
      }),
    );
  }
}
