import 'enums.dart';
import 'recipe.dart';

/// Filter brukt til å begrense en oppskriftsliste i UI. Rent klientsidig
/// filtrering av allerede hentede lister — antall oppskrifter forventes å
/// holde seg lite nok til at dette er greit (se CLAUDE.md).
class RecipeFilter {
  const RecipeFilter({
    this.ingredientIds = const {},
    this.minRating = 0,
    this.maxPrepMinutes,
    this.types = const {},
  });

  /// Oppskriften må inneholde minst én av disse ingrediensene (ELLER).
  /// Tom mengde betyr ikke filtrert på ingrediens.
  final Set<String> ingredientIds;

  /// 0 betyr ikke filtrert på egen vurdering.
  final int minRating;

  /// Null betyr ikke filtrert på tilberedningstid.
  final int? maxPrepMinutes;

  /// Oppskriften må ha en av disse typene (ELLER). Tom mengde betyr ikke
  /// eksplisitt filtrert på type — se husholdningens `hiddenRecipeTypes` for
  /// hva som da skjules som standard (håndteres utenfor denne klassen, i
  /// `_RecipeListView`, siden det trenger husholdnings-kontekst).
  final Set<RecipeType> types;

  bool get isActive =>
      ingredientIds.isNotEmpty || minRating > 0 || maxPrepMinutes != null || types.isNotEmpty;

  bool matches(Recipe recipe, {int? myRating}) {
    if (types.isNotEmpty && !types.contains(recipe.type)) {
      return false;
    }
    if (ingredientIds.isNotEmpty &&
        !recipe.ingredients.any((ing) => ingredientIds.contains(ing.ingredientId))) {
      return false;
    }
    if (minRating > 0 && (myRating == null || myRating < minRating)) {
      return false;
    }
    if (maxPrepMinutes != null && recipe.prepTimeMinutes > 0 && recipe.prepTimeMinutes > maxPrepMinutes!) {
      return false;
    }
    return true;
  }

  RecipeFilter copyWith({
    Set<String>? ingredientIds,
    int? minRating,
    int? Function()? maxPrepMinutes,
    Set<RecipeType>? types,
  }) {
    return RecipeFilter(
      ingredientIds: ingredientIds ?? this.ingredientIds,
      minRating: minRating ?? this.minRating,
      maxPrepMinutes: maxPrepMinutes != null ? maxPrepMinutes() : this.maxPrepMinutes,
      types: types ?? this.types,
    );
  }
}
