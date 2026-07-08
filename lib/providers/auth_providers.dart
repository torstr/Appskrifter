import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'service_providers.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Den innloggede brukerens profildokument fra Firestore, inkludert
/// husholdnings-id og admin-status. Null hvis ikke innlogget.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return Stream.value(null);
  return ref.watch(authServiceProvider).userProfileStream(user.uid);
});

/// Bekrefter at brukeren faktisk har et medlemskapsdokument i husholdningen
/// `householdId` peker på — brukt av AppGate til å oppdage og reparere en
/// «foreldreløs» profil (se [HouseholdService.leaveHousehold]).
final householdMembershipVerifiedProvider =
    FutureProvider.family<bool, ({String householdId, String uid})>((ref, args) {
  return ref.watch(householdServiceProvider).isActualMember(args.householdId, args.uid);
});

/// Husholdningen den innloggede brukeren er medlem av, hvis noen.
final currentHouseholdProvider = StreamProvider<Household?>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final householdId = profile?.householdId;
  if (householdId == null) return Stream.value(null);
  return ref.watch(householdServiceProvider).householdStream(householdId);
});

/// Uid-ene til medlemmene i husholdningen, for å vise antall medlemmer.
final householdMemberUidsProvider = StreamProvider<List<String>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(householdServiceProvider).memberUidsStream(householdId);
});

/// Profilene til medlemmene i husholdningen (navn/bilde/e-post), for å vise
/// en faktisk medlemsliste. Strømmer profilendringer i sanntid.
final householdMembersProvider = StreamProvider<List<UserProfile>>((ref) {
  final uidsAsync = ref.watch(householdMemberUidsProvider);
  final authService = ref.watch(authServiceProvider);

  return uidsAsync.when(
    data: (uids) => _watchProfilesInOrder(authService, uids),
    loading: () => Stream.value(const []),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Uid-ene til de som venter på å bli godkjent inn i husholdningen. Kun
/// husholdningens oppretter har leserettighet på disse (håndhevet av
/// firestore.rules), så denne er kun meningsfull for oppretteren.
final pendingJoinRequestUidsProvider = StreamProvider<List<String>>((ref) {
  final householdId = ref.watch(userProfileProvider).value?.householdId;
  if (householdId == null) return Stream.value(const []);
  return ref.watch(householdServiceProvider).joinRequestUidsStream(householdId);
});

final pendingJoinRequestProfilesProvider = FutureProvider<List<UserProfile>>((ref) async {
  final uids = ref.watch(pendingJoinRequestUidsProvider).value ?? const [];
  if (uids.isEmpty) return [];
  final authService = ref.watch(authServiceProvider);
  final profiles = await Future.wait(uids.map((uid) => authService.userProfileStream(uid).first));
  return profiles.whereType<UserProfile>().toList();
});

/// Slår sammen flere profilstrømmer til én liste i [uids]-rekkefølge, og
/// emitter på nytt når en enkeltprofil endrer seg.
Stream<List<UserProfile>> _watchProfilesInOrder(AuthService auth, List<String> uids) {
  if (uids.isEmpty) return Stream.value(const []);

  return Stream.multi((controller) {
    final latest = <String, UserProfile?>{};
    final subs = <StreamSubscription<UserProfile?>>[];

    void emit() {
      controller.add(
        uids.map((u) => latest[u]).whereType<UserProfile>().toList(),
      );
    }

    for (final uid in uids) {
      subs.add(
        auth.userProfileStream(uid).listen(
          (profile) {
            if (profile != null) latest[uid] = profile;
            emit();
          },
          onError: controller.addError,
        ),
      );
    }

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
  });
}
