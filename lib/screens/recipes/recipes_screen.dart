import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/recipe.dart';
import '../../models/recipe_filter.dart';
import '../../providers/auth_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';
import 'recipe_filter_sheet.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> with SingleTickerProviderStateMixin {
  late final bool _isAdmin;
  late final TabController _tabController;
  final _searchController = TextEditingController();
  RecipeFilter _filter = const RecipeFilter();

  @override
  void initState() {
    super.initState();
    // «Til godkjenning»-fanen er kun nyttig for admin (som faktisk kan godkjenne/avvise), så den
    // tas helt bort for andre i stedet for å bare stå der tom. Lest én gang her (ikke watch) siden
    // isAdmin uansett kun settes manuelt og aldri endrer seg midt i en økt.
    _isAdmin = ref.read(userProfileProvider).value?.isAdmin ?? false;
    _tabController = TabController(length: _isAdmin ? 3 : 2, vsync: this);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    final result = await showRecipeFilterSheet(context, _filter);
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final hiddenTypes = ref.watch(currentHouseholdProvider).value?.hiddenRecipeTypes ?? const {};
    final searchQuery = _searchController.text.trim().toLowerCase();
    // Strømmen er kun lesbar for admin (håndhevet av Firestore-reglene), så den skal ikke en gang
    // startes for andre brukere.
    final pendingCount = _isAdmin ? ref.watch(pendingProposalsProvider).value?.length ?? 0 : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oppskrifter'),
        actions: [
          IconButton(
            tooltip: 'Filtrer',
            onPressed: _openFilterSheet,
            icon: Badge(
              isLabelVisible: _filter.isActive,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Globalt'),
            const Tab(text: 'Mitt sett'),
            if (_isAdmin) Tab(child: _PendingTabLabel(pendingCount: pendingCount)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Søk etter oppskrift',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RecipeListView(
                  provider: globalRecipesProvider,
                  emptyText: 'Ingen godkjente oppskrifter ennå.',
                  filter: _filter,
                  hiddenTypes: hiddenTypes,
                  searchQuery: searchQuery,
                ),
                _RecipeListView(
                  provider: householdRecipesProvider,
                  emptyText: 'Husholdningen har ingen egne oppskrifter ennå.',
                  filter: _filter,
                  hiddenTypes: hiddenTypes,
                  searchQuery: searchQuery,
                ),
                if (_isAdmin)
                  _RecipeListView(
                    provider: pendingProposalsProvider,
                    emptyText: 'Ingen forslag venter på godkjenning.',
                    filter: _filter,
                    hiddenTypes: hiddenTypes,
                    searchQuery: searchQuery,
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'recipes-fab',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecipeEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Ny oppskrift'),
      ),
    );
  }
}

class _PendingTabLabel extends StatelessWidget {
  const _PendingTabLabel({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Til godkjenning'),
        const SizedBox(width: 6),
        Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: const Icon(Icons.admin_panel_settings, size: 16),
        ),
      ],
    );
  }
}

class _RecipeListView extends ConsumerWidget {
  const _RecipeListView({
    required this.provider,
    required this.emptyText,
    required this.filter,
    required this.hiddenTypes,
    required this.searchQuery,
  });

  final StreamProvider<List<Recipe>> provider;
  final String emptyText;
  final RecipeFilter filter;

  /// Oppskriftstyper husholdningen har valgt å skjule som standard i
  /// innstillinger. Overstyres av et eksplisitt type-filter (`filter.types`),
  /// slik at man fortsatt kan lete fram en skjult type ved behov.
  final Set<RecipeType> hiddenTypes;
  final String searchQuery;

  bool _isVisible(Recipe recipe, Map<String, int> myRatings) {
    if (searchQuery.isNotEmpty && !recipe.name.toLowerCase().contains(searchQuery)) {
      return false;
    }
    if (filter.types.isEmpty && hiddenTypes.contains(recipe.type)) {
      return false;
    }
    return filter.matches(recipe, myRating: myRatings[recipe.id]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesState = ref.watch(provider);
    final myRatings = ref.watch(myRatingsMapProvider).value ?? const {};
    return recipesState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
      data: (allRecipes) {
        final recipes = allRecipes.where((r) => _isVisible(r, myRatings)).toList();
        if (recipes.isEmpty) {
          final text = allRecipes.isNotEmpty
              ? 'Ingen oppskrifter matcher søket/filteret.'
              : emptyText;
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: recipes.length,
          itemBuilder: (context, i) {
            final recipe = recipes[i];
            return RecipeCard(
              recipe: recipe,
              myRating: myRatings[recipe.id],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: recipe.id)),
              ),
            );
          },
        );
      },
    );
  }
}
