import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/household.dart';
import 'auth_service.dart';

/// Feil kastet av husholdnings-operasjoner, med en norsk brukervennlig melding.
class HouseholdException implements Exception {
  HouseholdException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resultatet av å sende en forespørsel om å bli med — nok til å vise
/// «Venter på godkjenning fra Familien X» mens man venter.
class JoinRequestSubmitted {
  const JoinRequestSubmitted({required this.householdId, required this.householdName});
  final String householdId;
  final String householdName;
}

/// Husholdninger og medlemskap håndteres helt klientsidig (ingen Cloud
/// Functions/Blaze-plan nødvendig):
/// - `households/{id}`: selve husholdningen (navn, invitasjonskode, standard
///   antall personer, opprettet-av).
/// - `households/{id}/members/{uid}`: medlemskap som egne dokumenter i en
///   underkolleksjon i stedet for et array-felt.
/// - `households/{id}/joinRequests/{uid}`: en forespørsel om å bli med, som
///   beviser kjennskap til en gyldig invitasjonskode. Gir ikke medlemskap før
///   husholdningens oppretter godkjenner den (se `approveJoinRequest`).
/// - `inviteCodes/{code}`: en tynn oppslagstabell fra kode til husholdnings-id
///   (+ navn, denormalisert for visning før man er medlem). Dokument-id-en er
///   selve koden, og reglene tillater kun punkt-oppslag (get), aldri listing.
class HouseholdService {
  HouseholdService({
    FirebaseFirestore? firestore,
    AuthService? authService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _authService = authService;

  final FirebaseFirestore _firestore;
  final AuthService? _authService;

  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // uten 0/O/1/I
  static const _codeLength = 6;

  CollectionReference<Map<String, dynamic>> get _households =>
      _firestore.collection('households');

  CollectionReference<Map<String, dynamic>> get _inviteCodes =>
      _firestore.collection('inviteCodes');

  CollectionReference<Map<String, dynamic>> _members(String householdId) =>
      _households.doc(householdId).collection('members');

  CollectionReference<Map<String, dynamic>> _joinRequests(String householdId) =>
      _households.doc(householdId).collection('joinRequests');

  Stream<Household?> householdStream(String householdId) {
    return _households.doc(householdId).snapshots().map(
          (doc) => doc.exists ? Household.fromFirestore(doc) : null,
        );
  }

  /// Strømmer medlems-uid-ene i en husholdning.
  Stream<List<String>> memberUidsStream(String householdId) {
    return _members(householdId).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toList(),
        );
  }

  /// Strømmer uid-ene til de som venter på å bli godkjent inn i husholdningen.
  Stream<List<String>> joinRequestUidsStream(String householdId) {
    return _joinRequests(householdId).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toList(),
        );
  }

  /// Sant når [uid] er blitt godkjent som medlem — brukes av venteskjermen
  /// til å oppdage godkjenning og gå videre.
  Stream<bool> isMemberStream(String householdId, String uid) {
    return _members(householdId).doc(uid).snapshots().map((d) => d.exists);
  }

  /// Sant så lenge forespørselen fortsatt venter. Slutter å være sann både
  /// ved godkjenning (den slettes da som en del av godkjenningen) og ved
  /// avvisning — bruk sammen med [isMemberStream] for å skille de to.
  Stream<bool> joinRequestExistsStream(String householdId, String uid) {
    return _joinRequests(householdId).doc(uid).snapshots().map((d) => d.exists);
  }

  Future<String?> findMembershipHouseholdId(String uid) async {
    try {
      final snap = await _firestore
          .collectionGroup('members')
          .where('memberUid', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.reference.parent.parent!.id;
      }
      // Eldre medlemskap skrevet med feltnavnet `uid` før omdøping.
      final legacy = await _firestore
          .collectionGroup('members')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (legacy.docs.isEmpty) return null;
      return legacy.docs.first.reference.parent.parent!.id;
    } on FirebaseException catch (e) {
      if (e.code == 'invalid-argument' || e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  String _randomCode() {
    final random = Random.secure();
    return List.generate(_codeLength, (_) => _codeAlphabet[random.nextInt(_codeAlphabet.length)]).join();
  }

  Future<String> _findUnusedCode() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _randomCode();
      final existing = await _inviteCodes.doc(code).get();
      if (!existing.exists) return code;
    }
    throw HouseholdException('Klarte ikke å generere en unik kode. Prøv igjen.');
  }

  Future<String> createHousehold(String name, String uid) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw HouseholdException('Husholdningen må ha et navn.');
    }

    try {
      final userRef = _firestore.collection('users').doc(uid);
      final userDoc = await userRef.get();
      if (!userDoc.exists) {
        final authService = _authService;
        if (authService != null) {
          final user = authService.currentUser;
          if (user != null && user.uid == uid) {
            await authService.ensureUserProfile(user);
          }
        }
      }
      final refreshed = await userRef.get();
      if ((refreshed.data()?['householdId'] as String?) != null) {
        throw HouseholdException('Du er allerede med i en husholdning.');
      }
      final existingMembership = await findMembershipHouseholdId(uid);
      if (existingMembership != null) {
        throw HouseholdException(
          'Du er allerede godkjent som medlem i en husholdning. '
          'Start appen på nytt, eller kontakt support hvis problemet vedvarer.',
        );
      }

      final code = await _findUnusedCode();
      final householdRef = _households.doc();

      try {
        await householdRef.set({
          'name': trimmedName,
          'inviteCode': code,
          'createdBy': uid,
          'defaultServings': 4,
        });
      } on FirebaseException catch (e) {
        throw HouseholdException('Kunne ikke opprette husholdningen (${e.code}).');
      }
      try {
        await _inviteCodes.doc(code).set({'householdId': householdRef.id, 'householdName': trimmedName});
      } on FirebaseException catch (e) {
        throw HouseholdException('Kunne ikke opprette invitasjonskode (${e.code}).');
      }
      try {
        await householdRef.collection('members').doc(uid).set({
          'memberUid': uid,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        throw HouseholdException('Kunne ikke registrere medlemskap (${e.code}).');
      }
      try {
        await _firestore.collection('users').doc(uid).update({'householdId': householdRef.id});
      } on FirebaseException catch (e) {
        throw HouseholdException('Kunne ikke koble profilen til husholdningen (${e.code}).');
      }

      return householdRef.id;
    } on HouseholdException {
      rethrow;
    } on FirebaseException catch (e) {
      throw HouseholdException('Klarte ikke å opprette husholdningen (${e.code}): ${e.message}');
    }
  }

  /// Sender en forespørsel om å bli med i husholdningen som eier [code].
  /// Gir ikke medlemskap med det samme — husholdningens oppretter må
  /// godkjenne forespørselen (se [approveJoinRequest]).
  Future<JoinRequestSubmitted> submitJoinRequest(String code, String uid) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw HouseholdException('Du må oppgi en invitasjonskode.');
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    if ((userDoc.data()?['householdId'] as String?) != null) {
      throw HouseholdException('Du er allerede med i en husholdning.');
    }
    final existingMembership = await findMembershipHouseholdId(uid);
    if (existingMembership != null) {
      await finalizeJoin(existingMembership, uid);
      throw HouseholdException('Du er allerede godkjent som medlem og er nå koblet til husholdningen.');
    }

    final codeDoc = await _inviteCodes.doc(normalizedCode).get();
    if (!codeDoc.exists) {
      throw HouseholdException('Fant ingen husholdning med denne koden.');
    }
    final householdId = codeDoc.data()!['householdId'] as String;
    final householdName = codeDoc.data()!['householdName'] as String? ?? 'husholdningen';

    try {
      await _joinRequests(householdId).doc(uid).set({
        'requestedAt': FieldValue.serverTimestamp(),
        'joinCode': normalizedCode,
      });
    } catch (_) {
      throw HouseholdException('Klarte ikke å sende forespørselen.');
    }

    return JoinRequestSubmitted(householdId: householdId, householdName: householdName);
  }

  /// Fullfører "bli med"-flyten etter at [uid] er godkjent som medlem: setter
  /// husholdnings-id-en på brukerens egen profil.
  Future<void> finalizeJoin(String householdId, String uid) async {
    await _firestore.collection('users').doc(uid).update({'householdId': householdId});
  }

  /// Godkjenner en ventende forespørsel: oppretter medlemskap og fjerner
  /// forespørselen. Kun husholdningens oppretter kan gjøre dette (håndhevet
  /// av firestore.rules).
  Future<void> approveJoinRequest(String householdId, String uid) async {
    await _members(householdId).doc(uid).set({
      'memberUid': uid,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await _joinRequests(householdId).doc(uid).delete();
  }

  /// Avviser en ventende forespørsel: fjerner den uten å opprette medlemskap.
  Future<void> rejectJoinRequest(String householdId, String uid) async {
    await _joinRequests(householdId).doc(uid).delete();
  }

  /// Forlater husholdningen: fjerner eget medlemskap og nullstiller
  /// husholdnings-id-en på egen profil (i den rekkefølgen — reglene krever at
  /// medlemskapet er borte før profilfeltet kan nullstilles). De to skrivene
  /// er bevisst sekvensielle av samme grunn som «bli med»-flyten (se
  /// klassekommentaren), men det betyr at appen kan avbrytes/miste nettet
  /// mellom dem, slik at householdId blir stående igjen uten et tilhørende
  /// medlemskap («foreldreløs» profil). Se [isActualMember]/
  /// [clearOrphanedHouseholdId] for hvordan dette oppdages og repareres ved
  /// neste appstart (AppGate).
  Future<void> leaveHousehold(String householdId, String uid) async {
    await _members(householdId).doc(uid).delete();
    await _firestore.collection('users').doc(uid).update({'householdId': null});
  }

  /// Sjekker om brukeren faktisk har et medlemskapsdokument i husholdningen
  /// `users/{uid}.householdId` peker på. Brukes av AppGate til å oppdage en
  /// «foreldreløs» profil (se [leaveHousehold]) — trygt å kalle for hvem som
  /// helst om seg selv uansett utfall, siden reglene alltid tillater å lese
  /// sin egen medlemskapsstatus.
  Future<bool> isActualMember(String householdId, String uid) async {
    final doc = await _members(householdId).doc(uid).get();
    return doc.exists;
  }

  /// Reparerer en foreldreløs profil ved å nullstille householdId. Tillatt av
  /// reglene nettopp fordi det gamle medlemskapet allerede mangler — se
  /// [isActualMember].
  Future<void> clearOrphanedHouseholdId(String uid) async {
    await _firestore.collection('users').doc(uid).update({'householdId': null});
  }

  Future<String> regenerateInviteCode(String householdId) async {
    final householdDoc = await _households.doc(householdId).get();
    if (!householdDoc.exists) {
      throw HouseholdException('Fant ikke husholdningen.');
    }
    final householdName = householdDoc.data()!['name'] as String;
    await _deleteInviteCodesForHousehold(householdId);
    final newCode = await _findUnusedCode();

    await _inviteCodes.doc(newCode).set({'householdId': householdId, 'householdName': householdName});
    await _households.doc(householdId).update({'inviteCode': newCode});

    return newCode;
  }

  /// Sletter alle oppslag for en husholdning — brukes ved regenerering slik at
  /// gamle og «løse» koder ikke fortsetter å virke.
  Future<void> _deleteInviteCodesForHousehold(String householdId) async {
    final snap = await _inviteCodes.where('householdId', isEqualTo: householdId).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> updateDefaultServings(String householdId, int servings) async {
    await _households.doc(householdId).update({'defaultServings': servings});
  }

  Future<void> updateHiddenRecipeTypes(String householdId, Set<RecipeType> types) async {
    await _households.doc(householdId).update({
      'hiddenRecipeTypes': types.map((t) => t.name).toList(),
    });
  }
}
