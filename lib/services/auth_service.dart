import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. Initialize GoogleSignIn with your specific Web Client ID
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // REPLACE THIS STRING with the ID you copied from Google Cloud Console
    // It ends with .apps.googleusercontent.com
    clientId: "1045397450464-g4037emnf8l97vv9n73mifguv3m9dbfl.apps.googleusercontent.com", 
  );

  Future<User?> signInWithGoogle() async {
    try {
      // 2. Use the configured instance (_googleSignIn), NOT a new one
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print("User cancelled the sign-in popup.");
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      return userCredential.user;
    } catch (e) {
      print("CRITICAL ERROR in AuthService: $e");
      return null;
    }
  }

  User? get currentUser => _auth.currentUser;

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}