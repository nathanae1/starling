import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';

/// Top-level settings menu. Storage management lives here as of Plan 12;
/// other rows arrive in Plan 15.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                      'Settings',
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
              child: ListView(
                children: [
                  const _SectionHeader('Network'),
                  _SettingsRow(
                    icon: LucideIcons.globe,
                    label: 'Network',
                    detail: 'Sync, Tor, Wi-Fi, background mode',
                    onTap: () => context.push('/settings/network'),
                  ),
                  _SettingsRow(
                    icon: LucideIcons.radio,
                    label: 'Connection',
                    detail: 'Per-friend LAN and Tor reachability',
                    onTap: () => context.push('/settings/connection'),
                  ),
                  const _SectionHeader('Device'),
                  _SettingsRow(
                    icon: LucideIcons.hardDrive,
                    label: 'Storage',
                    detail: 'Cache size, clear cache, export',
                    onTap: () => context.push('/settings/storage'),
                  ),
                  const _SectionHeader('Calls'),
                  _SettingsRow(
                    icon: LucideIcons.phone,
                    label: 'Voice',
                    detail: 'Custom ICE servers for voice calls',
                    onTap: () => context.push('/voice/settings'),
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

/// A grouped-list section label. Gives the otherwise-identical settings
/// rows visual hierarchy ("Network", "Device", "Calls").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: starling.typography.micro.copyWith(
          color: starling.colors.stone,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: starling.colors.hairline)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: starling.colors.graphite),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: starling.typography.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: starling.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: starling.typography.micro),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: starling.colors.stone,
            ),
          ],
        ),
      ),
    );
  }
}
