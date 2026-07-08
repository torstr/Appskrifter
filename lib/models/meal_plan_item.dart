import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// En valgt middag i husholdningens middagsplan.
class MealPlanItem {
  const MealPlanItem({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeUnit,
    required this.servings,
  });

  final String id;
  final String recipeId;
  final String recipeName;

  /// Øyeblikksbilde av oppskriftens [RecipeUnit] på tidspunktet den ble lagt
  /// til, i likhet med [recipeName] — slik at skjermer kan vise riktig
  /// enhetsnavn («personer»/«porsjoner») uten et ekstra oppskrift-oppslag.
  final RecipeUnit recipeUnit;

  /// Antall personer (eller porsjoner, for bakeoppskrifter) for denne
  /// middagen. Forhåndsutfylt med husholdningens standardverdi for
  /// person-oppskrifter, eller 1 for porsjon-oppskrifter, men kan overstyres.
  final int servings;

  factory MealPlanItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MealPlanItem(
      id: doc.id,
      recipeId: data['recipeId'] as String,
      recipeName: data['recipeName'] as String,
      recipeUnit: RecipeUnit.fromName(data['recipeUnit'] as String?),
      servings: (data['servings'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeUnit': recipeUnit.name,
      'servings': servings,
    };
  }

  MealPlanItem copyWith({int? servings}) {
    return MealPlanItem(
      id: id,
      recipeId: recipeId,
      recipeName: recipeName,
      recipeUnit: recipeUnit,
      servings: servings ?? this.servings,
    );
  }
}
