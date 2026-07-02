import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/models.dart';
import '../../providers/follow_profile_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/voice_provider.dart';
import '../../services/types.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/time_ago.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/inputs.dart';
import '../../widgets/top_bar.dart';

/// Plan 17 — a durable chatroom: an async E2E text timeline plus a "start
/// call" affordance. Text mirrors the comments UI; the call reuses the Plan
/// 16 mesh via [RoomManager.startRoomCall].
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  bool _startingCall = false;

  @override
  void initState() {
    super.initState();
    // Clear the unread badge once the timeline is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(roomMessageControllerProvider(widget.roomId).notifier)
          .markRead();
    });
  }

  Future<void> _startCall(Room room, List<String> members) async {
    if (_startingCall) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Microphone permission is needed for calls.'),
          action: status.isPermanentlyDenied
              ? const SnackBarAction(
                  label: 'Open Settings',
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
      return;
    }
    setState(() => _startingCall = true);
    try {
      await ref
          .read(roomManagerProvider)
          .startRoomCall(
            chatroomId: room.id,
            name: room.name,
            memberPubkeys: members,
          );
      unawaited(router.push('/voice/room'));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(friendlyError(e, tag: 'room_call'))),
        );
      }
    } finally {
      if (mounted) setState(() => _startingCall = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final room = ref.watch(roomByIdProvider(widget.roomId)).value;
    final members =
        ref.watch(roomMembersListProvider(widget.roomId)).value ??
        const <RoomMember>[];
    final voiceState = ref.watch(voiceRoomStateProvider).value;
    final inThisCall =
        voiceState != null && voiceState.room.id == widget.roomId;
    final memberCount = members.length;

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            StarlingTopBar(
              title: room?.name ?? 'Room',
              subtitle: memberCount > 0
                  ? '$memberCount member${memberCount == 1 ? '' : 's'}'
                  : null,
              left: StarlingIconButton(
                onPressed: () => context.pop(),
                semanticLabel: 'Back',
                child: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
              right: room == null
                  ? null
                  : StarlingIconButton(
                      onPressed: _startingCall
                          ? null
                          : () {
                              if (inThisCall) {
                                context.push('/voice/room');
                              } else {
                                _startCall(
                                  room,
                                  members.map((m) => m.pubkey).toList(),
                                );
                              }
                            },
                      semanticLabel: inThisCall
                          ? 'Return to call'
                          : 'Start call',
                      child: Icon(
                        inThisCall ? LucideIcons.phoneCall : LucideIcons.phone,
                        size: 20,
                        color: inThisCall
                            ? starling.colors.sageDeep
                            : starling.colors.ink,
                      ),
                    ),
            ),
            Expanded(child: _RoomTimeline(roomId: widget.roomId)),
            _RoomComposer(roomId: widget.roomId),
          ],
        ),
      ),
    );
  }
}

/// The room's message timeline (kind=102), oldest→newest.
class _RoomTimeline extends ConsumerWidget {
  const _RoomTimeline({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final messagesAsync = ref.watch(roomMessagesProvider(roomId));

    return messagesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            friendlyError(e, tag: 'room'),
            style: starling.typography.small.copyWith(
              color: starling.colors.danger,
            ),
          ),
        ),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'No messages yet. Say hello.',
                textAlign: TextAlign.center,
                style: starling.typography.small.copyWith(
                  color: starling.colors.stone,
                ),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, i) => _RoomMessageRow(message: messages[i]),
        );
      },
    );
  }
}

class _RoomMessageRow extends ConsumerWidget {
  const _RoomMessageRow({required this.message});

  final Event message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starling = StarlingTheme.of(context);
    final clock = ref.watch(clockProvider);
    final profile = ref.watch(followProfileProvider(message.pubkey));
    final displayName = profile.maybeWhen(
      data: (p) => firstNameOf(p.displayName),
      orElse: () => 'You',
    );
    final body = utf8.decode(message.content, allowMalformed: true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(name: displayName, size: AvatarSize.sm),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: starling.typography.small.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: starling.colors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(
                        message.createdAt,
                        nowUnixSeconds: clock.nowUnixSeconds(),
                      ),
                      style: starling.typography.micro,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: starling.typography.body.copyWith(
                    fontSize: 14,
                    color: starling.colors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky composer, mirroring `CommentInput` but backed by
/// [RoomMessageController].
class _RoomComposer extends ConsumerStatefulWidget {
  const _RoomComposer({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_RoomComposer> createState() => _RoomComposerState();
}

class _RoomComposerState extends ConsumerState<_RoomComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(roomMessageControllerProvider(widget.roomId).notifier)
          .submit(text);
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: starling.colors.paper,
          border: Border(top: BorderSide(color: starling.colors.hairline)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: StarlingInput(
                    controller: _controller,
                    focusNode: _focusNode,
                    placeholder: 'Message…',
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    style: starling.typography.body.copyWith(fontSize: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StarlingIconButton(
                  onPressed: _sending ? null : _submit,
                  semanticLabel: 'Send message',
                  child: Icon(
                    LucideIcons.send,
                    size: 20,
                    color: _sending
                        ? starling.colors.stone
                        : starling.colors.sageDeep,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
