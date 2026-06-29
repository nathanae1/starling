import 'package:flutter/widgets.dart';

class StarlingIcon extends StatelessWidget {
  const StarlingIcon(this.icon, {super.key, this.size = 20, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: color);
  }
}
