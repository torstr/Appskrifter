import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/meal_plan_item.dart';
import '../../models/recipe.dart';
import '../../providers/auth_providers.dart';
import '../../providers/meal_plan_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../providers/service_providers.dart';
import '../recipes/recipe_detail_screen.dart';

class MealPlanScreen extends ConsumerStatefulWidget {
  const MealPlanScreen({super.key});

  @override
  ConsumerState<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends ConsumerState<MealPlanScreen> {
  bool _generating = false;

  Future<void> _pickRecipe() async {
    final household = ref.read(currentHouseholdProvider).value;
    if (household == null) return;
    final selected = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RecipePickerSheet(),
    );
    if (selected == null) return;
    final servings = selected.recipeUnit == RecipeUnit.porsjon ? 1 : household.defaultServings;
    await ref.read(mealPlanServiceProvider).addRecipe(household.id, selected, servings);
  }

  Future<void> _generateShoppingList(List<MealPlanItem> items) async {
    final household = ref.read(currentHouseholdProvider).value;
    if (household == null || items.isEmpty) return;
    setState(() => _generating = true);
    try {
      final recipeService = ref.read(recipeServiceProvider);
      final recipes = await recipeService.getRecipesByIds(items.map((e) => e.recipeId).toList());
      await ref.read(shoppingListServiceProvider).generateFromMealPlan(
            household.id,
            items,
            recipes,
            staples: household.staples,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Handlelisten er generert. Se fanen «Handleliste».')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Klarte ikke å generere handlelisten: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _confirmClearShoppingList(String householdId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tøm handleliste fra middagsplan?'),
        content: const Text(
          'Fjerner varer generert fra tidligere middager. Manuelt tillagte varer beholdes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tøm')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(shoppingListServiceProvider).removeRecipeDerivedItems(householdId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mealPlanState = ref.watch(mealPlanProvider);
    final householdId = ref.watch(userProfileProvider).value?.householdId;

    return Scaffold(
      appBar: AppBar(title: const Text('Middagsplan')),
      body: mealPlanState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ingen middager valgt ennå. Trykk «Legg til middag» for å komme i gang.',
                      textAlign: TextAlign.center,
                    ),
                    if (householdId != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_remove),
                        label: const Text('Tøm handleliste fra middagsplan'),
                        onPressed: () => _confirmClearShoppingList(householdId),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return ListTile(
                leading: const Icon(Icons.restaurant),
                title: Text(item.recipeName),
                subtitle: Text('${item.servings} ${item.recipeUnit.displayNameFor(item.servings).toLowerCase()}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: item.recipeId)),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: item.servings > 1 && householdId != null
                          ? () => ref.read(mealPlanServiceProvider).updateServings(householdId, item.id, item.servings - 1)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: householdId != null
                          ? () => ref.read(mealPlanServiceProvider).updateServings(householdId, item.id, item.servings + 1)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: householdId != null
                          ? () => ref.read(mealPlanServiceProvider).removeItem(householdId, item.id)
                          : null,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mealPlanState.value?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.extended(
                heroTag: 'generate',
                onPressed: _generating ? null : () => _generateShoppingList(mealPlanState.value!),
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long),
                label: const Text('Generer handleliste'),
              ),
            ),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _pickRecipe,
            icon: const Icon(Icons.add),
            label: const Text('Legg til middag'),
          ),
        ],
      ),
    );
  }
}

class _RecipePickerSheet extends ConsumerStatefulWidget {
  const _RecipePickerSheet();

  @override
  ConsumerState<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends ConsumerState<_RecipePickerSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            TabBar(controller: _tabController, tabs: const [Tab(text: 'Globalt'), Tab(text: 'Mitt sett')]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PickerList(provider: globalRecipesProvider, scrollController: scrollController),
                  _PickerList(provider: householdRecipesProvider, scrollController: scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PickerList extends ConsumerWidget {
  const _PickerList({required this.provider, required this.scrollController});

  final StreamProvider<List<Recipe>> provider;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
      data: (recipes) => ListView.builder(
        controller: scrollController,
        itemCount: recipes.length,
        itemBuilder: (context, i) {
          final recipe = recipes[i];
          return ListTile(
            leading: const Icon(Icons.restaurant),
            title: Text(recipe.name),
            onTap: () => Navigator.of(context).pop(recipe),
          );
        },
      ),
    );
  }
}
