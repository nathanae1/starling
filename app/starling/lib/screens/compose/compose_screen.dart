import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/compose_provider.dart';
import '../../theme/starling_theme.dart';
import '../../widgets/buttons.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/inputs.dart';
import '../../widgets/starling_alert_dialog.dart';
import '../../widgets/sticky_action_bar.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _captionCtrl;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(
      text: ref.read(composeControllerProvider).caption,
    );
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  bool get _dirty {
    final state = ref.read(composeControllerProvider);
    return state.caption.trim().isNotEmpty || state.photoBytes != null;
  }

  /// One discard policy for both exits: Cancel and the system back gesture
  /// confirm before dropping a dirty draft; discard invalidates the
  /// keepAlive provider so the draft doesn't silently survive.
  Future<void> _close() async {
    if (_dirty) {
      final discard = await showStarlingConfirm(
        context,
        title: 'Discard post?',
        message: 'Your photo and caption will be lost.',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep editing',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    ref.invalidate(composeControllerProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    // Keep the caption field in sync when the provider's caption is reset
    // elsewhere (e.g. invalidated after publish). Deferred to a post-frame
    // callback so mutating the TextEditingController can't trigger
    // AnimatedBuilder.setState during an ancestor's build cycle.
    ref.listen<ComposeState>(composeControllerProvider, (prev, next) {
      if (_captionCtrl.text != next.caption) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_captionCtrl.text != next.caption) {
            _captionCtrl.value = TextEditingValue(
              text: next.caption,
              selection: TextSelection.collapsed(offset: next.caption.length),
            );
          }
        });
      }
    });
    final state = ref.watch(composeControllerProvider);
    final controller = ref.read(composeControllerProvider.notifier);
    final dirty = state.caption.trim().isNotEmpty || state.photoBytes != null;

    return PopScope(
      // Clean drafts pop straight through (and get invalidated below, same
      // as Cancel); dirty ones are held for the "Discard post?" confirm.
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.invalidate(composeControllerProvider);
          return;
        }
        _close();
      },
      child: Scaffold(
        backgroundColor: starling.colors.paper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Slim title bar; the close + advance actions live in the bottom
              // StickyActionBar so they sit within thumb reach.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Text(
                  'New post',
                  textAlign: TextAlign.center,
                  style: starling.typography.h3.copyWith(
                    fontFamily: 'Fraunces',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: _PhotoSlot(
                          state: state,
                          onGallery: controller.pickFromGallery,
                          onCamera: controller.pickFromCamera,
                          onClear: controller.clearPhoto,
                        ),
                      ),
                      const SizedBox(height: 20),
                      StarlingTextarea(
                        controller: _captionCtrl,
                        placeholder: 'Say something…',
                        minLines: 3,
                        maxLines: 8,
                        onChanged: controller.setCaption,
                      ),
                      if (state.photoBytes == null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Add a photo to post.',
                          textAlign: TextAlign.center,
                          style: starling.typography.small.copyWith(
                            color: starling.colors.stone,
                          ),
                        ),
                      ],
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.errorMessage!,
                          style: starling.typography.small.copyWith(
                            color: starling.colors.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              StickyActionBar(
                child: Row(
                  children: [
                    GhostButton(label: 'Cancel', onPressed: _close),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Next',
                        block: true,
                        onPressed: state.canAdvanceToPreview
                            ? () => context.push('/compose/preview')
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.state,
    required this.onGallery,
    required this.onCamera,
    required this.onClear,
  });

  final ComposeState state;
  final Future<void> Function() onGallery;
  final Future<void> Function() onCamera;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final bytes = state.photoBytes;
    if (bytes != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: starling.colors.hairline),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _ClearPhotoButton(onPressed: onClear),
          ),
        ],
      );
    }

    return DashedBorder(
      color: starling.colors.hairline,
      child: Container(
        color: starling.colors.linen.withValues(alpha: 0.4),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.camera, size: 32, color: starling.colors.stone),
            const SizedBox(height: 8),
            Text(
              'Choose a photo',
              style: starling.typography.body.copyWith(
                color: starling.colors.stone,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SecondaryButton(
                  label: 'Gallery',
                  leading: const Icon(LucideIcons.image, size: 16),
                  onPressed: state.phase == ComposePhase.picking
                      ? null
                      : onGallery,
                ),
                const SizedBox(width: 12),
                SecondaryButton(
                  label: 'Camera',
                  leading: const Icon(LucideIcons.camera, size: 16),
                  onPressed: state.phase == ComposePhase.picking
                      ? null
                      : onCamera,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearPhotoButton extends StatelessWidget {
  const _ClearPhotoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Semantics(
      button: true,
      label: 'Remove photo',
      child: Material(
        color: starling.colors.ink.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(LucideIcons.x, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
