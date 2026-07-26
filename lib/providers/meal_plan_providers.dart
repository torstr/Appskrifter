import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meal_plan_item.dart';
import 'auth_providers.dart';
import 'service_providers.dart';
import 'shopping_lists_providers.dart';

final mealPlanProvider = StreamProvider<List<MealPlanItem>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  final listId = ref.watch(currentListProvider)?.id;
  if (householdId == null || listId == null) return Stream.value(const []);
  return ref.watch(mealPlanServiceProvider).mealPlanStream(householdId, listId);
});
