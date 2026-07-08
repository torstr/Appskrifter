import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manual_item_history_entry.dart';
import '../models/shopping_list_item.dart';
import 'auth_providers.dart';
import 'service_providers.dart';

final shoppingListProvider = StreamProvider<List<ShoppingListItem>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(shoppingListServiceProvider).shoppingListStream(householdId);
});

/// Husholdningens historikk over tidligere manuelt tillagte varer, brukt til
/// å foreslå varer man har lagt til før når man legger til en ny vare.
final manualItemHistoryProvider = StreamProvider<List<ManualItemHistoryEntry>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(shoppingListServiceProvider).manualItemHistoryStream(householdId);
});
