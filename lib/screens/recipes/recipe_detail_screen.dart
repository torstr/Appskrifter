import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/enums.dart';
import '../../models/recipe.dart';
import '../../providers/auth_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/shopping_lists_providers.dart';
import '../../services/device_settings_service.dart';
import '../../utils/quantity_formatter.dart';
import '../../widgets/star_rating.dart';
import 'recipe_edit_screen.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  int? _servings;
  bool _keepScreenOn = false;
  Timer? _wakeLockTimer;

  @override
  void dispose() {
    _wakeLockTimer?.cancel();
    if (_keepScreenOn) WakelockPlus.disable();
    super.dispose();
  }

  /// Slår «hold skjermen på» av/på. Slås automatisk av igjen etter
  /// [minutes] minutter, i tillegg til når skjermen lukkes (se [dispose]).
  Future<void> _setKeepScreenOn(bool value, int minutes) async {
    _wakeLockTimer?.cancel();
    setState(() => _keepScreenOn = value);
    if (value) {
      await WakelockPlus.enable();
      _wakeLockTimer = Timer(Duration(minutes: minutes), () {
        WakelockPlus.disable();
        if (mounted) setState(() => _keepScreenOn = false);
      });
    } else {
      await WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipeState = ref.watch(recipeByIdProvider(widget.recipeId));
    final profile = ref.watch(userProfileProvider).value;
    final list = ref.watch(currentListProvider);
    final wakeLockMinutes = ref.watch(wakeLockMinutesProvider).value ?? DeviceSettingsService.defaultWakeLockMinutes;

    return Scaffold(
      body: recipeState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Noe gikk galt: $e')),
        data: (recipe) {
          if (recipe == null) {
            return const Center(child: Text('Fant ikke oppskriften.'));
          }
          if (_servings == null) {
            if (recipe.recipeUnit == RecipeUnit.porsjon) {
              _servings = 1;
            } else if (list != null) {
              _servings = list.defaultServings;
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          }
          final servings = _servings!;
          final isOwnHousehold = profile?.householdId != null && recipe.ownerHouseholdId == profile!.householdId;
          final isAdmin = profile?.isAdmin ?? false;
          final canEdit = (isOwnHousehold && recipe.status != RecipeStatus.approved) ||
              (isAdmin && recipe.status == RecipeStatus.approved);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(recipe.name),
                pinned: true,
                actions: [
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RecipeEditScreen(existingRecipe: recipe)),
                      ),
                    ),
                  if (isOwnHousehold && recipe.status != RecipeStatus.approved)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(recipe),
                    ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _RatingSection(recipe: recipe),
                    const SizedBox(height: 16),
                    if (recipe.status == RecipeStatus.pending)
                      _StatusBanner(
                        text: isAdmin
                            ? 'Foreslått som felles oppskrift. Godkjenn eller avvis under.'
                            : 'Venter på godkjenning for det globale settet.',
                      ),
                    if (isAdmin && recipe.status == RecipeStatus.pending) _AdminApprovalActions(recipe: recipe),
                    if (isOwnHousehold && recipe.status == RecipeStatus.private)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_outlined),
                          label: const Text('Foreslå for felles utvalg'),
                          onPressed: () async {
                            await ref.read(recipeServiceProvider).proposeToGlobal(recipe.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Oppskriften er foreslått for det globale settet.')),
                              );
                            }
                          },
                        ),
                      ),
                    if (profile?.householdId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Lag variant av denne oppskriften'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RecipeEditScreen(duplicateFrom: recipe)),
                          ),
                        ),
                      ),
                    if (recipe.prepTimeMinutes > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule),
                            const SizedBox(width: 8),
                            Text('${recipe.prepTimeMinutes} minutter'),
                          ],
                        ),
                      ),
                    if (recipe.recipeUnit == RecipeUnit.porsjon && recipe.yieldNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.bakery_dining_outlined),
                            const SizedBox(width: 8),
                            Text('Én porsjon gir ${recipe.yieldNote}'),
                          ],
                        ),
                      ),
                    _ServingsSelector(
                      unit: recipe.recipeUnit,
                      servings: servings,
                      onChanged: (v) => setState(() => _servings = v),
                    ),
                    const SizedBox(height: 8),
                    Text('Ingredienser', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...recipe.ingredients.map((ing) {
                      final total = ing.quantityPerUnit * servings;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text('${formatQuantity(total)} ${ing.unit.displayNameFor(total)}'),
                            ),
                            Expanded(child: Text(ing.name)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Legg til i middagsplan'),
                      onPressed: (profile?.householdId == null || list == null)
                          ? null
                          : () => _addToMealPlan(recipe, profile!.householdId!, list.id),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _keepScreenOn,
                      title: const Text('Hold skjermen på'),
                      subtitle: Text('I inntil $wakeLockMinutes minutter, eller til du lukker oppskriften.'),
                      onChanged: (checked) => _setKeepScreenOn(checked ?? false, wakeLockMinutes),
                    ),
                    const SizedBox(height: 16),
                    Text('Fremgangsmåte', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(recipe.instructions),
                    const SizedBox(height: 48),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addToMealPlan(Recipe recipe, String householdId, String listId) async {
    final servings = await showDialog<int>(
      context: context,
      builder: (context) => _ServingsDialog(unit: recipe.recipeUnit, initial: _servings ?? 1),
    );
    if (servings == null) return;
    await ref.read(mealPlanServiceProvider).addRecipe(householdId, listId, recipe, servings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${recipe.name} er lagt til i middagsplanen.')),
      );
    }
  }

  Future<void> _confirmDelete(Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slette oppskrift?'),
        content: Text('«${recipe.name}» blir slettet permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Slett')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(recipeServiceProvider).deleteRecipe(recipe.id);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

class _ServingsSelector extends StatelessWidget {
  const _ServingsSelector({required this.unit, required this.servings, required this.onChanged});

  final RecipeUnit unit;
  final int servings;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Antall ${unit.pluralDisplayName.toLowerCase()}:'),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: servings > 1 ? () => onChanged(servings - 1) : null,
        ),
        Text('$servings', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(servings + 1),
        ),
      ],
    );
  }
}

class _ServingsDialog extends StatefulWidget {
  const _ServingsDialog({required this.unit, required this.initial});

  final RecipeUnit unit;
  final int initial;

  @override
  State<_ServingsDialog> createState() => _ServingsDialogState();
}

class _ServingsDialogState extends State<_ServingsDialog> {
  late int _servings = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Antall ${widget.unit.pluralDisplayName.toLowerCase()}'),
      content: _ServingsSelector(
        unit: widget.unit,
        servings: _servings,
        onChanged: (v) => setState(() => _servings = v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
        FilledButton(onPressed: () => Navigator.pop(context, _servings), child: const Text('Legg til')),
      ],
    );
  }
}

class _RatingSection extends ConsumerWidget {
  const _RatingSection({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(userProfileProvider).value?.uid;
    final myRating = uid == null ? null : ref.watch(myRatingProvider(recipe.id)).value;

    if (uid == null) return const SizedBox.shrink();

    return Row(
      children: [
        Text(
          myRating != null ? 'Din vurdering:' : 'Vurder denne oppskriften:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(width: 8),
        StarRating(
          rating: (myRating ?? 0).toDouble(),
          size: 28,
          onRate: (stars) {
            final service = ref.read(recipeServiceProvider);
            if (myRating == stars) {
              service.clearRating(recipe.id, uid);
            } else {
              service.rate(recipe.id, uid, stars);
            }
          },
        ),
        if (myRating != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => ref.read(recipeServiceProvider).clearRating(recipe.id, uid),
            child: const Text('Fjern'),
          ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}

class _AdminApprovalActions extends ConsumerWidget {
  const _AdminApprovalActions({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Godkjenn'),
              onPressed: () => ref.read(recipeServiceProvider).approve(recipe.id),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Avvis'),
              onPressed: () => ref.read(recipeServiceProvider).reject(recipe.id),
            ),
          ),
        ],
      ),
    );
  }
}
