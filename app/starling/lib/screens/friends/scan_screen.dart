import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/identity_provider.dart';
import '../../providers/qr_scanner_provider.dart';
import '../../services/qr_scanner_service.dart';
import '../../utils/debug_log.dart';
import '../../theme/starling_theme.dart';
import '../../utils/connection_card_parser.dart';
import '../../widgets/buttons.dart';
import '../../widgets/sheet.dart';
import 'confirm_relay_pairing_sheet.dart';
import 'confirm_request_sheet.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  StreamSubscription<String>? _sub;
  // Cached so dispose() can stop the scanner without touching `ref` —
  // Riverpod marks the element disposed before our dispose() runs, so
  // ref.read here would throw "Cannot use ref after the widget was
  // disposed."
  QrScannerService? _scanner;
  bool _busy = false;
  String? _permissionMessage;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    final scanner = _scanner;
    if (scanner != null) {
      unawaited(scanner.stop());
    }
    super.dispose();
  }

  Future<void> _start() async {
    final scanner = ref.read(qrScannerServiceProvider);
    _scanner = scanner;
    try {
      await scanner.start();
      _sub = scanner.scans.listen(_handleScan);
    } on QrScannerException catch (e) {
      setState(() {
        _permissionMessage = e.code == 'permission-denied'
            ? 'Camera access is off. Paste an invite link below.'
            : "Couldn't start the camera (${e.message}). Paste an invite link below.";
      });
    }
  }

  /// Scanning your own QR is the obvious first experiment — catch it here
  /// with a snackbar and keep the camera running, instead of popping into a
  /// sheet that offers to follow yourself. (`ConfirmRequestSheet` has the
  /// same guard as a backstop for the paste and deep-link paths.)
  bool _isOwnCode(ParsedInvite parsed) {
    final ownPubkey = ref.read(identityControllerProvider).value?.pubkey;
    return parsed is ValidInvite &&
        ownPubkey != null &&
        parsed.card.pubkey == ownPubkey;
  }

  Future<void> _rejectOwnCode() async {
    setState(() => _busy = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            "That's your own code — have a friend scan it instead.",
          ),
          duration: Duration(seconds: 2),
        ),
      );
    // Debounce: the scanner keeps emitting the same QR every frame.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _handleScan(String payload) async {
    if (_busy) return;
    final parsed = parseInvite(payload);
    // Ignore anything that isn't a recognized Starling QR — keep scanning.
    if (parsed is! ValidInvite && parsed is! ValidRelayPair) return;
    if (_isOwnCode(parsed)) {
      await _rejectOwnCode();
      return;
    }
    setState(() => _busy = true);
    if (!mounted) return;
    Navigator.of(context).pop();
    await showStarlingSheet(
      context: context,
      builder: (_) => parsed is ValidRelayPair
          ? ConfirmRelayPairingSheet(payload: parsed.payload)
          : ConfirmRequestSheet(card: (parsed as ValidInvite).card),
    );
  }

  Future<void> _openPasteSheet() async {
    final controller = TextEditingController();
    final result = await showStarlingSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste invite link',
              style: StarlingTheme.of(ctx).typography.h3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'starling://connect?card=…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Open',
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              block: true,
            ),
          ],
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    final parsed = parseInvite(result);
    if (parsed is InvalidInvite) {
      if (!mounted) return;
      // Parser reasons are developer strings — log them, show plain copy.
      debugLog('scan', 'invite parse failed: ${parsed.reason}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That doesn't look like a Starling invite."),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    await showStarlingSheet(
      context: context,
      builder: (_) => parsed is ValidRelayPair
          ? ConfirmRelayPairingSheet(payload: parsed.payload)
          : ConfirmRequestSheet(card: (parsed as ValidInvite).card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final scanner = ref.read(qrScannerServiceProvider);
    final permissionDenied = _permissionMessage != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: permissionDenied
                  ? Container(color: Colors.black)
                  : _platformView(scanner.platformViewType),
            ),
            const Positioned.fill(child: _ReticleOverlay()),
            if (_permissionMessage != null)
              Positioned(
                top: 80,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: starling.colors.paper,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _permissionMessage!,
                    style: starling.typography.small,
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            Positioned(
              bottom: 36,
              left: 24,
              right: 24,
              child: Center(
                child: GhostButton(
                  label: 'Paste invite link',
                  onPressed: _openPasteSheet,
                ),
              ),
            ),
            const Positioned(
              bottom: 110,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Point at a Starling QR',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformView(String viewType) {
    if (viewType.endsWith('.mock')) {
      return Container(color: Colors.black);
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
          )
        : AndroidView(
            viewType: viewType,
            creationParams: const <String, dynamic>{},
            creationParamsCodec: const StandardMessageCodec(),
          );
  }
}

class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black26,
        child: Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}
