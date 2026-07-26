import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/shopping_list.dart';

/// Feil kastet av handleliste-administrasjon, med en norsk brukervennlig melding.
class ShoppingListsException implements Exception {
  ShoppingListsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Administrasjon av selve handlelistene i en husholdning (opprette, gi navn,
/// farge, standardinnstillinger, slette) — ikke varene i dem, se
/// `ShoppingListService` for det. En husholdning har alltid minst én liste.
class ShoppingListsService {
  ShoppingListsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Firestore batch-grense er 500 operasjoner.
  static const _maxBatchOps = 500;

  CollectionReference<Map<String, dynamic>> _lists(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('shoppingLists');

  Stream<List<ShoppingList>> listsStream(String householdId) {
    return _lists(householdId).orderBy('createdAt').snapshots().map(
          (snap) => snap.docs.map(ShoppingList.fromFirestore).toList(),
        );
  }

  Future<String> createList(
    String householdId, {
    required String name,
    required ListColor color,
    int defaultServings = 4,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ShoppingListsException('Listen må ha et navn.');
    }
    final list = ShoppingList(
      id: '',
      name: trimmedName,
      color: color,
      defaultServings: defaultServings,
      staples: const {},
      createdAt: null,
    );
    final ref = await _lists(householdId).add(list.toMap());
    return ref.id;
  }

  Future<void> renameList(String householdId, String listId, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ShoppingListsException('Listen må ha et navn.');
    }
    await _lists(householdId).doc(listId).update({'name': trimmedName});
  }

  Future<void> updateColor(String householdId, String listId, ListColor color) async {
    await _lists(householdId).doc(listId).update({'color': color.name});
  }

  Future<void> updateDefaultServings(String householdId, String listId, int servings) async {
    await _lists(householdId).doc(listId).update({'defaultServings': servings});
  }

  Future<void> updateStaples(String householdId, String listId, Set<String> ingredientIds) async {
    await _lists(householdId).doc(listId).update({'staples': ingredientIds.toList()});
  }

  /// Sletter en handleliste og alt innholdet dens (middagsplan + varer på
  /// selve handlelisten). Kan aldri slette den siste gjenværende listen i
  /// husholdningen — en husholdning har alltid minst én.
  Future<void> deleteList(String householdId, String listId) async {
    final existing = await _lists(householdId).get();
    if (existing.docs.length <= 1) {
      throw ShoppingListsException('Kan ikke slette den siste handlelisten.');
    }
    final listRef = _lists(householdId).doc(listId);
    await _deleteAllInCollection(listRef.collection('mealPlanItems'));
    await _deleteAllInCollection(listRef.collection('shoppingListItems'));
    await listRef.delete();
  }

  Future<void> _deleteAllInCollection(CollectionReference<Map<String, dynamic>> collection) async {
    final snap = await collection.get();
    for (var i = 0; i < snap.docs.length; i += _maxBatchOps) {
      final batch = _firestore.batch();
      for (final doc in snap.docs.skip(i).take(_maxBatchOps)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}
