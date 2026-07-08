import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// En ingrediens-linje i en oppskrift. Navn og kategori er en øyeblikksbilde-kopi
/// fra den sentrale ingredienslisten på det tidspunktet oppskriften ble lagret,
/// slik at oppskriften kan vises offline uten å slå opp ingrediensen på nytt.
/// [ingredientId] beholdes for at handlelisten skal kunne slå sammen like ingredienser.
class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredientId,
    required this.name,
    required this.category,
    required this.quantityPerUnit,
    required this.unit,
  });

  final String ingredientId;
  final String name;
  final IngredientCategory category;

  /// Mengde per [Recipe.recipeUnit] (per person, eller per porsjon for
  /// bakeoppskrifter). Total mengde = quantityPerUnit * antall personer/porsjoner.
  final double quantityPerUnit;
  final Unit unit;

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      ingredientId: map['ingredientId'] as String,
      name: map['name'] as String,
      category: IngredientCategory.fromName(map['category'] as String),
      // Firestore-feltnavnet er bevisst uendret fra før «porsjon»-modus fantes,
      // for å unngå å migrere alle eksisterende oppskrift-dokumenter.
      quantityPerUnit: (map['quantityPerPerson'] as num).toDouble(),
      unit: Unit.fromName(map['unit'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ingredientId': ingredientId,
      'name': name,
      'category': category.name,
      'quantityPerPerson': quantityPerUnit,
      'unit': unit.name,
    };
  }

  RecipeIngredient copyWith({
    String? ingredientId,
    String? name,
    IngredientCategory? category,
    double? quantityPerUnit,
    Unit? unit,
  }) {
    return RecipeIngredient(
      ingredientId: ingredientId ?? this.ingredientId,
      name: name ?? this.name,
      category: category ?? this.category,
      quantityPerUnit: quantityPerUnit ?? this.quantityPerUnit,
      unit: unit ?? this.unit,
    );
  }
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.type,
    required this.recipeUnit,
    required this.yieldNote,
    required this.prepTimeMinutes,
    required this.instructions,
    required this.ingredients,
    required this.status,
    required this.ownerHouseholdId,
    required this.createdByUid,
  });

  final String id;
  final String name;
  final RecipeType type;

  /// Om ingrediensmengdene skaleres per person (vanlige middager/desserter)
  /// eller per porsjon (bakeoppskrifter oppgitt for en hel omgang/bakst).
  final RecipeUnit recipeUnit;

  /// Valgfri, fritekst beskrivelse av hva én porsjon faktisk gir, f.eks.
  /// «ca. 18 kjeks» eller «1 brød». Kun relevant når [recipeUnit] er
  /// [RecipeUnit.porsjon] — rent informativt, påvirker ikke utregningen.
  final String yieldNote;

  /// Anslått tilberedningstid i minutter.
  final int prepTimeMinutes;
  final String instructions;
  final List<RecipeIngredient> ingredients;
  final RecipeStatus status;

  /// Husholdningen som eier oppskriften. Null når status er [RecipeStatus.approved]
  /// (oppskriften eies da av det globale, felles settet).
  final String? ownerHouseholdId;
  final String createdByUid;

  bool get isGlobal => status == RecipeStatus.approved;

  factory Recipe.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Recipe(
      id: doc.id,
      name: data['name'] as String,
      type: RecipeType.fromName(data['type'] as String?),
      recipeUnit: RecipeUnit.fromName(data['recipeUnit'] as String?),
      yieldNote: data['yieldNote'] as String? ?? '',
      prepTimeMinutes: (data['prepTimeMinutes'] as num?)?.toInt() ?? 0,
      instructions: data['instructions'] as String? ?? '',
      ingredients: ((data['ingredients'] as List<dynamic>?) ?? [])
          .map((e) => RecipeIngredient.fromMap(e as Map<String, dynamic>))
          .toList(),
      status: RecipeStatus.fromValue(data['status'] as String? ?? 'private'),
      ownerHouseholdId: data['ownerHouseholdId'] as String?,
      createdByUid: data['createdByUid'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type.name,
      'recipeUnit': recipeUnit.name,
      'yieldNote': yieldNote,
      'prepTimeMinutes': prepTimeMinutes,
      'instructions': instructions,
      'ingredients': ingredients.map((e) => e.toMap()).toList(),
      'status': status.value,
      'ownerHouseholdId': ownerHouseholdId,
      'createdByUid': createdByUid,
      'nameLowercase': name.toLowerCase(),
    };
  }

  Recipe copyWith({
    String? name,
    RecipeType? type,
    RecipeUnit? recipeUnit,
    String? yieldNote,
    int? prepTimeMinutes,
    String? instructions,
    List<RecipeIngredient>? ingredients,
    RecipeStatus? status,
    String? ownerHouseholdId,
  }) {
    return Recipe(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      recipeUnit: recipeUnit ?? this.recipeUnit,
      yieldNote: yieldNote ?? this.yieldNote,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      instructions: instructions ?? this.instructions,
      ingredients: ingredients ?? this.ingredients,
      status: status ?? this.status,
      ownerHouseholdId: ownerHouseholdId ?? this.ownerHouseholdId,
      createdByUid: createdByUid,
    );
  }
}
