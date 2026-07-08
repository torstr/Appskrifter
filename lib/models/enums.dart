/// Kategorier for ingredienser/varer, brukt til å sortere handlelisten.
/// Rekkefølgen på verdiene er samme rekkefølge som handlelisten skal vises i.
enum IngredientCategory {
  fruktOgGront('Frukt og grønt'),
  kjott('Kjøtt og fisk'),
  meieri('Meieriprodukter'),
  torrvarerOgSauser('Tørrvarer og sauser'),
  annet('Annet');

  const IngredientCategory(this.displayName);

  final String displayName;

  static IngredientCategory fromName(String name) {
    return IngredientCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => IngredientCategory.annet,
    );
  }
}

/// Måleenheter som er vanlige i norske oppskrifter. Forkortede metriske
/// enheter (g, kg, ss osv.) bøyes ikke i flertall på norsk, mens hele ord
/// (boks, pose, pakke, bunt, klype) gjør det — «fedd» er likt i entall og
/// flertall (som «sau»/«fisk»).
enum Unit {
  stk('stk', 'stk'),
  g('g', 'g'),
  kg('kg', 'kg'),
  ml('ml', 'ml'),
  dl('dl', 'dl'),
  l('l', 'l'),
  ss('ss', 'ss'),
  ts('ts', 'ts'),
  boks('boks', 'bokser'),
  pose('pose', 'poser'),
  pakke('pakke', 'pakker'),
  bunt('bunt', 'bunter'),
  fedd('fedd', 'fedd'),
  klype('klype', 'klyper');

  const Unit(this.displayName, this.pluralDisplayName);

  final String displayName;
  final String pluralDisplayName;

  /// Riktig bøying av enheten for en gitt mengde: entall kun ved nøyaktig 1.
  String displayNameFor(double quantity) => quantity == 1 ? displayName : pluralDisplayName;

  static Unit fromName(String name) {
    return Unit.values.firstWhere(
      (u) => u.name == name,
      orElse: () => Unit.stk,
    );
  }
}

/// Hvilken type måltid en oppskrift er til, brukt til filtrering og til
/// husholdningens «skjul som standard»-innstilling. Eldre oppskrifter uten
/// dette feltet regnes som «middag» (se [Recipe.fromFirestore]).
enum RecipeType {
  middag('Middag'),
  dessert('Dessert'),
  bakst('Bakst'),
  frokost('Frokost');

  const RecipeType(this.displayName);

  final String displayName;

  static RecipeType fromName(String? name) {
    return RecipeType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => RecipeType.middag,
    );
  }
}

/// Hvilken enhet ingrediensmengdene i en oppskrift er oppgitt per. De fleste
/// middager/desserter skaleres naturlig **per person**, mens bakeoppskrifter
/// (brød, boller, kjeks) typisk er oppgitt for én hel omgang/bakst uansett
/// antall personer — for disse brukes **per porsjon**, der én porsjon er hele
/// oppskriften slik den er skrevet (se [Recipe.yieldNote] for hvor mye det
/// faktisk blir, f.eks. «ca. 18 kjeks»). Eldre oppskrifter uten dette feltet
/// regnes som «person» (se [Recipe.fromFirestore]).
enum RecipeUnit {
  person('Person', 'Personer'),
  porsjon('Porsjon', 'Porsjoner');

  const RecipeUnit(this.displayName, this.pluralDisplayName);

  final String displayName;
  final String pluralDisplayName;

  String displayNameFor(num count) => count == 1 ? displayName : pluralDisplayName;

  static RecipeUnit fromName(String? name) {
    return RecipeUnit.values.firstWhere(
      (u) => u.name == name,
      orElse: () => RecipeUnit.person,
    );
  }
}

/// Status på en oppskrift i livssyklusen fra privat til godkjent i fellesskapet.
enum RecipeStatus {
  /// Kun synlig for husholdningen som eier den.
  private('private'),

  /// Foreslått for det globale settet, venter på godkjenning.
  pending('pending'),

  /// Godkjent og synlig for alle husholdninger.
  approved('approved');

  const RecipeStatus(this.value);

  final String value;

  static RecipeStatus fromValue(String value) {
    return RecipeStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => RecipeStatus.private,
    );
  }
}
