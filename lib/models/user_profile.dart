import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.householdId,
    required this.isAdmin,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  /// Null hvis brukeren ikke har opprettet eller blitt med i en husholdning ennå.
  final String? householdId;

  /// Kan godkjenne/avvise oppskrifter foreslått for det globale settet.
  final bool isAdmin;

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      householdId: data['householdId'] as String?,
      isAdmin: data['isAdmin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'householdId': householdId,
      'isAdmin': isAdmin,
    };
  }

  UserProfile copyWith({String? householdId}) {
    return UserProfile(
      uid: uid,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
      householdId: householdId ?? this.householdId,
      isAdmin: isAdmin,
    );
  }
}
