import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/device_settings_service.dart';
import '../services/household_service.dart';
import '../services/ingredient_service.dart';
import '../services/meal_plan_service.dart';
import '../services/recipe_service.dart';
import '../services/shopping_list_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final householdServiceProvider = Provider(
  (ref) => HouseholdService(authService: ref.watch(authServiceProvider)),
);
final ingredientServiceProvider = Provider((ref) => IngredientService());
final recipeServiceProvider = Provider((ref) => RecipeService());
final mealPlanServiceProvider = Provider((ref) => MealPlanService());
final shoppingListServiceProvider = Provider((ref) => ShoppingListService());
final deviceSettingsServiceProvider = Provider((ref) => DeviceSettingsService());

/// Antall minutter «hold skjermen på» skal vare før den automatisk slås av
/// igjen — en personlig, enhetslokal innstilling (se [DeviceSettingsService]),
/// ikke delt med resten av husholdningen. Inaktiver med [WidgetRef.invalidate]
/// etter en skriving for å laste inn den nye verdien.
final wakeLockMinutesProvider = FutureProvider<int>((ref) {
  return ref.watch(deviceSettingsServiceProvider).getWakeLockMinutes();
});
