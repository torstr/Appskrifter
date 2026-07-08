import 'package:shared_preferences/shared_preferences.dart';

/// Innstillinger som lagres lokalt på enheten (SharedPreferences), ikke i
/// Firestore — for ting som er personlige/enhetsspesifikke i naturen (f.eks.
/// om skjermen skal holdes på), ikke noe husholdningen skal dele.
class DeviceSettingsService {
  static const defaultWakeLockMinutes = 15;
  static const _wakeLockMinutesKey = 'wakeLockMinutes';

  Future<int> getWakeLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_wakeLockMinutesKey) ?? defaultWakeLockMinutes;
  }

  Future<void> setWakeLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wakeLockMinutesKey, minutes);
  }
}
