import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/recipe.dart';
import 'star_rating.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    this.myRating,
  });

  final Recipe recipe;
  final VoidCallback onTap;

  /// Innlogget brukers egen vurdering av oppskriften, hvis noen.
  final int? myRating;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.restaurant, size: 32),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(recipe.name, style: Theme.of(context).textTheme.titleMedium),
                    if (recipe.type != RecipeType.middag) ...[
                      const SizedBox(height: 2),
                      Text(
                        recipe.type.displayName,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                    if (myRating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StarRating(rating: myRating!.toDouble(), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Din vurdering',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                    if (recipe.prepTimeMinutes > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 14),
                          const SizedBox(width: 4),
                          Text('${recipe.prepTimeMinutes} min', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
