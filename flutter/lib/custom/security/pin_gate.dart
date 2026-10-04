import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../custom_settings.dart';

class CustomPinGate {
  CustomPinGate._();

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(
      List<int>.generate(16, (_) => rnd.nextInt(256)),
    );
    await CustomSettings.setPinSalt(salt);
    await CustomSettings.setPinHash(_hash(salt, pin));
  }

  static Future<void> clearPin() async {
    await CustomSettings.setPinSalt('');
    await CustomSettings.setPinHash('');
  }

  static bool check(String pin) =>
      CustomSettings.pinSet &&
      _hash(CustomSettings.pinSalt, pin) == CustomSettings.pinHash;

  static Future<bool> verify(BuildContext context) async {
    if (!CustomSettings.pinSet) return true;
    if (CustomSettings.biometric) {
      final ok = await _biometric();
      if (ok == true) return true;
    }
    if (!context.mounted) return false;
    return askPin(context);
  }

  static Future<bool?> _biometric() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return null;
      final available = await auth.getAvailableBiometrics();
      if (available.isEmpty) return null;
      return await auth.authenticate(
        localizedReason: 'Unlock remote access',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: false,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> askPin(
    BuildContext context, {
    String title = 'Enter PIN',
  }) async {
    var attempts = 0;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final ctl = TextEditingController();
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void submit() {
              if (check(ctl.text)) {
                Navigator.of(ctx).pop(true);
                return;
              }
              attempts++;
              if (attempts >= 5) {
                Navigator.of(ctx).pop(false);
                return;
              }
              ctl.clear();
              setState(() => error = 'Wrong PIN (${5 - attempts} left)');
            }

            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: ctl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(errorText: error),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(onPressed: submit, child: const Text('OK')),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  static Future<String?> promptNewPin(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final first = TextEditingController();
        final second = TextEditingController();
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void submit() {
              final pin = first.text.trim();
              if (pin.length < 4) {
                setState(() => error = 'Use at least 4 digits');
                return;
              }
              if (pin != second.text.trim()) {
                setState(() => error = 'The two entries differ');
                return;
              }
              Navigator.of(ctx).pop(pin);
            }

            return AlertDialog(
              title: const Text('Set connection PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: first,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'New PIN'),
                  ),
                  TextField(
                    controller: second,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Repeat PIN',
                      errorText: error,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                TextButton(onPressed: submit, child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
  }
}
