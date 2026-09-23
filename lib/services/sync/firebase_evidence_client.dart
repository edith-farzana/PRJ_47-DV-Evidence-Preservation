import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'evidence_sync_client.dart';

/// The only file in the app that talks to Firebase.
///
/// Two things are deliberate here:
///
///  * **Anonymous auth.** No email, no phone number. A confirmation
///    message would land in an inbox an abuser may be able to read, and
///    a phone number ties the account to a real person.
///  * **Lazy sign-in.** Nothing contacts Google until the first sync
///    after the vault is unlocked. The app reaching out the moment it
///    opens would be a signal in itself, and the calculator must look
///    like a calculator all the way down to the network.
class FirebaseEvidenceClient implements EvidenceSyncClient {
  FirebaseEvidenceClient({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _injectedFirestore = firestore,
       _injectedStorage = storage,
       _injectedAuth = auth;

  final FirebaseFirestore? _injectedFirestore;
  final FirebaseStorage? _injectedStorage;
  final FirebaseAuth? _injectedAuth;

  /// False until `Firebase.initializeApp` has run, which needs
  /// `google-services.json` from `flutterfire configure`. Everything
  /// local keeps working in that state.
  @override
  bool get isConfigured => Firebase.apps.isNotEmpty;

  // Resolved on use, never in the constructor: reaching for
  // `.instance` before initialization throws.
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;

  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  Future<String> _uid() async {
    if (!isConfigured) {
      throw const SyncUnavailableException(
        'Firebase is not configured in this build.',
      );
    }

    final existing = _auth.currentUser;

    if (existing != null) {
      return existing.uid;
    }

    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;

      if (user == null) {
        throw const SyncUnavailableException(
          'Anonymous sign-in returned no '
          'user.',
        );
      }

      return user.uid;
    } on FirebaseAuthException catch (error) {
      throw SyncUnavailableException('Could not sign in: ${error.message}');
    }
  }

  @override
  Future<void> writeMetadata(
    String evidenceId,
    Map<String, Object?> payload,
  ) async {
    final uid = await _uid();

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('evidence')
          .doc(evidenceId)
          .set(payload);
    } on FirebaseException catch (error) {
      // The rules allow create and deny update, so a refusal here means
      // the record is already on the server. That is the immutability
      // working, not a failure.
      if (error.code == 'permission-denied') {
        return;
      }

      throw SyncFailedException('Could not record evidence: ${error.message}');
    }
  }

  @override
  Future<void> uploadBlob(String evidenceId, File blob) async {
    final uid = await _uid();

    try {
      await _storage
          .ref('users/$uid/evidence/$evidenceId.enc')
          .putFile(
            blob,
            SettableMetadata(contentType: 'application/octet-stream'),
          );
    } on FirebaseException catch (error) {
      // The bucket is named in google-services.json whether or not it
      // was ever created, so "Storage was never enabled" arrives here
      // as a not-found. Say that, rather than passing on an error that
      // reads like the evidence is the problem.
      if (error.code == 'object-not-found' ||
          error.code == 'unknown' ||
          error.code == 'bucket-not-found') {
        throw const SyncUnavailableException(
          'Cloud storage is not set up for this project yet, so the file '
          'copy could not be saved. The evidence on this phone is '
          'untouched.',
        );
      }

      throw SyncFailedException('Could not upload evidence: ${error.message}');
    }
  }

  @override
  Future<void> writeReceipt(
    String evidenceId,
    Map<String, Object?> payload,
  ) async {
    final uid = await _uid();

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('backups')
          .doc(evidenceId)
          .set(payload);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return;
      }

      throw SyncFailedException(
        'Could not record the backup: '
        '${error.message}',
      );
    }
  }

  @override
  Future<Set<String>> backedUpIds() async {
    final uid = await _uid();

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('backups')
          .get();

      return snapshot.docs.map((document) => document.id).toSet();
    } on FirebaseException catch (error) {
      throw SyncFailedException('Could not read backups: ${error.message}');
    }
  }
}
