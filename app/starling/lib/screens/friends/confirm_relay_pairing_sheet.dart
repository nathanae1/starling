import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/relay_providers.dart';
import '../../services/relay_pairing_initiator.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

/// Confirmation sheet for pairing an always-on Relay (Plan 15). Shown when
/// the Owner scans a Relay's `starling-relay://pair` QR. On confirm it runs
/// the `/pair` handshake, advertises the relay endpoint, fans the updated
/// card to followers, and kicks the history backfill — all via
/// [RelayPairingService].
class ConfirmRelayPairingSheet extends ConsumerStatefulWidget {
  const ConfirmRelayPairingSheet({super.key, required this.payload});

  final RelayPairingPayload payload;

  @override
  ConsumerState<ConfirmRelayPairingSheet> createState() =>
      _ConfirmRelayPairingSheetState();
}

class _ConfirmRelayPairingSheetState
    extends ConsumerState<ConfirmRelayPairingSheet> {
  bool _pairing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final ready = ref.watch(relayPairingServiceProvider).value != null;
    final onion = widget.payload.relayOnion;
    final shortOnion = onion.length > 18 ? '${onion.substring(0, 18)}…' : onion;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Pair this relay?', style: starling.typography.h3),
        const SizedBox(height: 4),
        Text(
          shortOnion,
          style: starling.typography.micro,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'A relay keeps your feed reachable when your phone is offline. It '
          'stores only encrypted data it can’t read, and friends still '
          'prefer your phone when it’s online.',
          style: starling.typography.body,
          textAlign: TextAlign.center,
        ),
        if (!ready) ...[
          const SizedBox(height: 12),
          Text(
            'Waiting for Tor to come up — try again in a moment.',
            style: starling.typography.small
                .copyWith(color: starling.colors.stone),
            textAlign: TextAlign.center,
          ),
        ],
        if (_pairing) ...[
          const SizedBox(height: 12),
          Text(
            'This can take a minute while the relay sets up its Tor '
            'address.',
            style: starling.typography.small
                .copyWith(color: starling.colors.stone),
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: starling.typography.small
                .copyWith(color: starling.colors.danger),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Cancel',
                onPressed:
                    _pairing ? null : () => Navigator.of(context).pop(false),
                block: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: _pairing ? 'Pairing…' : 'Pair relay',
                onPressed: (_pairing || !ready) ? null : _pair,
                block: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pair() async {
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final service = ref.read(relayPairingServiceProvider).value;
      if (service == null) {
        setState(() {
          _pairing = false;
          _error = 'Tor isn’t ready yet.';
        });
        return;
      }
      await service.pair(widget.payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RelayPairingException catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        // 409 = the relay already claimed this token, routinely because our
        // earlier attempt timed out mid-launch; once the launch finishes,
        // retrying the same claim succeeds idempotently.
        _error = e.statusCode == 409
            ? 'That pairing code was already claimed — if your earlier '
                'attempt timed out, the relay may still be finishing. Try '
                'again in a minute, or scan a fresh code from the relay’s '
                'pairing page.'
            : 'Pairing failed: ${e.message}';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _error = 'The relay didn’t respond in time — it may still be '
            'setting up its address. Wait a minute, then try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _error = 'Unexpected error: $e';
      });
    }
  }
}
