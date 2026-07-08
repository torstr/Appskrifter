import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meal_plan_item.dart';
import 'auth_providers.dart';
import 'service_providers.dart';

final mealPlanProvider = StreamProvider<List<MealPlanItem>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(mealPlanServiceProvider).mealPlanStream(householdId);
});
