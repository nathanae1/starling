import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/app_paths_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/media/encrypted_media_paths.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/starling_alert_dialog.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  Future<_StorageSummary>? _summary;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _summary = _computeSummary();
  }

  Future<_StorageSummary> _computeSummary() async {
    final storage = ref.read(storageServiceProvider);
    final cacheSize = await storage.getMediaCacheSize();
    final dbSize = await storage.getDatabaseFileSize();
    final pinned = await storage.getPinnedMediaHashes();
    final allHashes = await storage.getAllCachedMediaHashes();
    var ownPinnedSize = 0;
    if (pinned.isNotEmpty) {
      for (final hash in allHashes) {
        if (!pinned.contains(hash)) continue;
        final m = await storage.getMedia(hash);
        if (m != null) ownPinnedSize += m.size;
      }
    }
    final cachedFromOthers = cacheSize - ownPinnedSize;
    return _StorageSummary(
      databaseBytes: dbSize,
      mediaCacheBytes: cacheSize,
      pinnedBytes: ownPinnedSize,
      cachedFromOthersBytes: cachedFromOthers < 0 ? 0 : cachedFromOthers,
    );
  }

  void _refresh() {
    setState(() {
      _summary = _computeSummary();
    });
  }

  Future<void> _clearCache() async {
    final confirmed = await showStarlingConfirm(
      context,
      title: 'Clear cache?',
      message:
          'Removes downloaded photos from friends. Your own posts and '
          'saved posts are kept. Photos will reload from peers when '
          'you next view them.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final supportDir = await ref.read(appSupportDirectoryProvider.future);
      final pinned = await storage.getPinnedMediaHashes();
      final removed = await storage.clearCachedMediaExcluding(pinned);
      for (final entry in removed) {
        try {
          final file = File(
            p.join(supportDir.path, mediaRelativePath(entry.hash)),
          );
          if (file.existsSync()) await file.delete();
        } catch (_) {
          // best effort
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared ${removed.length} cached files')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _exportOwnContent() async {
    setState(() => _busy = true);
    try {
      final exporter = ref.read(exportServiceProvider);
      final result = await exporter.exportOwnContent();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.path)],
          subject: 'Starling export',
          text:
              'Starling export — ${result.eventCount} posts, ${result.mediaCount} '
              'media files.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Column(
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
                      'Storage',
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
              child: FutureBuilder<_StorageSummary>(
                future: _summary,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${snap.error}',
                          style: starling.typography.small.copyWith(
                            color: starling.colors.danger,
                          ),
                        ),
                      ),
                    );
                  }
                  final s = snap.data!;
                  final total = s.databaseBytes + s.mediaCacheBytes;
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _Row(label: 'Total used', value: _fmt(total)),
                      _Row(label: 'Database', value: _fmt(s.databaseBytes)),
                      _Row(
                        label: 'Your content (saved & own media)',
                        value: _fmt(s.pinnedBytes),
                      ),
                      _Row(
                        label: 'Cached from friends',
                        value: _fmt(s.cachedFromOthersBytes),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: PrimaryButton(
                          label: 'Clear cache',
                          onPressed: _busy ? null : _clearCache,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SecondaryButton(
                          label: 'Export your content',
                          onPressed: _busy ? null : _exportOwnContent,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageSummary {
  const _StorageSummary({
    required this.databaseBytes,
    required this.mediaCacheBytes,
    required this.pinnedBytes,
    required this.cachedFromOthersBytes,
  });

  final int databaseBytes;
  final int mediaCacheBytes;
  final int pinnedBytes;
  final int cachedFromOthersBytes;
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: starling.typography.body)),
          Text(
            value,
            style: starling.typography.body.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: starling.colors.graphite,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var idx = 0;
  while (v >= 1024 && idx < units.length - 1) {
    v /= 1024;
    idx++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[idx]}';
}
