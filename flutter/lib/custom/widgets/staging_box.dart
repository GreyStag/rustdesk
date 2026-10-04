import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../custom_settings.dart';

Future<void> sendTextToRemote(FFI ffi, String text) async {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isNotEmpty) {
      await bind.sessionInputString(sessionId: ffi.sessionId, value: lines[i]);
    }
    if (i < lines.length - 1) {
      final input = ffi.inputModel;
      final shiftWas = input.shift;
      input.shift = true;
      input.inputKey('VK_RETURN');
      input.shift = shiftWas;
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
}

class StagingBox extends StatefulWidget {
  final FFI ffi;
  final VoidCallback onClose;
  final VoidCallback? onActivity;
  const StagingBox(
      {Key? key, required this.ffi, required this.onClose, this.onActivity})
      : super(key: key);

  static final TextEditingController controller = TextEditingController();
  static final RxBool opaque = false.obs;

  @override
  State<StagingBox> createState() => _StagingBoxState();
}

class _StagingBoxState extends State<StagingBox> {
  final _focus = FocusNode();
  final _scroll = ScrollController();

  void _followCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool _busy = false;
  String _lastText = StagingBox.controller.text;

  bool get _chordModifierLatched {
    final input = widget.ffi.inputModel;
    return input.ctrl || input.alt || input.command;
  }

  bool _sendChord(String ch) {
    if (ch.length != 1) return false;
    final code = ch.toUpperCase().codeUnitAt(0);
    final isLetter = code >= 65 && code <= 90;
    final isDigit = code >= 48 && code <= 57;
    if (!isLetter && !isDigit) return false;
    final input = widget.ffi.inputModel;
    input.inputKey('VK_${String.fromCharCode(code)}');
    input.resetModifiers();
    return true;
  }

  void _onTextChanged(String text) {
    final old = _lastText;
    if (_chordModifierLatched && text.length == old.length + 1) {
      var i = 0;
      while (i < old.length && old[i] == text[i]) {
        i++;
      }
      final ch = text[i];
      if (_sendChord(ch)) {
        StagingBox.controller.value = TextEditingValue(
          text: old,
          selection: TextSelection.collapsed(offset: i),
        );
        _lastText = old;
        return;
      }
    }
    _lastText = text;
    widget.onActivity?.call();
    _followCaret();
  }

  void _replaceSelection(String insert, {int deleteBefore = 0}) {
    final c = StagingBox.controller;
    final text = c.text;
    var sel = c.selection;
    if (!sel.isValid || sel.start > text.length || sel.end > text.length) {
      sel = TextSelection.collapsed(offset: text.length);
    }
    var start = sel.start;
    final end = sel.end;
    if (sel.isCollapsed && deleteBefore > 0) {
      start = (start - deleteBefore).clamp(0, text.length);
    }
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    _lastText = c.text;
    widget.onActivity?.call();
    _followCaret();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      if (StagingBox.controller.text.isEmpty) {
        widget.ffi.inputModel.inputKey('VK_BACK');
        widget.onActivity?.call();
      } else {
        _replaceSelection('', deleteBefore: 1);
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _replaceSelection('\n');
    } else {
      final ch = event.character;
      if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
        if (!(_chordModifierLatched && _sendChord(ch))) {
          _replaceSelection(ch);
        }
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureKeyboard());
    for (final ms in [600, 1500, 3000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        if (View.of(context).viewInsets.bottom == 0) _ensureKeyboard();
      });
    }
  }

  Future<void> _ensureKeyboard() async {
    await widget.ffi.invokeMethod('enable_soft_keyboard', true);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    if (!mounted) return;
    if (!_focus.hasFocus) _focus.requestFocus();
    await SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    widget.ffi.invokeMethod('enable_soft_keyboard', false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    super.dispose();
  }

  Future<void> _send() async {
    final text = StagingBox.controller.text;
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await sendTextToRemote(widget.ffi, text);
      if (CustomSettings.enterAfterSend) {
        widget.ffi.inputModel.inputKey('VK_RETURN');
      }
      if (!CustomSettings.keepTextAfterSend) StagingBox.controller.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectAllOnLaptop() {
    final input = widget.ffi.inputModel;
    final ctrlWas = input.ctrl;
    input.ctrl = true;
    input.inputKey('VK_A');
    input.ctrl = ctrlWas;
    widget.onActivity?.call();
  }

  Future<void> _copyFromLaptop() async {
    final before = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final input = widget.ffi.inputModel;
    final ctrlWas = input.ctrl;
    input.ctrl = true;
    input.inputKey('VK_C');
    input.ctrl = ctrlWas;
    String after = before;
    for (var i = 0; i < 8 && after == before; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      after = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    }
    if (!mounted) return;
    if (after == before) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing new arrived from the laptop clipboard. Select text first, and check clipboard sync is on.',
          ),
        ),
      );
      return;
    }
    await _pasteFromPhone();
  }

  Future<void> _pasteFromPhone() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    final c = StagingBox.controller;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.text = c.text.replaceRange(start, end, text);
    c.selection = TextSelection.collapsed(offset: start + text.length);
  }

  Widget _iconButton(
    IconData icon,
    String tip,
    VoidCallback? onTap, {
    Color? color,
  }) =>
      IconButton(
        icon: Icon(icon, color: color ?? Colors.white, size: 20),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Obx(() {
        final opacity =
            StagingBox.opaque.value ? 0.97 : CustomSettings.keyboardOpacity;
        return Focus(
          onKeyEvent: _onKey,
          child: Material(
            color: Colors.black.withOpacity(opacity.clamp(0.2, 1.0)),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _iconButton(Icons.keyboard_hide, 'Hide keyboard',
                                  () {
                                widget.onClose();
                              }),
                              _iconButton(
                                StagingBox.opaque.value
                                    ? Icons.opacity
                                    : Icons.opacity_outlined,
                                'Toggle transparency',
                                () => StagingBox.opaque.toggle(),
                              ),
                              _iconButton(
                                Icons.select_all,
                                'Select all on the laptop (Ctrl+A)',
                                _selectAllOnLaptop,
                              ),
                              _iconButton(
                                Icons.copy,
                                'Copy the laptop selection into the box',
                                _copyFromLaptop,
                              ),
                              _iconButton(
                                Icons.content_paste,
                                'Paste phone clipboard here',
                                _pasteFromPhone,
                              ),
                              _iconButton(Icons.backspace_outlined, 'Clear',
                                  () {
                                StagingBox.controller.clear();
                                _lastText = '';
                              }),
                              _iconButton(
                                Icons.spellcheck,
                                'Toggle autocorrect',
                                () async {
                                  await CustomSettings.setAutocorrect(
                                    !CustomSettings.autocorrect,
                                  );
                                  if (mounted) setState(() {});
                                },
                                color: CustomSettings.autocorrect
                                    ? Colors.greenAccent
                                    : Colors.white54,
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Send'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          maxHeight: 150,
                        ),
                        child: TextField(
                          controller: StagingBox.controller,
                          scrollController: _scroll,
                          focusNode: _focus,
                          autofocus: true,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: CustomSettings.autocorrect,
                          enableSuggestions: CustomSettings.autocorrect,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onChanged: _onTextChanged,
                          onTap: _ensureKeyboard,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Type here, then Send',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
