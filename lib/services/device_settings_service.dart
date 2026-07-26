import 'package:shared_preferences/shared_preferences.dart';

/// Innstillinger som lagres lokalt på enheten (SharedPreferences), ikke i
/// Firestore — for ting som er personlige/enhetsspesifikke i naturen (f.eks.
/// om skjermen skal holdes på), ikke noe husholdningen skal dele.
class DeviceSettingsService {
  static const defaultWakeLockMinutes = 15;
  static const _wakeLockMinutesKey = 'wakeLockMinutes';
  static const _selectedListIdKey = 'selectedShoppingListId';

  Future<int> getWakeLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_wakeLockMinutesKey) ?? defaultWakeLockMinutes;
  }

  Future<void> setWakeLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wakeLockMinutesKey, minutes);
  }

  /// Hvilken handleliste denne enheten sist så på — personlig/enhetslokalt,
  /// slik at ulike husholdningsmedlemmer kan jobbe med ulike lister samtidig
  /// (se `currentListProvider`). `null` hvis ingen er valgt ennå, eller hvis
  /// den lagrede listen ikke lenger finnes.
  Future<String?> getSelectedListId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedListIdKey);
  }

  Future<void> setSelectedListId(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedListIdKey, listId);
  }
}
