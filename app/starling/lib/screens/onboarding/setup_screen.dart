import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/profile_provider.dart';
import '../../theme/starling_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/avatar_picker.dart';
import '../../widgets/avatar.dart';
import '../../widgets/buttons.dart';
import '../../widgets/inputs.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _controller = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      ref
          .read(onboardingProfileControllerProvider.notifier)
          .setDisplayName(_controller.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canContinue => _controller.text.trim().isNotEmpty && !_creating;

  Future<void> _pickAvatar() async {
    final bytes = await pickAndCropAvatar(context);
    if (bytes == null || !mounted) return;
    ref
        .read(onboardingProfileControllerProvider.notifier)
        .setAvatarBytes(bytes);
  }

  Future<void> _onContinue() async {
    setState(() => _creating = true);
    try {
      await ref.read(onboardingControllerProvider.notifier).createIdentity();
      if (!mounted) return;
      context.go('/onboarding/recovery');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, tag: 'create_identity'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final name = _controller.text.trim();
    final avatarBytes = ref
        .watch(onboardingProfileControllerProvider)
        .avatarBytes;

    return Scaffold(
      backgroundColor: starling.colors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarlingIconButton(
                // Gated while creating: backing out mid-create would land on
                // Welcome, and once the identity reload finishes the router
                // would bounce past the recovery screen entirely.
                onPressed: _creating
                    ? null
                    : () => context.go('/onboarding/welcome'),
                semanticLabel: 'Back',
                child: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
              const SizedBox(height: 18),
              Text(
                'Pick a name and photo',
                style: starling.typography.h1.copyWith(
                  fontSize: 28,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Just for your friends. You can change it anytime.',
                style: starling.typography.small,
              ),
              const SizedBox(height: 36),
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(
                        name: name.isEmpty ? 'You' : name,
                        color: starling.colors.clay,
                        size: AvatarSize.lg,
                        imageProvider: avatarBytes != null
                            ? MemoryImage(avatarBytes)
                            : null,
                      ),
                      Positioned(
                        bottom: -4,
                        right: -4,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: starling.colors.paper,
                            shape: BoxShape.circle,
                            border: Border.all(color: starling.colors.hairline),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            LucideIcons.camera,
                            size: 16,
                            color: starling.colors.graphite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const StarlingFieldLabel('Display name'),
              const SizedBox(height: 6),
              StarlingInput(
                controller: _controller,
                placeholder: 'Sam',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_canContinue) _onContinue();
                },
              ),
              const Spacer(),
              PrimaryButton(
                label: _creating ? 'Creating…' : 'Continue',
                block: true,
                onPressed: _canContinue ? _onContinue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
