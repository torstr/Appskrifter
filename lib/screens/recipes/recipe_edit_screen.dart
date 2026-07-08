import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../../providers/auth_providers.dart';
import '../../providers/recipe_providers.dart';
import '../../providers/service_providers.dart';
import '../../services/llm_recipe_import.dart';

/// Offentlig, ikke-innlogget side som beskriver JSON-formatet under for en
/// språkmodell — se `web/llm-import.html`.
const _llmImportUrl = 'https://appskrifter.web.app/llm-import.html';

/// Skjema for å opprette en ny oppskrift, redigere en eksisterende
/// privat/foreslått oppskrift som tilhører egen husholdning (eller, for
/// admin, en allerede godkjent global oppskrift), eller lage en variant av
/// en oppskrift: [duplicateFrom] forhåndsutfyller skjemaet men lagrer som en
/// helt ny oppskrift i egen husholdning i stedet for å endre originalen.
class RecipeEditScreen extends ConsumerStatefulWidget {
  const RecipeEditScreen({super.key, this.existingRecipe, this.duplicateFrom});

  final Recipe? existingRecipe;
  final Recipe? duplicateFrom;

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _IngredientRowData {
  _IngredientRowData({
    String name = '',
    this.resolved,
    double quantity = 1,
    this.unit = Unit.stk,
  })  : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(text: quantity == quantity.roundToDouble()
            ? quantity.toStringAsFixed(0)
            : quantity.toString());

  final TextEditingController nameController;
  final TextEditingController quantityController;

  /// Autocomplete krever at focusNode og textEditingController følges ad når
  /// begge settes eksplisitt (ellers kaster widgeten en assertion).
  final FocusNode nameFocusNode = FocusNode();
  Ingredient? resolved;
  Unit unit;
  IngredientCategory newCategory = IngredientCategory.torrvarerOgSauser;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    nameFocusNode.dispose();
  }
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  final _nameController = TextEditingController();
  final _prepTimeController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _yieldNoteController = TextEditingController();
  final List<_IngredientRowData> _rows = [];
  RecipeType _type = RecipeType.middag;
  RecipeUnit _recipeUnit = RecipeUnit.person;
  bool _saving = false;

  bool get _isEditing => widget.existingRecipe != null;

  @override
  void initState() {
    super.initState();
    final recipe = widget.existingRecipe ?? widget.duplicateFrom;
    if (recipe != null) _populateFrom(recipe, trustIngredientIds: true);
    if (_rows.isEmpty) _rows.add(_IngredientRowData());
  }

  /// Fyller ut skjemaet fra et [Recipe]-objekt — brukt både for forhåndsutfylling
  /// ved redigering/variant ([initState]) og for JSON limt inn fra en
  /// språkmodell ([_pasteFromLlm]). [trustIngredientIds] skal kun være sann for
  /// kilder med ekte, verifiserte ingrediens-id-er (redigering/variant). JSON fra
  /// en språkmodell har ingen pålitelig id, så vi forsøker i stedet å slå navnet
  /// opp mot [knownIngredients] (den levende sentrale listen) — uten dette ville
  /// *alle* limte inn ingredienser feilaktig vist seg som «ny ingrediens» i
  /// skjemaet, selv om de faktisk ville blitt gjenbrukt ved lagring (se `_save`).
  void _populateFrom(Recipe recipe, {required bool trustIngredientIds, List<Ingredient>? knownIngredients}) {
    _nameController.text = recipe.name;
    _type = recipe.type;
    _recipeUnit = recipe.recipeUnit;
    _yieldNoteController.text = recipe.yieldNote;
    _prepTimeController.text = recipe.prepTimeMinutes > 0 ? recipe.prepTimeMinutes.toString() : '';
    _instructionsController.text = recipe.instructions;
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    for (final ing in recipe.ingredients) {
      Ingredient? resolved;
      if (trustIngredientIds) {
        resolved = Ingredient(id: ing.ingredientId, name: ing.name, category: ing.category);
      } else if (knownIngredients != null) {
        final lower = ing.name.trim().toLowerCase();
        for (final candidate in knownIngredients) {
          if (candidate.name.trim().toLowerCase() == lower) {
            resolved = candidate;
            break;
          }
        }
      }
      _rows.add(_IngredientRowData(
        name: resolved?.name ?? ing.name,
        resolved: resolved,
        quantity: ing.quantityPerUnit,
        unit: ing.unit,
      )..newCategory = resolved?.category ?? ing.category);
    }
  }

  Future<void> _copyLlmImportLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _llmImportUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lenken er kopiert.')));
    }
  }

  Future<void> _pasteFromLlm() async {
    final hasContent = _nameController.text.trim().isNotEmpty ||
        _rows.any((r) => r.nameController.text.trim().isNotEmpty);
    final controller = TextEditingController();
    final jsonText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lim inn JSON fra språkmodell'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gi språkmodellen denne lenken sammen med en oppskrift (lenke eller bilde):'),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _llmImportUrl,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Kopier lenken',
                    onPressed: () => _copyLlmImportLink(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Lim inn JSON-svaret her...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Fyll ut skjema'),
          ),
        ],
      ),
    );
    if (jsonText == null || jsonText.trim().isEmpty) return;

    if (hasContent && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Erstatte skjemaet?'),
          content: const Text('Innholdet du allerede har fylt ut blir overskrevet.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Erstatt')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final recipe = parseLlmRecipeJson(jsonText);
      final knownIngredients = ref.read(ingredientListProvider).value;
      setState(() {
        _populateFrom(recipe, trustIngredientIds: false, knownIngredients: knownIngredients);
        if (_rows.isEmpty) _rows.add(_IngredientRowData());
      });
    } on LlmRecipeImportException catch (e) {
      _showError(e.message);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _prepTimeController.dispose();
    _instructionsController.dispose();
    _yieldNoteController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_IngredientRowData()));

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Oppskriften må ha et navn.');
      return;
    }
    final validRows = _rows.where((r) => r.nameController.text.trim().isNotEmpty).toList();
    if (validRows.isEmpty) {
      _showError('Legg til minst én ingrediens.');
      return;
    }

    setState(() => _saving = true);
    try {
      final ingredientService = ref.read(ingredientServiceProvider);
      final ingredients = <RecipeIngredient>[];
      for (final row in validRows) {
        final typedName = row.nameController.text.trim();
        Ingredient ingredient;
        if (row.resolved != null && row.resolved!.name == typedName) {
          ingredient = row.resolved!;
        } else {
          ingredient = await ingredientService.findOrCreate(typedName, row.newCategory);
        }
        final quantity = double.tryParse(row.quantityController.text.replaceAll(',', '.')) ?? 0;
        ingredients.add(RecipeIngredient(
          ingredientId: ingredient.id,
          name: ingredient.name,
          category: ingredient.category,
          quantityPerUnit: quantity,
          unit: row.unit,
        ));
      }

      final prepTime = int.tryParse(_prepTimeController.text) ?? 0;
      final instructions = _instructionsController.text.trim();
      final yieldNote = _yieldNoteController.text.trim();

      if (_isEditing) {
        final profile = ref.read(userProfileProvider).value;
        final householdId = profile?.householdId ?? widget.existingRecipe!.ownerHouseholdId ?? '';
        final recipeService = ref.read(recipeServiceProvider);
        if (await recipeService.nameExistsInScope(
          name,
          householdId,
          excludeRecipeId: widget.existingRecipe!.id,
        )) {
          _showError('Det finnes allerede en oppskrift med navnet «$name». Velg et annet navn.');
          return;
        }
        final updated = widget.existingRecipe!.copyWith(
          name: name,
          type: _type,
          recipeUnit: _recipeUnit,
          yieldNote: yieldNote,
          prepTimeMinutes: prepTime,
          instructions: instructions,
          ingredients: ingredients,
        );
        await ref.read(recipeServiceProvider).updateRecipe(updated);
      } else {
        final profile = ref.read(userProfileProvider).value;
        final householdId = profile?.householdId;
        if (householdId == null) {
          _showError('Du må være med i en husholdning for å lage oppskrifter.');
          return;
        }
        final recipeService = ref.read(recipeServiceProvider);
        if (await recipeService.nameExistsInScope(name, householdId)) {
          _showError('Det finnes allerede en oppskrift med navnet «$name». Velg et annet navn.');
          return;
        }
        await recipeService.createRecipe(
              name: name,
              type: _type,
              recipeUnit: _recipeUnit,
              yieldNote: yieldNote,
              prepTimeMinutes: prepTime,
              instructions: instructions,
              ingredients: ingredients,
              ownerHouseholdId: householdId,
              createdByUid: profile!.uid,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Klarte ikke å lagre: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ingredientsAsync = ref.watch(ingredientListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? 'Rediger oppskrift'
            : (widget.duplicateFrom != null ? 'Lag variant' : 'Ny oppskrift')),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Lim inn JSON fra språkmodell',
              onPressed: _pasteFromLlm,
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Navn på retten', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<RecipeType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: RecipeType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.displayName)))
                      .toList(),
                  onChanged: (t) => setState(() => _type = t ?? _type),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<RecipeUnit>(
                  initialValue: _recipeUnit,
                  decoration: const InputDecoration(labelText: 'Mengder oppgitt per', border: OutlineInputBorder()),
                  items: RecipeUnit.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.displayName)))
                      .toList(),
                  onChanged: (u) => setState(() => _recipeUnit = u ?? _recipeUnit),
                ),
              ),
            ],
          ),
          if (_recipeUnit == RecipeUnit.porsjon) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _yieldNoteController,
              decoration: const InputDecoration(
                labelText: 'Hva gir én porsjon? (valgfritt)',
                hintText: 'f.eks. «ca. 18 kjeks»',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _prepTimeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Tilberedningstid (minutter)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Text(
            'Ingredienser (per ${_recipeUnit.displayName.toLowerCase()})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ingredientsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => Text('Klarte ikke å laste ingrediensliste: $e'),
            data: (allIngredients) => Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  _IngredientRowEditor(
                    key: ObjectKey(_rows[i]),
                    row: _rows[i],
                    allIngredients: allIngredients,
                    onChanged: () => setState(() {}),
                    onRemove: _rows.length > 1 ? () => _removeRow(i) : null,
                  ),
              ],
            ),
          ),
          TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Legg til ingrediens')),
          const SizedBox(height: 24),
          Text('Fremgangsmåte', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _instructionsController,
            maxLines: 8,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Beskriv stegene i oppskriften'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _IngredientRowEditor extends StatefulWidget {
  const _IngredientRowEditor({
    super.key,
    required this.row,
    required this.allIngredients,
    required this.onChanged,
    required this.onRemove,
  });

  final _IngredientRowData row;
  final List<Ingredient> allIngredients;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  State<_IngredientRowEditor> createState() => _IngredientRowEditorState();
}

class _IngredientRowEditorState extends State<_IngredientRowEditor> {
  @override
  void initState() {
    super.initState();
    widget.row.nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    widget.row.nameController.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    final row = widget.row;
    if (row.resolved != null && row.resolved!.name != row.nameController.text) {
      row.resolved = null;
      widget.onChanged();
    } else {
      // Trigger a rebuild so the "ny ingrediens"-kategorivelger vises/skjules.
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final allIngredients = widget.allIngredients;
    final onChanged = widget.onChanged;
    final onRemove = widget.onRemove;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Autocomplete<Ingredient>(
                  textEditingController: row.nameController,
                  focusNode: row.nameFocusNode,
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) return const Iterable.empty();
                    return allIngredients.where((ing) => ing.name.toLowerCase().contains(query));
                  },
                  displayStringForOption: (ing) => ing.name,
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Ingrediens', border: OutlineInputBorder(), isDense: true),
                    );
                  },
                  onSelected: (ing) {
                    row.resolved = ing;
                    row.nameController.text = ing.name;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: row.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mengde', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<Unit>(
                  initialValue: row.unit,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: Unit.values
                      .map((u) => DropdownMenuItem(value: u, child: Text(u.displayName)))
                      .toList(),
                  onChanged: (u) {
                    if (u != null) {
                      row.unit = u;
                      onChanged();
                    }
                  },
                ),
              ),
              if (onRemove != null)
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onRemove),
            ],
          ),
          if (row.resolved == null && row.nameController.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(
                children: [
                  const Text('Ny ingrediens – kategori:', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  DropdownButton<IngredientCategory>(
                    value: row.newCategory,
                    items: IngredientCategory.values
                        .where((c) => c != IngredientCategory.annet)
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                        .toList(),
                    onChanged: (c) {
                      if (c != null) {
                        row.newCategory = c;
                        onChanged();
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
