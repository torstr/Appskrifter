import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/manual_item_history_entry.dart';
import '../models/meal_plan_item.dart';
import '../models/recipe.dart';
import '../models/shopping_list_item.dart';

class ShoppingListService {
  ShoppingListService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore batch-grense er 500 operasjoner.
  static const _maxBatchOps = 500;

  CollectionReference<Map<String, dynamic>> _items(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('shoppingListItems');

  CollectionReference<Map<String, dynamic>> _history(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('manualItemHistory');

  /// Doc-id for en historikk-oppføring: en trygg, deterministisk nøkkel basert
  /// på navnet, slik at samme vare (uavhengig av store/små bokstaver) alltid
  /// oppdaterer samme oppføring i stedet for å hope seg opp som duplikater.
  String _historyKey(String name) {
    final safe = name.trim().toLowerCase().replaceAll(RegExp(r'[/\s]+'), '-');
    return safe.isEmpty ? 'vare' : safe;
  }

  /// Strømmer husholdningens historikk over tidligere manuelt tillagte varer,
  /// brukt som forslag når man legger til en ny vare.
  Stream<List<ManualItemHistoryEntry>> manualItemHistoryStream(String householdId) {
    return _history(householdId).orderBy('nameLowercase').snapshots().map(
          (snap) => snap.docs.map(ManualItemHistoryEntry.fromFirestore).toList(),
        );
  }

  /// Oppdaterer en historikk-oppføring. Siden dokument-id-en er avledet fra
  /// navnet, flyttes oppføringen til en ny dokument-id hvis navnet endres
  /// (gammel slettes, ny opprettes) — ellers oppdateres samme dokument.
  Future<void> updateHistoryEntry(
    String householdId,
    String oldName,
    ManualItemHistoryEntry updated,
  ) async {
    final oldKey = _historyKey(oldName);
    final newKey = _historyKey(updated.name);
    if (oldKey != newKey) {
      await _history(householdId).doc(oldKey).delete();
    }
    await _history(householdId).doc(newKey).set(updated.toMap());
  }

  Future<void> deleteHistoryEntry(String householdId, String name) async {
    await _history(householdId).doc(_historyKey(name)).delete();
  }

  /// Strømmer handlelisten sortert etter kategori
  /// (frukt/grønt → kjøtt → meieri → tørrvarer/sauser → annet), deretter navn.
  Stream<List<ShoppingListItem>> shoppingListStream(String householdId) {
    return _items(householdId).snapshots().map((snap) {
      final items = snap.docs.map(ShoppingListItem.fromFirestore).toList();
      items.sort((a, b) {
        final categoryCompare = a.category.index.compareTo(b.category.index);
        if (categoryCompare != 0) return categoryCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return items;
    });
  }

  /// Genererer handlelisten på nytt fra husholdningens middagsplan. Like
  /// ingredienser (samme ingrediens og enhet) slås sammen på tvers av valgte
  /// middager, og mengden skaleres lineært med antall personer (eller
  /// porsjoner, for bakeoppskrifter) for hver middag. Manuelt tillagte varer
  /// som ikke er krysset av beholdes uendret
  /// (de er fortsatt relevante); manuelt tillagte varer som ER krysset av
  /// (dvs. kjøpt) fjernes, i likhet med alle oppskrift-avledede varer som
  /// alltid bygges opp helt på nytt. Ingredienser i [staples] (husholdningens
  /// standardvarer, f.eks. salt/pepper — antas alltid å være i hyllen)
  /// utelates helt fra den genererte listen.
  Future<void> generateFromMealPlan(
    String householdId,
    List<MealPlanItem> mealPlanItems,
    List<Recipe> recipesById, {
    Set<String> staples = const {},
  }) async {
    final recipeMap = {for (final r in recipesById) r.id: r};

    // key: "ingredientId|unitName" for ingredienser, "manual navn" håndteres separat.
    final aggregated = <String, _AggregatedLine>{};
    for (final mealItem in mealPlanItems) {
      final recipe = recipeMap[mealItem.recipeId];
      if (recipe == null) continue;
      for (final ingredient in recipe.ingredients) {
        if (staples.contains(ingredient.ingredientId)) continue;
        final key = '${ingredient.ingredientId}|${ingredient.unit.name}';
        final totalQuantity = ingredient.quantityPerUnit * mealItem.servings;
        final existing = aggregated[key];
        if (existing == null) {
          aggregated[key] = _AggregatedLine(
            ingredientId: ingredient.ingredientId,
            name: ingredient.name,
            category: ingredient.category,
            unit: ingredient.unit,
            quantity: totalQuantity,
          );
        } else {
          existing.quantity += totalQuantity;
        }
      }
    }

    final existingSnap = await _items(householdId).get();

    final toDelete = <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in existingSnap.docs) {
      final item = ShoppingListItem.fromFirestore(doc);
      final keep = item.manual && !item.checked;
      if (!keep) {
        toDelete.add(doc.reference);
      }
    }
    await _deleteInBatches(toDelete);

    final newItems = aggregated.values.map(
      (line) => ShoppingListItem(
        id: '',
        name: line.name,
        category: line.category,
        quantity: line.quantity,
        unit: line.unit,
        checked: false,
        manual: false,
        ingredientId: line.ingredientId,
      ),
    );
    await _createInBatches(householdId, newItems);
  }

  Future<void> _deleteInBatches(List<DocumentReference<Map<String, dynamic>>> refs) async {
    for (var i = 0; i < refs.length; i += _maxBatchOps) {
      final batch = _firestore.batch();
      for (final ref in refs.skip(i).take(_maxBatchOps)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  Future<void> _createInBatches(String householdId, Iterable<ShoppingListItem> items) async {
    final list = items.toList();
    for (var i = 0; i < list.length; i += _maxBatchOps) {
      final batch = _firestore.batch();
      for (final item in list.skip(i).take(_maxBatchOps)) {
        batch.set(_items(householdId).doc(), item.toMap());
      }
      await batch.commit();
    }
  }

  Future<void> addManualItem(
    String householdId, {
    required String name,
    required IngredientCategory category,
    double? quantity,
    Unit? unit,
  }) async {
    final item = ShoppingListItem(
      id: '',
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
      checked: false,
      manual: true,
    );
    await _items(householdId).add(item.toMap());

    final historyEntry = ManualItemHistoryEntry(
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
    );
    await _history(householdId).doc(_historyKey(name)).set(historyEntry.toMap());
  }

  Future<void> setChecked(String householdId, String itemId, bool checked) async {
    await _items(householdId).doc(itemId).update({'checked': checked});
  }

  Future<void> removeItem(String householdId, String itemId) async {
    await _items(householdId).doc(itemId).delete();
  }

  Future<void> clearAll(String householdId) async {
    final snap = await _items(householdId).get();
    await _deleteInBatches(snap.docs.map((d) => d.reference).toList());
  }

  /// Fjerner alle avkryssede varer (kjøpt), både oppskrift-avledede og
  /// manuelt tillagte — for å rydde opp i handlelisten uten å tømme alt.
  Future<void> removeChecked(String householdId) async {
    final snap = await _items(householdId).where('checked', isEqualTo: true).get();
    await _deleteInBatches(snap.docs.map((d) => d.reference).toList());
  }

  /// Fjerner alle oppskrift-avledede varer (`manual == false`), uten å røre
  /// manuelt tillagte varer. Brukt til å tømme rester av en tidligere
  /// generert handleliste når middagsplanen er tømt, uten en ny
  /// «Generer handleliste»-kjøring å bygge opp igjen fra.
  Future<void> removeRecipeDerivedItems(String householdId) async {
    final snap = await _items(householdId).where('manual', isEqualTo: false).get();
    await _deleteInBatches(snap.docs.map((d) => d.reference).toList());
  }
}

class _AggregatedLine {
  _AggregatedLine({
    required this.ingredientId,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
  });

  final String ingredientId;
  final String name;
  final IngredientCategory category;
  final Unit unit;
  double quantity;
}
