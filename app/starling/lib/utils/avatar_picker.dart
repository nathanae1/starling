import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../screens/profile/avatar_crop_screen.dart';
import '../theme/starling_theme.dart';
import '../widgets/sheet.dart';

/// Prompts for an avatar source (gallery or camera), picks an image via
/// `image_picker` (the same picker the compose flow uses — no Google Play
/// Services / ML Kit dependency), then runs the interactive square cropper.
/// Returns the cropped image bytes, or null if cancelled at any step.
Future<Uint8List?> pickAndCropAvatar(BuildContext context) async {
  final source = await _pickSource(context);
  if (source == null || !context.mounted) return null;

  final XFile? file = await ImagePicker().pickImage(
    source: source,
    imageQuality: 100,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;

  return Navigator.of(context, rootNavigator: true).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropScreen(imageBytes: bytes),
    ),
  );
}

Future<ImageSource?> _pickSource(BuildContext context) {
  return showStarlingSheet<ImageSource>(
    context: context,
    builder: (ctx) => const _AvatarSourceSheet(),
  );
}

class _AvatarSourceSheet extends StatelessWidget {
  const _AvatarSourceSheet();

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Profile photo', style: starling.typography.h2),
        const SizedBox(height: 12),
        _SourceRow(
          icon: LucideIcons.image,
          label: 'Choose from gallery',
          onTap: () => Navigator.of(context).pop(ImageSource.gallery),
        ),
        _SourceRow(
          icon: LucideIcons.camera,
          label: 'Take a photo',
          onTap: () => Navigator.of(context).pop(ImageSource.camera),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: starling.colors.ink),
            const SizedBox(width: 14),
            Text(label, style: starling.typography.body),
          ],
        ),
      ),
    );
  }
}
