import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/meal_plan_item.dart';
import '../models/recipe.dart';

class MealPlanService {
  MealPlanService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String householdId, String listId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('shoppingLists')
      .doc(listId)
      .collection('mealPlanItems');

  Stream<List<MealPlanItem>> mealPlanStream(String householdId, String listId) {
    return _items(householdId, listId).orderBy('recipeName').snapshots().map(
          (snap) => snap.docs.map(MealPlanItem.fromFirestore).toList(),
        );
  }

  Future<void> addRecipe(String householdId, String listId, Recipe recipe, int servings) async {
    final item = MealPlanItem(
      id: '',
      recipeId: recipe.id,
      recipeName: recipe.name,
      recipeUnit: recipe.recipeUnit,
      servings: servings,
    );
    await _items(householdId, listId).add(item.toMap());
  }

  Future<void> removeItem(String householdId, String listId, String itemId) async {
    await _items(householdId, listId).doc(itemId).delete();
  }

  Future<void> updateServings(String householdId, String listId, String itemId, int servings) async {
    await _items(householdId, listId).doc(itemId).update({'servings': servings});
  }

  Future<void> clear(String householdId, String listId) async {
    final snap = await _items(householdId, listId).get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
