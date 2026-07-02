import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/starling_theme.dart';

/// The status vocabulary, per Plan 18's locked decisions:
///   - [connecting] — Tor is still bootstrapping and no peer is reachable
///     yet; the app is coming online, not broken.
///   - [synced] — up to date.
///   - [syncing] — a run is in flight (see [SyncDirection]).
///   - [offline] — no friend reachable on *any* transport (LAN, Tor,
///     libp2p), not just mDNS.
///   - [problem] — the last sync run errored while peers were reachable.
enum SyncState { synced, syncing, connecting, offline, problem }

/// Direction of an in-flight sync, used to split the [SyncState.syncing] glyph
/// and label into "Loading feeds…" (pulling friends' posts in) vs "Publishing…"
/// (pushing the user's own post out). Null = generic syncing (no direction).
enum SyncDirection { pulling, pushing }

/// Status indicator for the feed sync row. Conveys state through a distinct
/// glyph *and* color (not color alone, which is invisible to color-blind
/// users) and carries a screen-reader label. The syncing state pulses to
/// signal in-flight work.
class SyncDot extends StatefulWidget {
  const SyncDot({super.key, required this.state, this.direction});
  final SyncState state;

  /// Only meaningful while [state] is [SyncState.syncing].
  final SyncDirection? direction;

  @override
  State<SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<SyncDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncToState();
  }

  @override
  void didUpdateWidget(covariant SyncDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncToState();
    }
  }

  /// Pulse while work is in flight — syncing and connecting both read as
  /// "something is happening", the others are steady states.
  bool get _pulsing =>
      widget.state == SyncState.syncing || widget.state == SyncState.connecting;

  /// Only run the controller when the dot is actually pulsing. A
  /// permanently-repeating controller blocks `pumpAndSettle` in widget
  /// tests and burns frames in production for steady-state UIs.
  void _syncToState() {
    if (_pulsing) {
      if (!_ctrl.isAnimating) {
        _ctrl.repeat(reverse: true);
      }
    } else {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _colorFor(StarlingTheme starling) => switch (widget.state) {
    SyncState.synced => starling.colors.success,
    SyncState.syncing => starling.colors.sage,
    SyncState.connecting => starling.colors.sage,
    SyncState.offline => starling.colors.stone,
    SyncState.problem => starling.colors.warning,
  };

  IconData _glyphFor() => switch (widget.state) {
    SyncState.synced => LucideIcons.check,
    SyncState.syncing => switch (widget.direction) {
      SyncDirection.pushing => LucideIcons.arrowUp,
      SyncDirection.pulling => LucideIcons.arrowDown,
      null => LucideIcons.refreshCw,
    },
    SyncState.connecting => LucideIcons.loader,
    SyncState.offline => LucideIcons.cloudOff,
    SyncState.problem => LucideIcons.triangleAlert,
  };

  String _semanticsFor() => switch (widget.state) {
    SyncState.synced => 'Synced',
    SyncState.syncing => switch (widget.direction) {
      SyncDirection.pushing => 'Publishing',
      SyncDirection.pulling => 'Loading feeds',
      null => 'Syncing',
    },
    SyncState.connecting => 'Connecting',
    SyncState.offline => 'Offline',
    SyncState.problem => 'Sync problem',
  };

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final glyph = Icon(_glyphFor(), size: 14, color: _colorFor(starling));

    Widget content = glyph;
    if (_pulsing) {
      content = AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          // Triangle wave 0 → 1 → 0 drives a wider opacity swing plus a
          // subtle scale so the pulse reads even without color.
          final tri = 1 - (1 - 2 * _ctrl.value).abs();
          final opacity = 0.30 + 0.70 * tri;
          final scale = 0.82 + 0.18 * tri;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: glyph,
      );
    }

    return Semantics(
      label: _semanticsFor(),
      child: SizedBox(width: 16, height: 16, child: Center(child: content)),
    );
  }
}
