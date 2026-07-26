import 'package:flutter/material.dart';

import '../models/enums.dart';

/// Selve fargeverdiene bak [ListColor] — hører hjemme i UI-laget, ikke i
/// modellen (se `ListColor` i `lib/models/enums.dart`).
extension ListColorMaterial on ListColor {
  Color get materialColor => switch (this) {
        ListColor.gronn => Colors.green,
        ListColor.bla => Colors.blue,
        ListColor.oransje => Colors.orange,
        ListColor.lilla => Colors.purple,
        ListColor.rosa => Colors.pink,
        ListColor.gul => Colors.amber,
      };
}

/// En liten fylt sirkel som viser en handlelistes farge, brukt i
/// listevelgere og administrasjonsskjermen for handlelister.
class ListColorDot extends StatelessWidget {
  const ListColorDot({super.key, required this.color, this.size = 14});

  final ListColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.materialColor, shape: BoxShape.circle),
    );
  }
}
