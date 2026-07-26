import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// Én av husholdningens handlelister — hver har sin egen middagsplan,
/// sitt eget «standard antall personer» og egne standardvarer. De fleste
/// husholdninger har bare én (f.eks. «Hjemme»), men man kan opprette flere
/// (f.eks. «Hytta») fra Innstillinger.
class ShoppingList {
  const ShoppingList({
    required this.id,
    required this.name,
    required this.color,
    required this.defaultServings,
    required this.staples,
    required this.createdAt,
  });

  final String id;
  final String name;
  final ListColor color;

  /// Standard antall personer å handle til for denne listen.
  final int defaultServings;

  /// Ingredienser (fra den sentrale ingredienslisten) denne listen alltid
  /// antar å ha i hyllen (salt, pepper, olivenolje osv.) — utelates derfor
  /// fra genererte handlelister selv om en oppskrift bruker dem, se
  /// `ShoppingListService.generateFromMealPlan`.
  final Set<String> staples;

  /// Brukt til å avgjøre hvilken liste som er «standardlisten» (den eldste)
  /// hvis en enhets lagrede valg ikke lenger finnes.
  final DateTime? createdAt;

  factory ShoppingList.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ShoppingList(
      id: doc.id,
      name: data['name'] as String,
      color: ListColor.fromName(data['color'] as String?),
      defaultServings: (data['defaultServings'] as num?)?.toInt() ?? 4,
      staples: ((data['staples'] as List<dynamic>?) ?? []).map((e) => e as String).toSet(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'color': color.name,
      'defaultServings': defaultServings,
      'staples': staples.toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
