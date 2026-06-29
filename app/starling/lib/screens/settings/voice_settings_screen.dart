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
                  bottom: BorderSide(color: starling.colors.hairline),
                ),
              ),
              child: Row(
                children: [
                  StarlingIconButton(
                    onPressed: () => context.pop(),
                    semanticLabel: 'Back',
                    child: const Icon(LucideIcons.arrowLeft, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      'Voice',
                      style: starling.typography.h3.copyWith(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
                        const SizedBox(height: 12),
                        const _IceFormatHelp(),
                        const SizedBox(height: 20),
                        PrimaryButton(
                          label: 'Save',
                          block: true,
                          onPressed: _save,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible inline help for the custom ICE-servers field. Mirrors the
/// syntax accepted by `IceConfig.parseServers` so users aren't guessing at
/// the format (accepted schemes, one server per line, pipe-separated
/// credentials).
class _IceFormatHelp extends StatefulWidget {
  const _IceFormatHelp();

  @override
  State<_IceFormatHelp> createState() => _IceFormatHelpState();
}

class _IceFormatHelpState extends State<_IceFormatHelp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: starling.colors.linen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: starling.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: starling.colors.graphite,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Format help',
                      style: starling.typography.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: starling.colors.ink,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: starling.colors.stone,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One server per line. Blank lines and lines starting with '
                    '# are skipped. To authenticate a TURN server, add a '
                    'username and credential after the URL, each separated by '
                    'a vertical bar ( | ).',
                    style: starling.typography.micro.copyWith(
                      color: starling.colors.graphite,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _IceExample('stun:stun.example.org:3478'),
                  const _IceExample('turn:turn.example.org:3478 | user | pass'),
                  const _IceExample(
                    'turns:turn.example.org:5349 | user | pass',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Schemes: stun, stuns, turn, turns.',
                    style: starling.typography.micro.copyWith(
                      color: starling.colors.stone,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A single monospace example line inside [_IceFormatHelp].
class _IceExample extends StatelessWidget {
  const _IceExample(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: starling.typography.monoSmall.copyWith(
          color: starling.colors.ink,
        ),
      ),
    );
  }
}
