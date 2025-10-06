import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
//import 'package:device_preview/device_preview.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _fireStore = FirebaseFirestore.instance; // Istanza di Firestore
  final GoogleSignIn _googleSignIn = GoogleSignIn(); // Istanza di Google Sign-In

  Future<UserCredential> signInWithEmailandPassword(String email, String password) async {
    try {
      UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        // Se l'email non è verificata, disconnetti l'utente
        await _firebaseAuth.signOut();
        throw FirebaseAuthException(
          code: 'email-not-verified',
          message: 'L\'email non è stata verificata. Controlla la tua casella di posta.',
        );
      }

      // Salva l'utente in Firestore
      _fireStore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      throw Exception(e.toString());
    }
  }


  // Funzione di registrazione con email e password
  Future<UserCredential> signUpWithEmailandPassword(String email, String password) async {
    try {
      // Registrazione con Firebase
      UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Invia l'email di verifica all'utente appena registrato
      await userCredential.user!.sendEmailVerification();

      // Aggiungi l'utente a Firestore
      _fireStore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
      });

      return userCredential;
    }
    on FirebaseAuthException catch (e) {
      throw Exception(e.code);
    }
  }

  // Funzione di login con Google
  Future<User?> signInWithGoogle() async {
    try {
      // Google Sign-In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // L'utente ha annullato il login
      }

      // Ottieni le credenziali di Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Crea le credenziali per Firebase
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Effettua il login con Firebase usando le credenziali di Google
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);

      // Aggiungi l'utente a Firestore se non esiste già
      _fireStore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': userCredential.user!.email,
      }, SetOptions(merge: true));

      return userCredential.user;
    }
    on FirebaseAuthException catch (e) {
      print(e.message);
      return null;
    }
  }

  // Funzione per il logout
  Future<void> signOut() async {
    return await FirebaseAuth.instance.signOut();
  }

  // Funzione per controllare se l'utente è autenticato e ha verificato l'email
  User? getCurrentUser() {
    User? user = _firebaseAuth.currentUser;
    if (user != null && user.emailVerified) {
      return user;
    }
    return null;
  }

  // Funzione per rinviare l'email di verifica
  Future<void> sendEmailVerification() async {
    User? user = _firebaseAuth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    } else {
      throw Exception("L'utente non è disponibile o ha già verificato l'email.");
    }
  }
}
