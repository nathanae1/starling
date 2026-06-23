import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/inputs.dart';

/// Plan 16 §Phase E — the opt-in custom-ICE escape hatch. By default voice is
/// serverless (host candidates only). A user who runs their own STUN/TURN
/// (e.g. coturn) can paste it here to recover symmetric-NAT pairs, knowingly
/// leaving the no-third-party-servers guarantee.
class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  final _controller = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: kCustomIceServersKey);
    if (!mounted) return;
    _controller.text = raw ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      await _storage.delete(key: kCustomIceServersKey);
    } else {
      await _storage.write(key: kCustomIceServersKey, value: text);
    }
    ref.invalidate(voiceServiceProvider);
    messenger.showSnackBar(
      const SnackBar(content: Text('Saved. Applies to your next call.')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: starling.colors.hairline)),
              ),
              child: Row(
                children: [
                  StarlingIconButton(
                    onPressed: () => context.pop(),
                    child: const Icon(LucideIcons.arrowLeft, size: 20),
                  ),
                  Expanded(
                    child: Text('Voice',
                        style: starling.typography.h3.copyWith(
                          fontFamily: 'Fraunces',
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        Text(
                          'Voice calls connect directly — over your WiFi or '
                          'your phone\'s IPv6 — with no servers. Most calls '
                          'just work. If a call can\'t connect directly, you '
                          'can paste your own STUN/TURN server below.',
                          style: starling.typography.small,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Adding a server here means call setup contacts it — '
                          'leaving Starling\'s no-servers guarantee. Leave '
                          'blank to stay fully serverless.',
                          style: starling.typography.micro,
                        ),
                        const SizedBox(height: 20),
                        const StarlingFieldLabel('Custom ICE servers'),
                        const SizedBox(height: 8),
                        StarlingTextarea(
                          controller: _controller,
                          minLines: 4,
                          maxLines: 8,
                          placeholder:
                              'stun:stun.example.org:3478\n'
                              'turn:turn.example.org:3478 | user | pass',
                        ),
                        const SizedBox(height: 20),
                        PrimaryButton(
                            label: 'Save', block: true, onPressed: _save),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
