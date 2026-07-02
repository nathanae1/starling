import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers/follow_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/voice_provider.dart';
import '../services/voice/room_manager.dart';
import '../theme/starling_theme.dart';
import '../utils/connection_card_parser.dart';
import 'buttons.dart';
import 'qr_code.dart';

class QrInviteSheet extends ConsumerStatefulWidget {
  const QrInviteSheet({super.key});

  @override
  ConsumerState<QrInviteSheet> createState() => _QrInviteSheetState();
}

class _QrInviteSheetState extends ConsumerState<QrInviteSheet> {
  bool _justCopied = false;
  // Cached so dispose() can check call state without touching `ref`.
  late final RoomManager _roomManager;

  @override
  void initState() {
    super.initState();
    _roomManager = ref.read(roomManagerProvider);
    // A sleeping/dimming screen is the top cause of failed phone-to-phone
    // scans — keep it awake while the QR is up.
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    // An active call holds its own wakelock (AppShell) — don't drop it.
    if (!_roomManager.inCall) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final identityAsync = ref.watch(identityControllerProvider);
    final card = ref.watch(ownConnectionCardProvider);

    if (identityAsync.value == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            'Finish onboarding before sharing your invite.',
            style: starling.typography.small,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (card == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Connecting to Tor…',
              style: starling.typography.small,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Your invite is ready as soon as the onion service comes up.',
              style: starling.typography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final url = inviteUrlFor(card);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Scan to add me as a friend',
          style: starling.typography.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "Share this with people you trust. There's no way for "
          'strangers to find you.',
          style: starling.typography.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        StarlingQRCode(data: url),
        const SizedBox(height: 16),
        Text(
          url,
          style: starling.typography.monoSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Text(
          "After they accept, have them show you their code too — that's "
          'how they share back.',
          style: starling.typography.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SecondaryButton(
                label: _justCopied ? 'Copied' : 'Copy link',
                onPressed: () => _onCopy(url),
                block: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SecondaryButton(
                label: 'Share link',
                onPressed: () => _onShare(url),
                block: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
          block: true,
        ),
        const SizedBox(height: 8),
        GhostButton(
          label: "Scan a friend's QR instead",
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/friends/scan');
          },
        ),
      ],
    );
  }

  Future<void> _onShare(String url) async {
    await SharePlus.instance.share(
      ShareParams(text: url, subject: 'Add me on Starling'),
    );
  }

  Future<void> _onCopy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _justCopied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }
}
