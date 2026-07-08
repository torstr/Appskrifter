import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import 'auth_providers.dart';
import 'service_providers.dart';

final globalRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  return ref.watch(recipeServiceProvider).globalRecipesStream();
});

final householdRecipesProvider = StreamProvider<List<Recipe>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(recipeServiceProvider).householdRecipesStream(householdId);
});

/// Kun meningsfull for admin-brukere — Firestore-reglene avviser spørringen
/// for alle andre.
final pendingProposalsProvider = StreamProvider<List<Recipe>>((ref) {
  final isAdmin = ref.watch(userProfileProvider).value?.isAdmin ?? false;
  if (!isAdmin) return Stream.value(const []);
  return ref.watch(recipeServiceProvider).pendingProposalsStream();
});

final recipeByIdProvider = StreamProvider.family<Recipe?, String>((ref, recipeId) {
  return ref.watch(recipeServiceProvider).recipeStream(recipeId);
});

final myRatingProvider = StreamProvider.family<int?, String>((ref, recipeId) {
  final uid = ref.watch(userProfileProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(recipeServiceProvider).myRatingStream(recipeId, uid);
});

/// recipeId → stjerner for innlogget bruker, brukt i lister og filtre.
final myRatingsMapProvider = StreamProvider<Map<String, int>>((ref) {
  final uid = ref.watch(userProfileProvider).value?.uid;
  if (uid == null) return Stream.value(const {});
  return ref.watch(recipeServiceProvider).myRatingsMapStream(uid);
});

final ingredientListProvider = StreamProvider<List<Ingredient>>((ref) {
  return ref.watch(ingredientServiceProvider).allIngredients();
});
