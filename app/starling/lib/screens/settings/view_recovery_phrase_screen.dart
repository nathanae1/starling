import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/service_providers.dart';
import '../../services/crypto/crockford_base32.dart';
import '../../services/storage/keychain_manager.dart';
import '../../theme/starling_theme.dart';
import '../../utils/debug_log.dart';
import '../../utils/secure_screen.dart';
import '../../widgets/buttons.dart';
import '../../widgets/phrase_card.dart';
import '../../widgets/starling_alert_dialog.dart';

/// Settings re-display of the 24-word recovery phrase (C2). Gated behind
/// local auth (biometric or device PIN); the phrase is re-derived from the
/// keychain secret key and round-tripped through the real recovery path
/// before display — a wrong phrase must never render.
class ViewRecoveryPhraseScreen extends ConsumerStatefulWidget {
  const ViewRecoveryPhraseScreen({super.key});

  @override
  ConsumerState<ViewRecoveryPhraseScreen> createState() =>
      _ViewRecoveryPhraseScreenState();
}

class _ViewRecoveryPhraseScreenState
    extends ConsumerState<ViewRecoveryPhraseScreen> {
  List<String>? _phrase;
  String? _error;
  bool _authFailed = false;

  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    SecureScreen.disable();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    setState(() {
      _authFailed = false;
      _error = null;
    });

    final auth = LocalAuthentication();
    bool authed;
    try {
      if (await auth.isDeviceSupported()) {
        // biometricOnly: false — device PIN is a fine fallback; a
        // biometric-only gate would dead-end non-enrolled users.
        authed = await auth.authenticate(
          localizedReason: 'Show your recovery phrase',
          persistAcrossBackgrounding: true,
        );
      } else {
        // No screen lock configured — the phrase is the user's own; warn
        // instead of locking them out of it.
        if (!mounted) return;
        authed = await showStarlingConfirm(
          context,
          title: 'No screen lock',
          message:
              'This device has no screen lock, so anyone holding it could '
              'view your recovery phrase. Show it anyway?',
          confirmLabel: 'Show phrase',
        );
      }
    } catch (e) {
      debugLog('recovery_phrase', 'local auth failed: $e');
      authed = false;
    }
    if (!mounted) return;
    if (!authed) {
      setState(() => _authFailed = true);
      return;
    }
    await _derivePhrase();
  }

  Future<void> _derivePhrase() async {
    try {
      final sk = await KeychainManager().loadIdentitySecretKey();
      final identity = await ref.read(storageServiceProvider).getIdentity();
      if (sk == null || sk.length < 32 || identity == null) {
        throw StateError('identity key unavailable');
      }
      // libsodium Ed25519 secret key layout: seed(32) || pubkey(32).
      final crypto = ref.read(cryptoServiceProvider);
      final words = await crypto.deriveRecoveryPhrase(sk.sublist(0, 32));
      // Round-trip through the REAL recovery path: the phrase must
      // reproduce the stored identity's pubkey, or we show an error —
      // never a wrong phrase.
      final recovered = await crypto.recoverFromPhrase(words);
      if (crockfordBase32Encode(recovered.publicKey) != identity.pubkey) {
        throw StateError('re-derived phrase does not match identity');
      }
      if (!mounted) return;
      setState(() => _phrase = words);
    } catch (e) {
      debugLog('recovery_phrase', 're-derivation failed: $e');
      if (!mounted) return;
      setState(() {
        _error =
            "Couldn't verify your recovery phrase on this device. Your "
            'account still works — but only a written copy from setup can '
            'recover it.';
      });
    }
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
                      'Recovery phrase',
                      style: starling.typography.h3.copyWith(
                        fontFamily: 'Fraunces',
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: _body(starling),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(StarlingTheme starling) {
    final phrase = _phrase;
    if (phrase != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PhraseWarning(),
          const SizedBox(height: 20),
          PhraseCard(phrase: phrase),
          const SizedBox(height: 10),
          PhraseCopyButton(phrase: phrase),
        ],
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(
          _error!,
          style: starling.typography.small.copyWith(
            color: starling.colors.danger,
          ),
        ),
      );
    }
    if (_authFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unlock to view your recovery phrase.',
              style: starling.typography.small,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Unlock', block: true, onPressed: _unlock),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
