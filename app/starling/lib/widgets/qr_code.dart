import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/starling_theme.dart';

class StarlingQRCode extends StatelessWidget {
  const StarlingQRCode({super.key, required this.data, this.size = 180});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: starling.colors.paper,
        border: Border.all(color: starling.colors.hairline),
        borderRadius: BorderRadius.circular(14),
        boxShadow: starling.colors.shadowSoft,
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: size,
        backgroundColor: starling.colors.paper,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: starling.colors.ink,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: starling.colors.ink,
        ),
      ),
    );
  }
}
