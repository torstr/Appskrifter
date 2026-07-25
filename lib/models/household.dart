import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdBy,
    required this.defaultServings,
    required this.hiddenRecipeTypes,
    required this.staples,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String createdBy;

  /// Standard antall personer å handle til, satt i innstillinger.
  final int defaultServings;

  /// Oppskriftstyper som er skjult som standard i oppskriftslistene for denne
  /// husholdningen (f.eks. et skjema som aldri baker kan skjule «Bakst»).
  /// Man kan fortsatt eksplisitt filtrere fram en skjult type i filterarket.
  final Set<RecipeType> hiddenRecipeTypes;

  /// Ingredienser (fra den sentrale ingredienslisten) husholdningen alltid
  /// antas å ha i hyllen (salt, pepper, olivenolje osv.) — utelates derfor
  /// fra genererte handlelister selv om en oppskrift bruker dem, se
  /// `ShoppingListService.generateFromMealPlan`.
  final Set<String> staples;

  /// Medlemskap ligger i underkolleksjonen `households/{id}/members`, se
  /// [HouseholdService.memberUidsStream] — ikke som et array-felt her, slik at
  /// "bli med via kode"-flyten kan verifiseres trygt av Firestore-reglene.

  factory Household.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Household(
      id: doc.id,
      name: data['name'] as String,
      inviteCode: data['inviteCode'] as String,
      createdBy: data['createdBy'] as String? ?? '',
      defaultServings: (data['defaultServings'] as num?)?.toInt() ?? 4,
      hiddenRecipeTypes: ((data['hiddenRecipeTypes'] as List<dynamic>?) ?? [])
          .map((e) => RecipeType.fromName(e as String?))
          .toSet(),
      staples: ((data['staples'] as List<dynamic>?) ?? []).map((e) => e as String).toSet(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'inviteCode': inviteCode,
      'createdBy': createdBy,
      'defaultServings': defaultServings,
      'hiddenRecipeTypes': hiddenRecipeTypes.map((t) => t.name).toList(),
      'staples': staples.toList(),
    };
  }
}
