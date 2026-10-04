import 'package:flutter/material.dart';

import '../common.dart';
import 'custom_settings.dart';

class OneTapConnectButton extends StatelessWidget {
  const OneTapConnectButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final id = CustomSettings.oneTapPeerId;
    if (id.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          icon: const Icon(Icons.laptop),
          label: const Text(
            'Connect to laptop',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          onPressed: () => connect(context, id),
        ),
      ),
    );
  }
}
