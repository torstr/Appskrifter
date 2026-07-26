import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shopping_list.dart';
import 'auth_providers.dart';
import 'service_providers.dart';

/// Alle handlelistene i husholdningen, sortert eldste først (se
/// `ShoppingListsService.listsStream`) — en husholdning har alltid minst én.
final shoppingListsProvider = StreamProvider<List<ShoppingList>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(shoppingListsServiceProvider).listsStream(householdId);
});

/// Hvilken handleliste denne enheten sist så på — personlig/enhetslokalt (se
/// [DeviceSettingsService.getSelectedListId]), ikke delt med resten av
/// husholdningen. Holdes som synkron state (i stedet for en `FutureProvider`
/// som re-leses via `invalidate`) slik at et bytte slår igjennom umiddelbart
/// for alle skjermer, uansett om de akkurat nå er «pauset» i bakgrunnen (f.eks.
/// en fane som ligger i en `IndexedStack` bak en annen synlig fane) — lesing
/// fra enhetslagring skjer kun én gang ved oppstart, skriving skjer i
/// bakgrunnen og blokkerer ikke UI-oppdateringen.
class SelectedListIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.read(deviceSettingsServiceProvider).getSelectedListId().then((stored) {
      if (stored != null) state = stored;
    });
    return null;
  }

  void select(String listId) {
    state = listId;
    ref.read(deviceSettingsServiceProvider).setSelectedListId(listId);
  }
}

final selectedListIdProvider = NotifierProvider<SelectedListIdNotifier, String?>(SelectedListIdNotifier.new);

/// Den faktiske aktive listen: enhetens lagrede valg hvis den fortsatt
/// finnes, ellers den eldste listen, ellers `null` (mens listene laster).
/// Dette er spørringspunktet alle skjermer skal bruke — se
/// `mealPlanProvider`/`shoppingListProvider`.
final currentListProvider = Provider<ShoppingList?>((ref) {
  final lists = ref.watch(shoppingListsProvider).value;
  if (lists == null || lists.isEmpty) return null;
  final selectedId = ref.watch(selectedListIdProvider);
  final matches = lists.where((l) => l.id == selectedId);
  return matches.isEmpty ? lists.first : matches.first;
});
