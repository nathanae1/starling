import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/identity_provider.dart';
import '../../providers/qr_scanner_provider.dart';
import '../../services/follow_service.dart';
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

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _sub;
  // Cached so dispose() can stop the scanner without touching `ref` —
  // Riverpod marks the element disposed before our dispose() runs, so
  // ref.read here would throw "Cannot use ref after the widget was
  // disposed."
  QrScannerService? _scanner;
  bool _busy = false;
  String? _permissionMessage;
  bool _permissionDenied = false;
  // Transient feedback while the camera stays live: a notice chip for
  // non-Starling QRs, a brief flash on a successful scan.
  String? _notice;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    final scanner = _scanner;
    if (scanner != null) {
      unawaited(scanner.stop());
    }
    super.dispose();
  }

  /// Coming back from Settings (or anywhere) with the camera previously
  /// blocked: retry, so granting permission doesn't dead-end on the old
  /// error copy.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionMessage != null) {
      setState(() {
        _permissionMessage = null;
        _permissionDenied = false;
      });
      _start();
    }
  }

  Future<void> _start() async {
    final scanner = ref.read(qrScannerServiceProvider);
    _scanner = scanner;
    try {
      await scanner.start();
      _sub = scanner.scans.listen(_handleScan);
    } on QrScannerException catch (e) {
      setState(() {
        _permissionDenied = e.code == 'permission-denied';
        _permissionMessage = _permissionDenied
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
    if (parsed is! ValidInvite && parsed is! ValidRelayPair) {
      // Pointing at a wrong QR used to give zero response. Show a transient
      // notice and keep scanning (debounced — the scanner re-emits the same
      // code every frame).
      await _rejectForeignCode(payload);
      return;
    }
    if (_isOwnCode(parsed)) {
      await _rejectOwnCode();
      return;
    }
    setState(() {
      _busy = true;
      _flash = true;
    });
    unawaited(HapticFeedback.mediumImpact());
    // Let the flash land before the screen pops into the confirm sheet.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    await _confirmParsedInvite(parsed);
  }

  Future<void> _rejectForeignCode(String payload) async {
    debugLog('scan', 'unrecognized QR (${payload.length} chars)');
    setState(() {
      _busy = true;
      _notice = 'Not a Starling invite';
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _busy = false;
        _notice = null;
      });
    }
  }

  /// Pops the scan screen and hands off to the right confirm sheet, then
  /// toasts the follow-request outcome ("Request sent" / "we'll keep
  /// trying"). The messenger is captured before the pop so the toast lands
  /// on the surviving scaffold.
  Future<void> _confirmParsedInvite(ParsedInvite parsed) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (parsed is ValidRelayPair) {
      await showStarlingSheet(
        context: context,
        builder: (_) => ConfirmRelayPairingSheet(payload: parsed.payload),
      );
      return;
    }
    final delivery = await showStarlingSheet<RequestDelivery>(
      context: context,
      builder: (_) =>
          ConfirmRequestSheet(card: (parsed as ValidInvite).card),
    );
    showRequestDeliveryToast(messenger, delivery);
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
    await _confirmParsedInvite(parsed);
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
            // Success flash: a brief white blink confirming the scan took.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _flash ? 0.55 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
            if (_notice != null)
              Positioned(
                bottom: 150,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _notice!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _permissionMessage!,
                        style: starling.typography.small,
                      ),
                      if (_permissionDenied) ...[
                        const SizedBox(height: 10),
                        const SecondaryButton(
                          label: 'Open Settings',
                          onPressed: openAppSettings,
                        ),
                      ],
                    ],
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
                  tooltip: 'Close scanner',
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
