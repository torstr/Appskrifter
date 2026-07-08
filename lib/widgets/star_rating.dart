import 'package:flutter/material.dart';

/// Viser stjerner for en gitt rating (0-5, kan ha desimaler for snitt).
/// Hvis [onRate] er satt, blir stjernene trykkbare slik at brukeren kan gi sin
/// egen vurdering.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.size = 20,
    this.onRate,
  });

  final double rating;
  final double size;
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = rating >= starIndex - 0.5;
        final icon = Icon(
          filled ? Icons.star : Icons.star_border,
          size: size,
          color: Colors.amber.shade700,
        );
        if (onRate == null) return icon;
        return InkWell(
          onTap: () => onRate!(starIndex),
          borderRadius: BorderRadius.circular(size),
          child: Padding(padding: const EdgeInsets.all(2), child: icon),
        );
      }),
    );
  }
}
