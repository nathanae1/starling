import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/voice_room.dart';
import '../../providers/voice_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/inputs.dart';
import '../../widgets/top_bar.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _name = TextEditingController(text: 'Voice room');
  final _selected = <String>{};
  bool _starting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Microphone permission is needed for voice calls.'),
      ));
      return;
    }
    setState(() => _starting = true);
    try {
      await ref.read(roomManagerProvider).createRoom(
            name: _name.text.trim().isEmpty ? 'Voice room' : _name.text.trim(),
            inviteePubkeys: _selected.toList(),
          );
      unawaited(router.pushReplacement('/voice/room'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Couldn\'t start the room: $e')));
    }
  }

  void _toggle(String pubkey) {
    setState(() {
      if (_selected.contains(pubkey)) {
        _selected.remove(pubkey);
      } else if (_selected.length < kMaxRoomInvitees) {
        _selected.add(pubkey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final mutuals = ref.watch(mutualFollowsProvider);

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            StarlingTopBar(
              title: 'New room',
              left: StarlingIconButton(
                onPressed: () => context.pop(),
                child: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const StarlingFieldLabel('Room name'),
                  const SizedBox(height: 8),
                  StarlingInput(controller: _name, placeholder: 'Voice room'),
                  const SizedBox(height: 24),
                  StarlingFieldLabel(
                      'Invite friends (${_selected.length}/$kMaxRoomInvitees)'),
                  const SizedBox(height: 8),
                  mutuals.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => Text('Couldn\'t load friends',
                        style: starling.typography.small),
                    data: (follows) {
                      if (follows.isEmpty) {
                        return Text(
                          'You can only invite friends who follow you back. '
                          'No mutual friends yet.',
                          style: starling.typography.small,
                        );
                      }
                      return Column(
                        children: [
                          for (final f in follows)
                            _ContactRow(
                              name: f.displayName ?? f.pubkey.substring(0, 8),
                              selected: _selected.contains(f.pubkey),
                              disabled: !_selected.contains(f.pubkey) &&
                                  _selected.length >= kMaxRoomInvitees,
                              onTap: () => _toggle(f.pubkey),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: PrimaryButton(
                label: _starting ? 'Starting…' : 'Start room',
                block: true,
                onPressed:
                    (_starting || _selected.isEmpty) ? null : _start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.name,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: starling.colors.hairline)),
          ),
          child: Row(
            children: [
              Avatar(name: name, size: AvatarSize.sm),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name, style: starling.typography.body),
              ),
              Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 20,
                color: selected ? starling.colors.sage : starling.colors.stone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
