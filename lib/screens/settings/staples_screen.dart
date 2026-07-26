import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ingredient.dart';
import '../../providers/auth_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/shopping_lists_providers.dart';

/// Administrasjon av en handlelistes standardvarer: ingredienser som antas å
/// alltid være i hyllen (salt, pepper, olivenolje osv.) og derfor utelates
/// fra genererte handlelister, se `ShoppingListService.generateFromMealPlan`.
class StaplesScreen extends ConsumerStatefulWidget {
  const StaplesScreen({super.key});

  @override
  ConsumerState<StaplesScreen> createState() => _StaplesScreenState();
}

class _StaplesScreenState extends ConsumerState<StaplesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String householdId, String listId, Set<String> current, String ingredientId, bool checked) {
    final updated = {...current};
    if (checked) {
      updated.add(ingredientId);
    } else {
      updated.remove(ingredientId);
    }
    ref.read(shoppingListsServiceProvider).updateStaples(householdId, listId, updated);
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(userProfileProvider).value?.householdId;
    final list = ref.watch(currentListProvider);
    if (householdId == null || list == null) return const SizedBox.shrink();

    final allIngredients = ref.watch(ingredientListProvider).value ?? const <Ingredient>[];
    final query = _searchController.text.trim().toLowerCase();
    final staples = list.staples;

    final selected = allIngredients.where((i) => staples.contains(i.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final unselectedMatches = allIngredients
        .where((i) => !staples.contains(i.id))
        .where((i) => query.isEmpty || i.name.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Standardvarer')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Ingredienser dere alltid antar å ha i hyllen (f.eks. salt, pepper, olivenolje). '
              'De dukker aldri opp i en generert handleliste, selv om en oppskrift bruker dem.',
            ),
          ),
          if (selected.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final ing in selected)
                      Chip(
                        label: Text(ing.name),
                        onDeleted: () => _toggle(householdId, list.id, staples, ing.id, false),
                      ),
                  ],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Søk etter ingrediens',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: unselectedMatches.length,
              itemBuilder: (context, i) {
                final ing = unselectedMatches[i];
                return CheckboxListTile(
                  title: Text(ing.name),
                  subtitle: Text(ing.category.displayName),
                  value: false,
                  onChanged: (checked) => _toggle(householdId, list.id, staples, ing.id, checked ?? false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
