import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_profile.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: ['email']);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  /// Logger inn med Google og oppretter en brukerprofil i Firestore hvis det
  /// er første gang brukeren logger inn.
  Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // Brukeren avbrøt innloggingen.
      return;
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    await _ensureUserProfile(userCredential.user!);
  }

  Future<void> _ensureUserProfile(User user) async {
    await ensureUserProfile(user);
  }

  /// Oppretter brukerprofil i Firestore hvis den mangler (f.eks. eldre konto
  /// eller avbrutt innlogging). Trygt å kalle flere ganger.
  Future<void> ensureUserProfile(User user) async {
    final docRef = _users.doc(user.uid);
    final doc = await docRef.get();
    if (doc.exists) return;
    final profile = UserProfile(
      uid: user.uid,
      displayName: user.displayName ?? user.email ?? 'Ukjent bruker',
      email: user.email ?? '',
      photoUrl: user.photoURL,
      householdId: null,
      isAdmin: false,
    );
    await docRef.set(profile.toMap());
  }

  Stream<UserProfile?> userProfileStream(String uid) {
    return _users.doc(uid).snapshots().map(
          (doc) => doc.exists ? UserProfile.fromFirestore(doc) : null,
        );
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
