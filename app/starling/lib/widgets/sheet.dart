import 'package:flutter/material.dart';

import '../theme/starling_theme.dart';

Future<T?> showStarlingSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
}) {
  final starling = StarlingTheme.of(context);
  // A caller-supplied transition controller is NOT owned by the route — we
  // must dispose it ourselves, and only after the exit animation (which it
  // drives) fully settles. Every sheet in the app routes through here, so
  // this used to leak one ticker per sheet shown.
  final controller = AnimationController(
    vsync: Navigator.of(context),
    duration: const Duration(milliseconds: 280),
  );
  final result = showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: starling.colors.shadowInk.withValues(alpha: 0.35),
    transitionAnimationController: controller,
    builder: (ctx) => StarlingSheet(child: Builder(builder: builder)),
  );
  result.whenComplete(() {
    // The future resolves at pop; the reverse animation may still be
    // running on this controller.
    if (controller.status == AnimationStatus.dismissed) {
      controller.dispose();
    } else {
      late final void Function(AnimationStatus) onStatus;
      onStatus = (status) {
        if (status == AnimationStatus.dismissed) {
          controller.removeStatusListener(onStatus);
          controller.dispose();
        }
      };
      controller.addStatusListener(onStatus);
    }
  });
  return result;
}

class StarlingSheet extends StatelessWidget {
  const StarlingSheet({
    super.key,
    required this.child,
    this.maxHeightFactor = 0.85,
  });

  final Widget child;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final starling = StarlingTheme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(top: media.padding.top),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: media.size.height * maxHeightFactor,
        ),
        decoration: BoxDecoration(
          color: starling.colors.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: starling.colors.shadowInk.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: starling.colors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: SingleChildScrollView(child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
