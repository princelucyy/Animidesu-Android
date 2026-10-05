import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AnimidesuAuthService {
  const AnimidesuAuthService();

  Future<UserCredential> signInWithGoogle() async {
    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw FirebaseAuthException(
        code: 'google-not-supported',
        message: 'Google Sign-In tidak tersedia di platform ini.',
      );
    }

    final googleUser = await signIn.authenticate();
    final googleAuth = googleUser.authentication;

    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'ID token Google tidak tersedia.',
      );
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
