import 'dart:convert';

import '../models/enums.dart';
import '../models/recipe.dart';

/// Kastet når JSON limt inn fra en språkmodell ikke kan tolkes som en
/// oppskrift. Meldingen er ment å vises direkte til brukeren.
class LlmRecipeImportException implements Exception {
  LlmRecipeImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Tolker JSON limt inn fra en språkmodell (formatet er beskrevet for
/// modellen i `web/llm-import.html`) til et [Recipe]-objekt klart til
/// forhåndsutfylling i redigeringsskjemaet — samme mekanisme som «Lag
/// variant» bruker (se [Recipe.duplicateFrom]-bruk i `RecipeEditScreen`).
/// Id/status/eierskap settes til plassholdere siden resultatet aldri lagres
/// direkte, kun forhåndsvises for gjennomsyn.
///
/// Ingrediensenes `ingredientId` fra JSON-en ignoreres bevisst: skjemaet slår
/// alltid opp/oppretter ingredienser på nytt basert på *navn* ved lagring
/// (se `RecipeEditScreen._save`), så en feil eller foreldet id fra
/// språkmodellen kan aldri føre til at feil ingrediens gjenbrukes.
Recipe parseLlmRecipeJson(String raw) {
  final Map<String, dynamic> data;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Toppnivået i JSON-en må være et objekt.');
    }
    data = decoded;
  } on FormatException catch (e) {
    throw LlmRecipeImportException('Ugyldig JSON: ${e.message}');
  }

  final name = (data['name'] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    throw LlmRecipeImportException('JSON-en mangler et gyldig «name»-felt.');
  }

  final ingredientsRaw = data['ingredients'];
  if (ingredientsRaw is! List || ingredientsRaw.isEmpty) {
    throw LlmRecipeImportException('JSON-en mangler en «ingredients»-liste.');
  }

  final ingredients = <RecipeIngredient>[];
  for (final entry in ingredientsRaw) {
    if (entry is! Map<String, dynamic>) {
      throw LlmRecipeImportException('Hver ingrediens i listen må være et JSON-objekt.');
    }
    final ingredientName = (entry['name'] as String?)?.trim() ?? '';
    if (ingredientName.isEmpty) {
      throw LlmRecipeImportException('En ingrediens mangler «name».');
    }
    final quantity = (entry['quantity'] as num?)?.toDouble();
    if (quantity == null) {
      throw LlmRecipeImportException('Ingrediensen «$ingredientName» mangler en gyldig «quantity».');
    }
    ingredients.add(RecipeIngredient(
      ingredientId: '',
      name: ingredientName,
      category: IngredientCategory.fromName(entry['category'] as String? ?? ''),
      quantityPerUnit: quantity,
      unit: Unit.fromName(entry['unit'] as String? ?? ''),
    ));
  }

  return Recipe(
    id: '',
    name: name,
    type: RecipeType.fromName(data['type'] as String?),
    recipeUnit: RecipeUnit.fromName(data['recipeUnit'] as String?),
    yieldNote: (data['yieldNote'] as String?)?.trim() ?? '',
    prepTimeMinutes: (data['prepTimeMinutes'] as num?)?.toInt() ?? 0,
    instructions: (data['instructions'] as String?)?.trim() ?? '',
    ingredients: ingredients,
    status: RecipeStatus.private,
    ownerHouseholdId: null,
    createdByUid: '',
  );
}
