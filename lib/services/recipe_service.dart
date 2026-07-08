import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/recipe.dart';

class RecipeService {
  RecipeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _recipes =>
      _firestore.collection('recipes');

  /// Det globale, godkjente oppskriftssettet — synlig for alle husholdninger.
  Stream<List<Recipe>> globalRecipesStream() {
    return _recipes
        .where('status', isEqualTo: RecipeStatus.approved.value)
        .orderBy('nameLowercase')
        .snapshots()
        .map((snap) => snap.docs.map(Recipe.fromFirestore).toList());
  }

  /// Husholdningens egne oppskrifter: private og de som venter på godkjenning.
  /// Godkjente oppskrifter mister sin ownerHouseholdId og havner kun i det
  /// globale settet.
  Stream<List<Recipe>> householdRecipesStream(String householdId) {
    return _recipes
        .where('ownerHouseholdId', isEqualTo: householdId)
        .orderBy('nameLowercase')
        .snapshots()
        .map((snap) => snap.docs.map(Recipe.fromFirestore).toList());
  }

  /// Oppskrifter foreslått for det globale settet, på tvers av alle
  /// husholdninger. Kun tilgjengelig for admin-brukere (håndhevet av
  /// Firestore-reglene).
  Stream<List<Recipe>> pendingProposalsStream() {
    return _recipes
        .where('status', isEqualTo: RecipeStatus.pending.value)
        .snapshots()
        .map((snap) => snap.docs.map(Recipe.fromFirestore).toList());
  }

  /// Sjekker om en oppskrift med dette navnet allerede finnes et sted brukeren
  /// ville sett det: i det globale settet, eller i egen husholdnings sett.
  /// Brukes til å hindre navnekollisjoner når man oppretter en ny oppskrift
  /// (inkl. når man lager en variant av en eksisterende).
  Future<bool> nameExistsInScope(
    String name,
    String householdId, {
    String? excludeRecipeId,
  }) async {
    final lower = name.trim().toLowerCase();
    final globalMatch = await _recipes
        .where('status', isEqualTo: RecipeStatus.approved.value)
        .where('nameLowercase', isEqualTo: lower)
        .limit(1)
        .get();
    if (globalMatch.docs.isNotEmpty &&
        globalMatch.docs.first.id != excludeRecipeId) {
      return true;
    }

    final ownMatch = await _recipes
        .where('ownerHouseholdId', isEqualTo: householdId)
        .where('nameLowercase', isEqualTo: lower)
        .limit(1)
        .get();
    if (ownMatch.docs.isEmpty) return false;
    return ownMatch.docs.first.id != excludeRecipeId;
  }

  /// Henter en engangs-liste med oppskrifter for en gitt liste med id-er,
  /// f.eks. for å regne ut en handleliste fra en middagsplan.
  Future<List<Recipe>> getRecipesByIds(List<String> recipeIds) async {
    final uniqueIds = recipeIds.toSet().toList();
    final docs = await Future.wait(uniqueIds.map((id) => _recipes.doc(id).get()));
    return docs.where((d) => d.exists).map(Recipe.fromFirestore).toList();
  }

  Stream<Recipe?> recipeStream(String recipeId) {
    return _recipes.doc(recipeId).snapshots().map(
          (doc) => doc.exists ? Recipe.fromFirestore(doc) : null,
        );
  }

  Future<String> createRecipe({
    required String name,
    required RecipeType type,
    required RecipeUnit recipeUnit,
    required String yieldNote,
    required int prepTimeMinutes,
    required String instructions,
    required List<RecipeIngredient> ingredients,
    required String ownerHouseholdId,
    required String createdByUid,
  }) async {
    final docRef = _recipes.doc();
    final recipe = Recipe(
      id: docRef.id,
      name: name,
      type: type,
      recipeUnit: recipeUnit,
      yieldNote: yieldNote,
      prepTimeMinutes: prepTimeMinutes,
      instructions: instructions,
      ingredients: ingredients,
      status: RecipeStatus.private,
      ownerHouseholdId: ownerHouseholdId,
      createdByUid: createdByUid,
    );
    await docRef.set(recipe.toMap());
    return docRef.id;
  }

  Future<void> updateRecipe(Recipe recipe) async {
    await _recipes.doc(recipe.id).update(recipe.toMap());
  }

  Future<void> deleteRecipe(String recipeId) async {
    await _recipes.doc(recipeId).delete();
  }

  /// Foreslår en privat oppskrift for det globale settet.
  Future<void> proposeToGlobal(String recipeId) async {
    await _recipes.doc(recipeId).update({'status': RecipeStatus.pending.value});
  }

  /// Admin godkjenner et forslag: oppskriften blir global og eierløs.
  Future<void> approve(String recipeId) async {
    await _recipes.doc(recipeId).update({
      'status': RecipeStatus.approved.value,
      'ownerHouseholdId': null,
    });
  }

  /// Admin avviser et forslag: oppskriften går tilbake til å være privat for
  /// husholdningen som eier den.
  Future<void> reject(String recipeId) async {
    await _recipes.doc(recipeId).update({'status': RecipeStatus.private.value});
  }

  // --- Personlig vurdering (kun egen stjerne per oppskrift, ingen snitt) ---

  DocumentReference<Map<String, dynamic>> _ratingDoc(String recipeId, String uid) =>
      _recipes.doc(recipeId).collection('ratings').doc(uid);

  /// Lagrer brukerens egen 1–5-stjerners vurdering av en oppskrift.
  Future<void> rate(String recipeId, String uid, int stars) async {
    await _ratingDoc(recipeId, uid).set({'stars': stars, 'raterUid': uid});
  }

  /// Fjerner brukerens vurdering av en oppskrift.
  Future<void> clearRating(String recipeId, String uid) async {
    await _ratingDoc(recipeId, uid).delete();
  }

  Stream<int?> myRatingStream(String recipeId, String uid) {
    return _ratingDoc(recipeId, uid).snapshots().map(
          (doc) => doc.exists ? (doc.data()!['stars'] as num).toInt() : null,
        );
  }

  Stream<Map<String, int>> myRatingsMapStream(String uid) {
    return _firestore
        .collectionGroup('ratings')
        .where('raterUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final map = <String, int>{};
      for (final doc in snap.docs) {
        final recipeId = doc.reference.parent.parent!.id;
        map[recipeId] = (doc.data()['stars'] as num).toInt();
      }
      return map;
    });
  }
}
