import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection_card.dart';
import '../../providers/follow_provider.dart';
import '../../providers/follows_provider.dart';
import '../../providers/identity_provider.dart';
import '../../services/follow_service.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';

class ConfirmRequestSheet extends ConsumerStatefulWidget {
  const ConfirmRequestSheet({super.key, required this.card});

  final ConnectionCard card;

  @override
  ConsumerState<ConfirmRequestSheet> createState() =>
      _ConfirmRequestSheetState();
}

class _ConfirmRequestSheetState extends ConsumerState<ConfirmRequestSheet> {
  bool _sending = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final shortPubkey = widget.card.pubkey.length > 8
        ? widget.card.pubkey.substring(0, 8)
        : widget.card.pubkey;

    // Guard rails before offering to send anything. This sheet is the one
    // choke point every invite path funnels through (scan, paste,
    // starling:// deep link), so both checks live here.
    final ownPubkey = ref.watch(identityControllerProvider).value?.pubkey;
    if (ownPubkey != null && widget.card.pubkey == ownPubkey) {
      return _InfoSheet(
        shortPubkey: shortPubkey,
        message: "That's your own code — have a friend scan it instead.",
      );
    }
    final follows = ref.watch(followsStreamProvider).value ?? const [];
    if (follows.any((f) => f.pubkey == widget.card.pubkey)) {
      return const _InfoSheet(
        shortPubkey: null,
        message: "You're already friends with this person.",
      );
    }

    final endpointCount = widget.card.endpoints.length;
    final ownEndpoints = ref.watch(ownEndpointsProvider);
    final ourOnionReady = ownEndpoints.any((e) => e.type == 'onion');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Avatar(name: shortPubkey, size: AvatarSize.lg),
        const SizedBox(height: 16),
        Text(shortPubkey, style: starling.typography.h3),
        const SizedBox(height: 4),
        Text(
          endpointCount == 0
              ? 'No endpoints — they may not be reachable'
              : '$endpointCount endpoint${endpointCount == 1 ? '' : 's'}',
          style: starling.typography.micro,
        ),
        const SizedBox(height: 16),
        Text(
          'Send a follow request to this person?',
          style: starling.typography.body,
          textAlign: TextAlign.center,
        ),
        if (!ourOnionReady) ...[
          const SizedBox(height: 12),
          Text(
            "Tor is still starting — you can send now and we'll deliver "
            "once it's up.",
            style: starling.typography.small.copyWith(
              color: starling.colors.stone,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (_sending) ...[
          const SizedBox(height: 12),
          Text(
            'This can take a minute over Tor.',
            style: starling.typography.small.copyWith(
              color: starling.colors.stone,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: starling.typography.small.copyWith(
              color: starling.colors.danger,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              // Cancel stays enabled while sending — a stalled Tor circuit
              // must never trap the user in the sheet.
              child: SecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
                block: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: _sending ? 'Sending…' : 'Send follow request',
                onPressed: _sending ? null : _send,
                block: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final service = ref.read(followServiceProvider);
      final delivery = await service.sendFollowRequest(widget.card);
      if (!mounted) return;
      // Unreachable friends queue instead of failing — the sheet closes
      // successfully either way and the caller toasts the outcome.
      Navigator.of(context).pop(delivery);
    } on FollowFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = switch (e.kind) {
          // No longer thrown by sendFollowRequest (unreachability queues);
          // kept for switch exhaustiveness.
          FollowFailureKind.noEndpoints =>
            "They look offline right now — we'll keep trying.",
          FollowFailureKind.network => 'Network error: ${e.message}',
          FollowFailureKind.unknownRequester =>
            "Couldn't load your identity. Try again.",
          FollowFailureKind.decryptFailed =>
            'Something went wrong preparing the request.',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = friendlyError(e, tag: 'follow_request');
      });
    }
  }
}

/// Toasts the outcome of a [ConfirmRequestSheet]. No-op when the sheet was
/// cancelled or dismissed ([delivery] == null). Takes the messenger rather
/// than a context because callers typically pop their own route before the
/// sheet resolves.
void showRequestDeliveryToast(
  ScaffoldMessengerState messenger,
  RequestDelivery? delivery,
) {
  if (delivery == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        delivery == RequestDelivery.delivered
            ? 'Request sent'
            : "They look offline right now — we'll keep trying and let "
                  'you know.',
      ),
    ),
  );
}

/// Terminal state for the confirm sheet: nothing to send, just explain why
/// and offer Close.
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.shortPubkey, required this.message});

  final String? shortPubkey;
  final String message;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (shortPubkey != null) ...[
          Avatar(name: shortPubkey!, size: AvatarSize.lg),
          const SizedBox(height: 16),
        ],
        Text(
          message,
          style: starling.typography.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          block: true,
        ),
      ],
    );
  }
}
