import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/ingredient.dart';
import '../../models/recipe_filter.dart';
import '../../providers/recipe_providers.dart';
import '../../widgets/star_rating.dart';

const _prepTimeOptions = [15, 30, 45, 60, 90];

/// Bunnark for å velge filter på oppskriftslistene: ingredienser (ELLER),
/// minimums-rating og maks tilberedningstid. Filteret rapporteres fortløpende
/// via [onChanged] mens brukeren justerer det, ikke bare når «Bruk filter»
/// trykkes — slik får et tap utenfor arket (vanlig dismiss) samme effekt som
/// å trykke «Bruk filter», i stedet for å forkaste endringene.
Future<void> showRecipeFilterSheet(
  BuildContext context,
  RecipeFilter current, {
  required ValueChanged<RecipeFilter> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecipeFilterSheet(initial: current, onChanged: onChanged),
  );
}

class _RecipeFilterSheet extends ConsumerStatefulWidget {
  const _RecipeFilterSheet({required this.initial, required this.onChanged});

  final RecipeFilter initial;
  final ValueChanged<RecipeFilter> onChanged;

  @override
  ConsumerState<_RecipeFilterSheet> createState() => _RecipeFilterSheetState();
}

class _RecipeFilterSheetState extends ConsumerState<_RecipeFilterSheet> {
  late Set<String> _ingredientIds = {...widget.initial.ingredientIds};
  late int _minRating = widget.initial.minRating;
  late int? _maxPrepMinutes = widget.initial.maxPrepMinutes;
  late Set<RecipeType> _types = {...widget.initial.types};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  RecipeFilter get _currentFilter => RecipeFilter(
        ingredientIds: _ingredientIds,
        minRating: _minRating,
        maxPrepMinutes: _maxPrepMinutes,
        types: _types,
      );

  /// Kjør etter enhver endring av filtertilstanden: oppdaterer skjermen bak
  /// arket med det samme, slik at enhver måte å lukke arket på (knapp,
  /// tap utenfor, tilbake-knapp) etterlater riktig filter.
  void _setAndReport(VoidCallback update) {
    setState(update);
    widget.onChanged(_currentFilter);
  }

  void _apply() => Navigator.of(context).pop();

  void _reset() {
    _setAndReport(() {
      _ingredientIds = {};
      _minRating = 0;
      _maxPrepMinutes = null;
      _types = {};
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final allIngredients = ref.watch(ingredientListProvider).value ?? const <Ingredient>[];
    final query = _searchController.text.trim().toLowerCase();
    final selected = allIngredients.where((i) => _ingredientIds.contains(i.id)).toList();
    final unselectedMatches = allIngredients
        .where((i) => !_ingredientIds.contains(i.id))
        .where((i) => query.isEmpty || i.name.toLowerCase().contains(query))
        .take(30)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filtrer oppskrifter', style: Theme.of(context).textTheme.titleLarge),
                TextButton(onPressed: _reset, child: const Text('Nullstill')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in RecipeType.values)
                  FilterChip(
                    label: Text(type.displayName),
                    selected: _types.contains(type),
                    onSelected: (selected) => _setAndReport(() {
                      if (selected) {
                        _types.add(type);
                      } else {
                        _types.remove(type);
                      }
                    }),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Ingredienser (inneholder minst én av)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final ing in selected)
                    Chip(
                      label: Text(ing.name),
                      onDeleted: () => _setAndReport(() => _ingredientIds.remove(ing.id)),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Søk etter ingrediens',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final ing in unselectedMatches)
                  ActionChip(
                    label: Text(ing.name),
                    onPressed: () => _setAndReport(() => _ingredientIds.add(ing.id)),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Minst din vurdering', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                StarRating(
                  rating: _minRating.toDouble(),
                  size: 32,
                  onRate: (stars) => _setAndReport(() => _minRating = _minRating == stars ? 0 : stars),
                ),
                const SizedBox(width: 12),
                Text(_minRating == 0 ? 'Alle' : '$_minRating+ stjerner'),
              ],
            ),
            const Divider(height: 32),
            Text('Maks tilberedningstid', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _maxPrepMinutes == null,
                  onSelected: (_) => _setAndReport(() => _maxPrepMinutes = null),
                ),
                for (final minutes in _prepTimeOptions)
                  ChoiceChip(
                    label: Text('≤ $minutes min'),
                    selected: _maxPrepMinutes == minutes,
                    onSelected: (_) => _setAndReport(() => _maxPrepMinutes = minutes),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _apply, child: const Text('Bruk filter')),
          ],
        );
      },
    );
  }
}
