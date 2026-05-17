import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FlashLearnApp());
}

// ─── APP ──────────────────────────────────────────────────────────────────────
class FlashLearnApp extends StatelessWidget {
  const FlashLearnApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A00E0)),
      ),
      home: const AuthGateScreen(),
    );
  }
}

// ─── DESIGN TOKENS ───────────────────────────────────────────────────────────
const kGradientStart = Color(0xFF0F0C29);
const kGradientMid = Color(0xFF302B63);
const kGradientEnd = Color(0xFF24243E);
const kAccent = Color(0xFF9B59B6);
const kAccentLight = Color(0xFFBB86FC);
const kAccentGlow = Color(0xFF7C3AED);
const kCardBg = Color(0xFF1E1B3A);
const kCardBgLight = Color(0xFF2A2750);
const kTextPrimary = Color(0xFFF0EEFF);
const kTextSecondary = Color(0xFFAA9FCC);
const kSuccess = Color(0xFF4CAF50);
const kError = Color(0xFFEF5350);
const kWarning = Color(0xFFFF9800);

LinearGradient get kBgGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [kGradientStart, kGradientMid, kGradientEnd]);

LinearGradient get kButtonGradient =>
    const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF9B59B6)]);

BoxDecoration kCardDecoration({Color? color, double radius = 20}) =>
    BoxDecoration(
      color: color ?? kCardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: kAccentLight.withAlpha(40), width: 1),
      boxShadow: [
        BoxShadow(
            color: kAccentGlow.withAlpha(30), blurRadius: 20, spreadRadius: 2)
      ],
    );

// ─── MODELS ───────────────────────────────────────────────────────────────────
class Flashcard {
  String id;
  String question;
  String answer;
  String mode;
  String? userAnswer;
  Flashcard(
      {this.id = '',
      required this.question,
      required this.answer,
      required this.mode,
      this.userAnswer});

  factory Flashcard.fromMap(Map<String, dynamic> m, String id) => Flashcard(
      id: id,
      question: m['question'] ?? '',
      answer: m['answer'] ?? '',
      mode: m['mode'] ?? 'Identification');

  Map<String, dynamic> toMap() =>
      {'question': question, 'answer': answer, 'mode': mode};
}

class Deck {
  String id;
  String name;
  List<Flashcard> cards;
  String? reviewerText;
  Deck(
      {this.id = '',
      required this.name,
      required this.cards,
      this.reviewerText});

  factory Deck.fromMap(Map<String, dynamic> m, String id) => Deck(
      id: id,
      name: m['name'] ?? '',
      cards: [],
      reviewerText: m['reviewerText']);

  Map<String, dynamic> toMap() =>
      {'name': name, if (reviewerText != null) 'reviewerText': reviewerText};
}

class Reviewer {
  String id;
  String title;
  String content;
  String? linkedDeckId;
  DateTime? createdAt;
  Reviewer(
      {this.id = '',
      required this.title,
      required this.content,
      this.linkedDeckId,
      this.createdAt});

  factory Reviewer.fromMap(Map<String, dynamic> m, String id) => Reviewer(
        id: id,
        title: m['title'] ?? 'Untitled',
        content: m['content'] ?? '',
        linkedDeckId: m['linkedDeckId'],
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'content': content,
        if (linkedDeckId != null) 'linkedDeckId': linkedDeckId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class Note {
  String id;
  String title;
  String description;
  Note({this.id = '', required this.title, required this.description});

  factory Note.fromMap(Map<String, dynamic> m, String id) => Note(
      id: id, title: m['title'] ?? '', description: m['description'] ?? '');

  Map<String, dynamic> toMap() => {'title': title, 'description': description};
}

// ─── GLOBAL STATE ─────────────────────────────────────────────────────────────
List<Deck> globalDecks = [];
List<Deck> trashedDecks = [];
List<Reviewer> globalReviewers = [];
List<Note> globalNotes = [];
int totalQuizzesTaken = 0;
int totalQuestionsAnswered = 0;
int totalCorrectAnswers = 0;
int totalCardsStudied = 0;
int totalFlashcardSessions = 0;
int totalFlashcardsKnown = 0;
int totalFlashcardsUnknown = 0;
Set<String> daysStudied = {};

// ─── FIRESTORE SERVICE ────────────────────────────────────────────────────────
class FirestoreService {
  final _db = FirebaseFirestore.instance;

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _decks =>
      _db.collection('users').doc(uid).collection('decks');
  CollectionReference get _reviewers =>
      _db.collection('users').doc(uid).collection('reviewers');
  CollectionReference get _notes =>
      _db.collection('users').doc(uid).collection('notes');
  DocumentReference get _stats => _db.collection('users').doc(uid);

  // ── Decks ─────────────────────────────────────────────────────────────────
  Future<List<Deck>> loadDecks() async {
    if (uid.isEmpty) return [];
    final snap = await _decks.get();
    List<Deck> decks = [];
    for (var doc in snap.docs) {
      final deck = Deck.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      final cardSnap = await _decks.doc(doc.id).collection('cards').get();
      deck.cards =
          cardSnap.docs.map((c) => Flashcard.fromMap(c.data(), c.id)).toList();
      decks.add(deck);
    }
    return decks;
  }

  Future<String> createOrGetDeck(String name) async {
    if (uid.isEmpty) throw Exception('User not authenticated');
    final existing = await _decks.where('name', isEqualTo: name).limit(1).get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;
    final doc = await _decks.add(
        {'name': name, 'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<String> restoreDeck(Deck deck) async {
    if (uid.isEmpty) throw Exception('User not authenticated');
    final docRef = await _decks.add({
      'name': deck.name,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (deck.reviewerText != null) 'reviewerText': deck.reviewerText,
    });
    for (final card in deck.cards) {
      await docRef.collection('cards').add({
        'question': card.question,
        'answer': card.answer,
        'mode': card.mode
      });
    }
    return docRef.id;
  }

  Future<String> addCard(
      String deckId, String question, String answer, String mode) async {
    final doc = await _decks
        .doc(deckId)
        .collection('cards')
        .add({'question': question, 'answer': answer, 'mode': mode});
    return doc.id;
  }

  Future<void> updateCard(String deckId, String cardId, String question,
      String answer, String mode) async {
    await _decks
        .doc(deckId)
        .collection('cards')
        .doc(cardId)
        .update({'question': question, 'answer': answer, 'mode': mode});
  }

  Future<void> deleteCard(String deckId, String cardId) async {
    await _decks.doc(deckId).collection('cards').doc(cardId).delete();
  }

  Future<void> deleteDeck(String deckId) async {
    final cards = await _decks.doc(deckId).collection('cards').get();
    for (var c in cards.docs) {
      await c.reference.delete();
    }
    await _decks.doc(deckId).delete();
  }

  Future<void> updateDeckName(String deckId, String newName) async {
    await _decks.doc(deckId).update({'name': newName});
  }

  Future<void> saveReviewerText(String deckId, String text) async {
    await _decks.doc(deckId).update({'reviewerText': text});
  }

  // ── Reviewers ─────────────────────────────────────────────────────────────
  Future<List<Reviewer>> loadReviewers() async {
    if (uid.isEmpty) return [];
    final snap = await _reviewers.orderBy('createdAt', descending: true).get();
    return snap.docs
        .map((d) => Reviewer.fromMap(d.data() as Map<String, dynamic>, d.id))
        .toList();
  }

  Future<String> addReviewer(String title, String content,
      {String? linkedDeckId}) async {
    if (uid.isEmpty) throw Exception('User not authenticated');
    final doc = await _reviewers.add({
      'title': title,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'uid': uid,
      if (linkedDeckId != null) 'linkedDeckId': linkedDeckId,
    });
    return doc.id;
  }

  Future<void> updateReviewer(String id, String title, String content,
      {String? linkedDeckId}) async {
    await _reviewers.doc(id).update({
      'title': title,
      'content': content,
      'linkedDeckId': linkedDeckId,
    });
  }

  Future<void> deleteReviewer(String id) async {
    await _reviewers.doc(id).delete();
  }

  // ── Notes ─────────────────────────────────────────────────────────────────
  Future<List<Note>> loadNotes() async {
    if (uid.isEmpty) return [];
    final snap = await _notes.orderBy('createdAt', descending: false).get();
    return snap.docs
        .map((d) => Note.fromMap(d.data() as Map<String, dynamic>, d.id))
        .toList();
  }

  Future<String> addNote(String title, String description) async {
    if (uid.isEmpty) throw Exception('User not authenticated');
    final doc = await _notes.add({
      'title': title,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'uid': uid,
    });
    return doc.id;
  }

  Future<void> updateNote(String id, String title, String description) async {
    await _notes.doc(id).update({'title': title, 'description': description});
  }

  Future<void> deleteNote(String id) async {
    await _notes.doc(id).delete();
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Future<void> saveStats() async {
    if (uid.isEmpty) return;
    await _stats.set({
      'stats': {
        'totalQuizzesTaken': totalQuizzesTaken,
        'totalQuestionsAnswered': totalQuestionsAnswered,
        'totalCorrectAnswers': totalCorrectAnswers,
        'totalCardsStudied': totalCardsStudied,
        'totalFlashcardSessions': totalFlashcardSessions,
        'totalFlashcardsKnown': totalFlashcardsKnown,
        'totalFlashcardsUnknown': totalFlashcardsUnknown,
        'daysStudied': daysStudied.toList(),
      }
    }, SetOptions(merge: true));
  }

  Future<void> loadStats() async {
    if (uid.isEmpty) return;
    final doc = await _stats.get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null || data['stats'] == null) return;
    final s = data['stats'] as Map<String, dynamic>;
    totalQuizzesTaken = (s['totalQuizzesTaken'] ?? 0) as int;
    totalQuestionsAnswered = (s['totalQuestionsAnswered'] ?? 0) as int;
    totalCorrectAnswers = (s['totalCorrectAnswers'] ?? 0) as int;
    totalCardsStudied = (s['totalCardsStudied'] ?? 0) as int;
    totalFlashcardSessions = (s['totalFlashcardSessions'] ?? 0) as int;
    totalFlashcardsKnown = (s['totalFlashcardsKnown'] ?? 0) as int;
    totalFlashcardsUnknown = (s['totalFlashcardsUnknown'] ?? 0) as int;
    daysStudied = Set<String>.from((s['daysStudied'] as List<dynamic>? ?? []));
  }
}

// ─── AUTH SERVICE ─────────────────────────────────────────────────────────────
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Simple reversible obfuscation — XOR each char with a key derived from email.
  // Not cryptographic security, but prevents plain-text storage in Firestore.
  String _obfuscate(String value, String key) {
    final kb = key.codeUnits;
    final result = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      result.writeCharCode(value.codeUnitAt(i) ^ kb[i % kb.length]);
    }
    // Base64-encode so it's safe to store as a Firestore string
    return _b64Encode(result.toString());
  }

  String _deobfuscate(String encoded, String key) {
    final decoded = _b64Decode(encoded);
    final kb = key.codeUnits;
    final result = StringBuffer();
    for (var i = 0; i < decoded.length; i++) {
      result.writeCharCode(decoded.codeUnitAt(i) ^ kb[i % kb.length]);
    }
    return result.toString();
  }

  // Simple base64 using dart:convert-free approach (just store as codeUnit list)
  String _b64Encode(String s) {
    final bytes = s.codeUnits;
    return bytes.map((b) => b.toString().padLeft(3, '0')).join('');
  }

  String _b64Decode(String encoded) {
    final result = StringBuffer();
    for (var i = 0; i < encoded.length; i += 3) {
      result.writeCharCode(int.parse(encoded.substring(i, i + 3)));
    }
    return result.toString();
  }

  Future<String?> signUp(String email, String password, String name) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      await cred.user!.updateDisplayName(name);
      final key = email.trim() + name.trim();
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        '_pk': _obfuscate(password, key),
      });
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      // Keep _pk in sync so forgot-password can recover the credential
      final uid = cred.user!.uid;
      final name = cred.user!.displayName ?? '';
      final key = email.trim() + name.trim();
      await _db
          .collection('users')
          .doc(uid)
          .set({'_pk': _obfuscate(password, key)}, SetOptions(merge: true));
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  Future<void> signOut(BuildContext context) async {
    globalDecks.clear();
    trashedDecks.clear();
    globalReviewers.clear();
    globalNotes.clear();
    await _auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  // ── Forgot Password: verify email + full name match account
  // Reads the public /users/{uid} document (Firestore rule allows unauthenticated
  // reads on the top-level user doc, while subcollections stay protected).
  Future<String?> verifyEmailAndName(String email, String fullName) async {
    try {
      final snap = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return 'No account found with this email address.';
      final storedName = (snap.docs.first.data()['name'] ?? '') as String;
      if (storedName.trim().toLowerCase() != fullName.trim().toLowerCase()) {
        return 'The name you entered does not match the account.';
      }
      return null; // ✓ both match
    } catch (_) {
      return 'No account found with this email address.';
    }
  }

  // ── Forgot Password: verify email only
  Future<String?> verifyEmailExists(String email) async {
    try {
      final snap = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return 'No account found with this email address.';
      return null;
    } catch (_) {
      return 'No account found with this email address.';
    }
  }

  /// Re-authenticate with stored credential, update password, re-save obfuscated value.
  Future<String?> changePasswordWithEmail(
      String email, String name, String newPassword) async {
    try {
      // Fetch the stored obfuscated password from Firestore
      final snap = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return 'Account not found.';
      final data = snap.docs.first.data();
      final uid = snap.docs.first.id;
      final pk = data['_pk'] as String? ?? '';
      if (pk.isEmpty)
        return 'Unable to reset password. Please contact support.';

      final key = email.trim() + (data['name'] as String? ?? name).trim();
      final currentPass = _deobfuscate(pk, key);

      // Sign in silently with the recovered password
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: currentPass);

      // Update to the new password in Firebase Auth
      await cred.user!.updatePassword(newPassword);

      // Update the stored obfuscated value with the new password
      final newKey = email.trim() + (data['name'] as String? ?? name).trim();
      await _db
          .collection('users')
          .doc(uid)
          .update({'_pk': _obfuscate(newPassword, newKey)});

      // Sign out — user must log in normally
      await _auth.signOut();
      return null;
    } on FirebaseAuthException catch (_) {
      return 'Failed to reset password...';
    } catch (_) {
      return 'Failed to reset password. Please try again.';
    }
  }

  /// Change password when already signed in
  Future<String?> changePasswordSignedIn(String newPassword) async {
    try {
      await _auth.currentUser?.updatePassword(newPassword);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  User? get currentUser => _auth.currentUser;
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────
Widget gradientScaffold(
    {required Widget body,
    PreferredSizeWidget? appBar,
    Widget? bottomNav,
    bool safeArea = true}) {
  Widget content = safeArea ? SafeArea(child: body) : body;
  return Scaffold(
    extendBodyBehindAppBar: true,
    backgroundColor: kGradientStart,
    appBar: appBar,
    body: Container(
        decoration: BoxDecoration(gradient: kBgGradient), child: content),
    bottomNavigationBar: bottomNav,
  );
}

AppBar gradientAppBar(String title, {List<Widget>? actions}) => AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: kTextPrimary),
      title: Text(title,
          style: const TextStyle(
              color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 20)),
      actions: actions,
    );

Widget glowButton(
    {required String label,
    required VoidCallback onTap,
    Color? color,
    IconData? icon,
    double height = 56}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color ?? kAccentGlow,
          (color ?? kAccentGlow).withAlpha(180)
        ]),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: (color ?? kAccentGlow).withAlpha(80),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10)
        ],
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      ]),
    ),
  );
}

Widget buildBottomNav(BuildContext context, int currentIndex) {
  return Container(
    decoration: BoxDecoration(
      color: kCardBg,
      border:
          Border(top: BorderSide(color: kAccentLight.withAlpha(50), width: 1)),
    ),
    child: BottomNavigationBar(
      currentIndex: currentIndex,
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: kAccentLight,
      unselectedItemColor: kTextSecondary,
      onTap: (index) {
        if (index == 0)
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainMenuScreen()),
              (_) => false);
        if (index == 1)
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const StatsScreen()));
        if (index == 2)
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TrashScreen()));
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded), label: 'Stats'),
        BottomNavigationBarItem(
            icon: Icon(Icons.delete_rounded), label: 'Trash'),
      ],
    ),
  );
}

// ─── SCREEN 0: AUTH GATE ─────────────────────────────────────────────────────
class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(gradient: kBgGradient),
            child: const Center(
                child: CircularProgressIndicator(color: kAccentLight)),
          );
        }
        if (snap.hasData && snap.data != null) return const MainMenuScreen();
        return const LoginScreen();
      },
    );
  }
}

// ─── SCREEN A: LOGIN ─────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  final _auth = AuthService();

  void _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = "Please fill in all fields.";
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final err = await _auth.signIn(email, password);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _loading = false;
          _error =
              "There was an error with your email/password combination, please double check and try again.";
        });
      } else {
        setState(() => _loading = false);
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainMenuScreen()),
            (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            "There was an error with your email/password combination, please double check and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(children: [
          const SizedBox(height: 80),
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4A00E0)]),
                  boxShadow: [
                    BoxShadow(
                        color: kAccentGlow.withAlpha(120),
                        blurRadius: 25,
                        spreadRadius: 2)
                  ]),
              child: const Icon(Icons.lightbulb_rounded,
                  color: Colors.amber, size: 48)),
          const SizedBox(height: 16),
          const Text("Flash Learn",
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: kTextPrimary,
                  letterSpacing: -0.5)),
          const Text("Quick study, smart recall",
              style: TextStyle(
                  color: kTextSecondary, fontSize: 13, letterSpacing: 1)),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: kCardDecoration(),
            child: Column(children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Sign In",
                      style: TextStyle(
                          color: kTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800))),
              const SizedBox(height: 20),
              _authField(_emailCtrl, "Email", Icons.email_outlined,
                  isEmail: true),
              const SizedBox(height: 14),
              _authField(_passCtrl, "Password", Icons.lock_outline,
                  isPass: true),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: kError.withAlpha(40),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: kError, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: kError, fontSize: 13))),
                    ])),
              ],
              const SizedBox(height: 20),
              _loading
                  ? const CircularProgressIndicator(color: kAccentLight)
                  : glowButton(
                      label: "Sign In",
                      onTap: _login,
                      icon: Icons.login_rounded),
              const SizedBox(height: 14),
              GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen())),
                  child: const Text("Forgot Password?",
                      style: TextStyle(
                          color: kAccentLight,
                          fontSize: 14,
                          fontWeight: FontWeight.w600))),
              const SizedBox(height: 14),
              GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen())),
                  child: RichText(
                      text: const TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: kTextSecondary, fontSize: 14),
                          children: [
                        TextSpan(
                            text: "Sign Up",
                            style: TextStyle(
                                color: kAccentLight,
                                fontWeight: FontWeight.w700))
                      ]))),
            ]),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _authField(TextEditingController ctrl, String label, IconData icon,
      {bool isPass = false, bool isEmail = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass && _obscure,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(color: kTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary),
        prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: kTextSecondary,
                    size: 20),
                onPressed: () => setState(() => _obscure = !_obscure))
            : null,
        filled: true,
        fillColor: kCardBgLight,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
      ),
    );
  }
}

// ─── SCREEN A2: FORGOT PASSWORD ───────────────────────────────────────────────
// Flow: Step 1 — enter email, verify it exists in Firebase.
//       Step 2 — if verified, let user set a new password (uses Firebase reset email under the hood).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _credVerified = false;
  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _done = false;
  String? _error;
  final _auth = AuthService();

  void _verifyCredentials() async {
    final email = _emailCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || name.isEmpty) {
      setState(() => _error = "Please enter both your email and full name.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await _auth.verifyEmailAndName(email, name);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
    } else {
      setState(() {
        _loading = false;
        _credVerified = true;
      });
    }
  }

  void _resetPassword() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.isEmpty || confirm.isEmpty) {
      setState(() => _error = "Please fill in both password fields.");
      return;
    }
    if (pass != confirm) {
      setState(() => _error = "Passwords do not match.");
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = "Password must be at least 6 characters.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await _auth.changePasswordWithEmail(
        _emailCtrl.text.trim(), _nameCtrl.text.trim(), pass);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
      _done = err == null;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("Forgot Password"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: kCardDecoration(),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_reset_rounded, color: kAccentLight, size: 40),
            const SizedBox(height: 14),
            Text(_credVerified ? "Set New Password" : "Reset Password",
                style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                _credVerified
                    ? "Your identity has been confirmed. Enter your new password below."
                    : "Enter the email address and full name linked to your account.",
                style: const TextStyle(
                    color: kTextSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 24),
            if (!_credVerified) ...[
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: kTextPrimary),
                decoration: InputDecoration(
                  labelText: "Email",
                  labelStyle: const TextStyle(color: kTextSecondary),
                  prefixIcon: const Icon(Icons.email_outlined,
                      color: kTextSecondary, size: 20),
                  filled: true,
                  fillColor: kCardBgLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kAccentLight, width: 1.5)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: kTextPrimary),
                decoration: InputDecoration(
                  labelText: "Full Name",
                  labelStyle: const TextStyle(color: kTextSecondary),
                  prefixIcon: const Icon(Icons.person_outline,
                      color: kTextSecondary, size: 20),
                  filled: true,
                  fillColor: kCardBgLight,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: kAccentLight, width: 1.5)),
                ),
              ),
            ] else ...[
              // Credentials confirmed — show new password fields
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: kSuccess.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kSuccess.withAlpha(80))),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                        color: kSuccess, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            "Identity confirmed: ${_emailCtrl.text.trim()}",
                            style: const TextStyle(
                                color: kSuccess, fontSize: 13))),
                  ])),
              const SizedBox(height: 16),
              _passField(_passCtrl, "New Password", _obscurePass,
                  () => setState(() => _obscurePass = !_obscurePass)),
              const SizedBox(height: 12),
              _passField(_confirmCtrl, "Confirm New Password", _obscureConf,
                  () => setState(() => _obscureConf = !_obscureConf)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: kError.withAlpha(40),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: kError, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style:
                                const TextStyle(color: kError, fontSize: 13))),
                  ])),
            ],
            if (_done) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: kSuccess.withAlpha(40),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Row(children: [
                    Icon(Icons.check_circle_outline, color: kSuccess, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            "Password updated successfully! You can now sign in with your new password.",
                            style: TextStyle(color: kSuccess, fontSize: 13))),
                  ])),
            ],
            const SizedBox(height: 20),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kAccentLight))
                : _done
                    ? glowButton(
                        label: "Back to Sign In",
                        onTap: () => Navigator.pop(context),
                        icon: Icons.arrow_back_rounded)
                    : glowButton(
                        label: _credVerified
                            ? "Reset Password"
                            : "Verify Identity",
                        onTap:
                            _credVerified ? _resetPassword : _verifyCredentials,
                        icon: _credVerified
                            ? Icons.lock_reset_rounded
                            : Icons.verified_rounded),
            const SizedBox(height: 14),
            if (!_done)
              Center(
                  child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text("Back to Sign In",
                          style: TextStyle(
                              color: kAccentLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)))),
          ]),
        ),
      ),
    );
  }

  Widget _passField(TextEditingController ctrl, String label, bool obscure,
      VoidCallback toggle) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: kTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary),
        prefixIcon:
            const Icon(Icons.lock_outline, color: kTextSecondary, size: 20),
        suffixIcon: IconButton(
            icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: kTextSecondary,
                size: 20),
            onPressed: toggle),
        filled: true,
        fillColor: kCardBgLight,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
      ),
    );
  }
}

// ─── SCREEN B: SIGN UP ───────────────────────────────────────────────────────
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  final _auth = AuthService();

  void _signUp() async {
    if (_passCtrl.text != _confCtrl.text) {
      setState(() => _error = "Passwords do not match.");
      return;
    }
    if (_nameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _passCtrl.text.isEmpty) {
      setState(() => _error = "Please fill in all fields.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await _auth.signUp(
        _emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
    } else {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
          (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("Create Account"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: kCardDecoration(),
            child: Column(children: [
              _field(_nameCtrl, "Full Name", Icons.person_outline),
              const SizedBox(height: 14),
              _field(_emailCtrl, "Email", Icons.email_outlined, isEmail: true),
              const SizedBox(height: 14),
              _field(_passCtrl, "Password", Icons.lock_outline, isPass: true),
              const SizedBox(height: 14),
              _field(_confCtrl, "Confirm Password", Icons.lock_outline,
                  isPass: true),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: kError.withAlpha(40),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: kError, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: kError, fontSize: 13))),
                    ])),
              ],
              const SizedBox(height: 20),
              _loading
                  ? const CircularProgressIndicator(color: kAccentLight)
                  : glowButton(
                      label: "Create Account",
                      onTap: _signUp,
                      icon: Icons.person_add_rounded),
            ]),
          ),
          const SizedBox(height: 16),
          GestureDetector(
              onTap: () => Navigator.pop(context),
              child: RichText(
                  text: const TextSpan(
                      text: "Already have an account? ",
                      style: TextStyle(color: kTextSecondary, fontSize: 14),
                      children: [
                    TextSpan(
                        text: "Sign In",
                        style: TextStyle(
                            color: kAccentLight, fontWeight: FontWeight.w700))
                  ]))),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool isPass = false, bool isEmail = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPass && _obscure,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(color: kTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary),
        prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: kTextSecondary,
                    size: 20),
                onPressed: () => setState(() => _obscure = !_obscure))
            : null,
        filled: true,
        fillColor: kCardBgLight,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
      ),
    );
  }
}

// ─── SCREEN 1: MAIN MENU ──────────────────────────────────────────────────────
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final _fs = FirestoreService();
  final _auth = AuthService();
  final _noteTitleCtrl = TextEditingController();
  final _noteDescCtrl = TextEditingController();
  bool _loadingDecks = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loadingDecks = false);
        return;
      }
      final decks = await _fs.loadDecks();
      final reviewers = await _fs.loadReviewers();
      final notes = await _fs.loadNotes();
      await _fs.loadStats();
      if (mounted) {
        setState(() {
          globalDecks = decks;
          globalReviewers = reviewers;
          globalNotes = notes;
          _loadingDecks = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDecks = false);
      debugPrint("Load error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return gradientScaffold(
      bottomNav: buildBottomNav(context, 0),
      body: _loadingDecks
          ? const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  CircularProgressIndicator(color: kAccentLight),
                  SizedBox(height: 16),
                  Text("Loading your decks...",
                      style: TextStyle(color: kTextSecondary)),
                ]))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                const SizedBox(height: 30),
                _buildHeader(user),
                const SizedBox(height: 30),
                _buildMenuButton("Start Review", kSuccess, Icons.bolt_rounded,
                    () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DeckSelectScreen()));
                  setState(() {});
                }),
                const SizedBox(height: 12),
                _buildMenuButton(
                    "Create FlashCards", kAccentGlow, Icons.add_circle_rounded,
                    () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreateFlashcardScreen()));
                  setState(() {});
                }),
                const SizedBox(height: 12),
                _buildMenuButton(
                    "My Decks", const Color(0xFF1565C0), Icons.folder_rounded,
                    () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyDecksListScreen()));
                  setState(() {});
                }),
                const SizedBox(height: 12),
                _buildMenuButton("My Reviewers", const Color(0xFF00796B),
                    Icons.menu_book_rounded, () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ReviewerListScreen()));
                  setState(() {});
                }),
                const SizedBox(height: 24),
                _buildNotesSection(),
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  Widget _buildHeader(User? user) {
    return Row(children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4A00E0)]),
                boxShadow: [
                  BoxShadow(
                      color: kAccentGlow.withAlpha(120),
                      blurRadius: 25,
                      spreadRadius: 2)
                ]),
            child: const Icon(Icons.lightbulb_rounded,
                color: Colors.amber, size: 32)),
        const SizedBox(height: 10),
        const Text("Flash Learn",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: kTextPrimary,
                letterSpacing: -0.5)),
        Text("Hello, ${user?.displayName ?? 'Learner'}!",
            style: const TextStyle(color: kTextSecondary, fontSize: 13)),
      ])),
      GestureDetector(
        onTap: () => _auth.signOut(context),
        child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kCardBgLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kAccentLight.withAlpha(40))),
            child: const Icon(Icons.logout_rounded, color: kError, size: 20)),
      ),
    ]);
  }

  Widget _buildMenuButton(
      String title, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
            color: color.withAlpha(220),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: color.withAlpha(80),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]),
        child: Row(children: [
          const SizedBox(width: 20),
          Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          const SizedBox(width: 16),
        ]),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      constraints: const BoxConstraints(minHeight: 150, maxHeight: 260),
      decoration: kCardDecoration(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(children: [
            const Icon(Icons.sticky_note_2_rounded,
                color: kAccentLight, size: 20),
            const SizedBox(width: 8),
            const Text("NOTES",
                style: TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 1.5)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.add_rounded, color: kAccentLight),
                onPressed: () => showDialog(
                    context: context, builder: (_) => _buildNoteDialog())),
          ]),
        ),
        Divider(color: kAccentLight.withAlpha(40), height: 1),
        Expanded(
          child: globalNotes.isEmpty
              ? const Center(
                  child: Text("No notes yet. Tap + to add.",
                      style: TextStyle(color: kTextSecondary, fontSize: 13)))
              : ListView.builder(
                  itemCount: globalNotes.length,
                  itemBuilder: (_, i) {
                    final note = globalNotes[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle,
                          color: kAccentLight, size: 8),
                      title: Text(note.title,
                          style: const TextStyle(
                              color: kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      subtitle: note.description.isNotEmpty
                          ? Text(note.description,
                              style: const TextStyle(
                                  color: kTextSecondary, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () => _showNoteOptions(i),
                    );
                  }),
        ),
      ]),
    );
  }

  void _showNoteOptions(int i) {
    final note = globalNotes[i];
    showModalBottomSheet(
      context: context,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.title,
                  style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              if (note.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(note.description,
                    style: const TextStyle(
                        color: kTextSecondary, fontSize: 14, height: 1.5)),
              ],
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                        context: context,
                        builder: (_) => _buildNoteDialog(editIndex: i));
                  },
                  child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: kAccentGlow.withAlpha(40),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kAccentGlow.withAlpha(80))),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded,
                                color: kAccentLight, size: 18),
                            SizedBox(width: 8),
                            Text("Edit",
                                style: TextStyle(
                                    color: kAccentLight,
                                    fontWeight: FontWeight.w700)),
                          ])),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await _fs.deleteNote(note.id);
                    setState(() => globalNotes.removeAt(i));
                  },
                  child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: kError.withAlpha(40),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kError.withAlpha(80))),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_rounded, color: kError, size: 18),
                            SizedBox(width: 8),
                            Text("Delete",
                                style: TextStyle(
                                    color: kError,
                                    fontWeight: FontWeight.w700)),
                          ])),
                )),
              ]),
              const SizedBox(height: 8),
            ]),
      ),
    );
  }

  Widget _buildNoteDialog({int? editIndex}) {
    final isEdit = editIndex != null;
    if (isEdit) {
      _noteTitleCtrl.text = globalNotes[editIndex].title;
      _noteDescCtrl.text = globalNotes[editIndex].description;
    } else {
      _noteTitleCtrl.clear();
      _noteDescCtrl.clear();
    }
    return StatefulBuilder(builder: (ctx, setDialogState) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E1B3A), Color(0xFF2A2750)]),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kAccentLight.withAlpha(50)),
              boxShadow: [
                BoxShadow(
                    color: kAccentGlow.withAlpha(60),
                    blurRadius: 30,
                    spreadRadius: 2)
              ]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    kAccentGlow.withAlpha(200),
                    kAccentGlow.withAlpha(100)
                  ]),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28))),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.edit_note_rounded,
                        color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(isEdit ? "Edit Note" : "New Note",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Title",
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Container(
                        decoration: BoxDecoration(
                            color: kCardBgLight,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: kAccentLight.withAlpha(40))),
                        child: TextField(
                            controller: _noteTitleCtrl,
                            style: const TextStyle(
                                color: kTextPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(
                                hintText: "Note title",
                                hintStyle: TextStyle(color: kTextSecondary),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                prefixIcon: Icon(Icons.title_rounded,
                                    color: kAccentLight, size: 18)))),
                    const SizedBox(height: 14),
                    const Text("Description",
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Container(
                        decoration: BoxDecoration(
                            color: kCardBgLight,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: kAccentLight.withAlpha(30))),
                        child: TextField(
                            controller: _noteDescCtrl,
                            maxLines: 4,
                            style: const TextStyle(
                                color: kTextPrimary, fontSize: 14, height: 1.6),
                            decoration: const InputDecoration(
                                hintText: "Add a description",
                                hintStyle: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 13,
                                    height: 1.5),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14)))),
                  ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(children: [
                Expanded(
                    child: GestureDetector(
                        onTap: () {
                          _noteTitleCtrl.clear();
                          _noteDescCtrl.clear();
                          Navigator.pop(ctx);
                        },
                        child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: kAccentLight.withAlpha(50)),
                                borderRadius: BorderRadius.circular(14)),
                            child: const Text("Cancel",
                                style: TextStyle(
                                    color: kTextSecondary,
                                    fontWeight: FontWeight.w600))))),
                const SizedBox(width: 12),
                Expanded(
                    child: GestureDetector(
                        onTap: () async {
                          final title = _noteTitleCtrl.text.trim();
                          if (title.isEmpty) return;
                          final desc = _noteDescCtrl.text.trim();
                          Navigator.pop(ctx);
                          if (isEdit) {
                            final note = globalNotes[editIndex];
                            await _fs.updateNote(note.id, title, desc);
                            setState(() => globalNotes[editIndex] = Note(
                                id: note.id, title: title, description: desc));
                          } else {
                            final id = await _fs.addNote(title, desc);
                            setState(() => globalNotes.add(
                                Note(id: id, title: title, description: desc)));
                          }
                          _noteTitleCtrl.clear();
                          _noteDescCtrl.clear();
                        },
                        child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                gradient: kButtonGradient,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                      color: kAccentGlow.withAlpha(80),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ]),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      isEdit
                                          ? Icons.save_rounded
                                          : Icons.add_rounded,
                                      color: Colors.white,
                                      size: 20),
                                  const SizedBox(width: 6),
                                  Text(isEdit ? "Save" : "Add Note",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ])))),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}

// ─── SCREEN 2: MY DECKS ───────────────────────────────────────────────────────
class MyDecksListScreen extends StatefulWidget {
  const MyDecksListScreen({super.key});
  @override
  State<MyDecksListScreen> createState() => _MyDecksListScreenState();
}

class _MyDecksListScreenState extends State<MyDecksListScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final decks = await _fs.loadDecks();
      if (mounted)
        setState(() {
          globalDecks = decks;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("My Decks"),
      bottomNav: buildBottomNav(context, 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentLight))
          : globalDecks.isEmpty
              ? const Center(
                  child: Text("No decks yet. Create some flashcards!",
                      style: TextStyle(color: kTextSecondary)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: kAccentLight,
                  backgroundColor: kCardBg,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                    itemCount: globalDecks.length,
                    itemBuilder: (_, i) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: kCardDecoration(),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                                gradient: kButtonGradient,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.folder_rounded,
                                color: Colors.white, size: 22)),
                        title: Text(globalDecks[i].name,
                            style: const TextStyle(
                                color: kTextPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                        subtitle: Text("${globalDecks[i].cards.length} cards",
                            style: const TextStyle(
                                color: kTextSecondary, fontSize: 12)),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          // Edit opens full deck editor (name + cards)
                          IconButton(
                              icon: const Icon(Icons.edit_rounded,
                                  color: kAccentLight, size: 20),
                              onPressed: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            DeckEditorScreen(deckIndex: i)));
                                setState(() {});
                              }),
                          IconButton(
                              icon: const Icon(Icons.delete_rounded,
                                  color: kError, size: 20),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final removed = globalDecks[i];
                                await _fs.deleteDeck(globalDecks[i].id);
                                setState(() {
                                  globalDecks.removeAt(i);
                                  trashedDecks.add(removed);
                                });
                                messenger.showSnackBar(SnackBar(
                                    content: const Text("Deck moved to Trash."),
                                    backgroundColor: kCardBgLight,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))));
                              }),
                        ]),
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      DeckEditorScreen(deckIndex: i)));
                          setState(() {});
                        },
                      ),
                    ),
                  )),
    );
  }
}

// ─── SCREEN 3: VIEW DECK CARDS (kept for reference, navigation now goes to DeckEditorScreen) ──
class ViewDeckCardsScreen extends StatefulWidget {
  final int deckIndex;
  const ViewDeckCardsScreen({super.key, required this.deckIndex});
  @override
  State<ViewDeckCardsScreen> createState() => _ViewDeckCardsScreenState();
}

class _ViewDeckCardsScreenState extends State<ViewDeckCardsScreen> {
  final _fs = FirestoreService();

  Color _modeColor(String mode) {
    switch (mode) {
      case "Identification":
        return const Color(0xFF00796B);
      case "Enumeration":
        return const Color(0xFF6A1B9A);
      case "True or False":
        return const Color(0xFFE65100);
      default:
        return kAccentGlow;
    }
  }

  @override
  Widget build(BuildContext context) {
    var deck = globalDecks[widget.deckIndex];
    return gradientScaffold(
      appBar: gradientAppBar(deck.name),
      bottomNav: buildBottomNav(context, 0),
      body: deck.cards.isEmpty
          ? const Center(
              child: Text("No cards in this deck.",
                  style: TextStyle(color: kTextSecondary)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              itemCount: deck.cards.length,
              itemBuilder: (_, i) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: kCardDecoration(),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  leading: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: _modeColor(deck.cards[i].mode),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(deck.cards[i].mode.split(" ").first,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700))),
                  title: Text(deck.cards[i].question,
                      style: const TextStyle(
                          color: kTextPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text(deck.cards[i].answer,
                      style:
                          const TextStyle(color: kTextSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_rounded,
                          color: kError, size: 20),
                      onPressed: () async {
                        await _fs.deleteCard(deck.id, deck.cards[i].id);
                        setState(() => deck.cards.removeAt(i));
                      }),
                ),
              ),
            ),
    );
  }
}

// ─── SCREEN 4: CREATE FLASHCARD ───────────────────────────────────────────────
class CreateFlashcardScreen extends StatefulWidget {
  const CreateFlashcardScreen({super.key});
  @override
  State<CreateFlashcardScreen> createState() => _CreateFlashcardScreenState();
}

class _CreateFlashcardScreenState extends State<CreateFlashcardScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final decks = await _fs.loadDecks();
      if (mounted)
        setState(() {
          globalDecks = decks;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newDeck() {
    final ctrl = TextEditingController();
    // Also allow linking a reviewer when creating a new deck
    String? selectedReviewerId;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setS) => AlertDialog(
                backgroundColor: kCardBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text("New Deck",
                    style: TextStyle(
                        color: kTextPrimary, fontWeight: FontWeight.w800)),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: InputDecoration(
                          hintText: "e.g. Biology Chapter 3",
                          hintStyle: const TextStyle(color: kTextSecondary),
                          filled: true,
                          fillColor: kCardBgLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: kAccentLight, width: 1.5)))),
                  if (globalReviewers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Link Reviewer (optional)",
                            style: TextStyle(
                                color: kTextSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: kCardBgLight,
                          borderRadius: BorderRadius.circular(12)),
                      child: DropdownButton<String?>(
                        value: selectedReviewerId,
                        isExpanded: true,
                        dropdownColor: kCardBg,
                        underline: const SizedBox(),
                        style:
                            const TextStyle(color: kTextPrimary, fontSize: 14),
                        hint: const Text("No reviewer linked",
                            style:
                                TextStyle(color: kTextSecondary, fontSize: 13)),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null,
                              child: Text("No reviewer",
                                  style: TextStyle(
                                      color: kTextSecondary, fontSize: 13))),
                          ...globalReviewers.map((r) =>
                              DropdownMenuItem<String?>(
                                  value: r.id,
                                  child: Text(r.title,
                                      overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setS(() => selectedReviewerId = v),
                      ),
                    ),
                  ],
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel",
                          style: TextStyle(color: kTextSecondary))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: kAccentGlow,
                          shape: const StadiumBorder()),
                      onPressed: () async {
                        final name = ctrl.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(ctx);
                        setState(() => _loading = true);
                        try {
                          final deckId = await _fs.createOrGetDeck(name);
                          // If a reviewer was selected, link it
                          if (selectedReviewerId != null) {
                            final rev = globalReviewers.firstWhere(
                                (r) => r.id == selectedReviewerId,
                                orElse: () => globalReviewers.first);
                            await _fs.saveReviewerText(deckId, rev.content);
                          }
                          final newDeck = Deck(
                              id: deckId,
                              name: name,
                              cards: [],
                              reviewerText: selectedReviewerId != null
                                  ? globalReviewers
                                      .firstWhere(
                                          (r) => r.id == selectedReviewerId,
                                          orElse: () => globalReviewers.first)
                                      .content
                                  : null);
                          final existing =
                              globalDecks.indexWhere((d) => d.id == deckId);
                          if (existing == -1) {
                            setState(() {
                              globalDecks.add(newDeck);
                              _loading = false;
                            });
                          } else {
                            setState(() => _loading = false);
                          }
                          if (mounted) {
                            final idx =
                                globalDecks.indexWhere((d) => d.id == deckId);
                            if (idx != -1) {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          DeckEditorScreen(deckIndex: idx)));
                              setState(() {});
                            }
                          }
                        } catch (e) {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                      child: const Text("Create",
                          style: TextStyle(color: Colors.white))),
                ],
              ),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("My Flashcard Sets"),
      bottomNav: buildBottomNav(context, 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentLight))
          : Stack(children: [
              globalDecks.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          const Icon(Icons.layers_outlined,
                              color: kTextSecondary, size: 56),
                          const SizedBox(height: 16),
                          const Text("No decks yet",
                              style: TextStyle(
                                  color: kTextPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          const Text("Tap below to create your first deck",
                              style: TextStyle(
                                  color: kTextSecondary, fontSize: 13)),
                        ]))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: kAccentLight,
                      backgroundColor: kCardBg,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 80, 20, 100),
                        itemCount: globalDecks.length,
                        itemBuilder: (_, i) {
                          final deck = globalDecks[i];
                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          DeckEditorScreen(deckIndex: i)));
                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: kCardDecoration(),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                                gradient: kButtonGradient,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: const Icon(
                                                Icons.layers_rounded,
                                                color: Colors.white,
                                                size: 22)),
                                        const SizedBox(width: 14),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(deck.name,
                                                  style: const TextStyle(
                                                      color: kTextPrimary,
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              Text(
                                                  "${deck.cards.length} card${deck.cards.length == 1 ? '' : 's'}",
                                                  style: const TextStyle(
                                                      color: kTextSecondary,
                                                      fontSize: 12)),
                                            ])),
                                        const Icon(Icons.edit_rounded,
                                            color: kAccentLight, size: 18),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: kCardBg,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20)),
                                                title: const Text("Delete Deck",
                                                    style: TextStyle(
                                                        color: kTextPrimary,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                                content: Text(
                                                    "Are you sure you want to delete \"${deck.name}\"? This cannot be undone.",
                                                    style: const TextStyle(
                                                        color: kTextSecondary,
                                                        height: 1.5)),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child: const Text(
                                                          "Cancel",
                                                          style: TextStyle(
                                                              color:
                                                                  kTextSecondary))),
                                                  ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                              backgroundColor:
                                                                  kError,
                                                              shape:
                                                                  const StadiumBorder()),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      child: const Text(
                                                          "Delete",
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white))),
                                                ],
                                              ),
                                            );
                                            if (confirmed == true && mounted) {
                                              setState(() => _loading = true);
                                              try {
                                                await _fs.deleteDeck(deck.id);
                                                setState(() {
                                                  globalDecks.removeAt(i);
                                                  _loading = false;
                                                });
                                              } catch (_) {
                                                if (mounted)
                                                  setState(
                                                      () => _loading = false);
                                              }
                                            }
                                          },
                                          child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                  color: kError.withAlpha(40),
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: kError,
                                                  size: 18)),
                                        ),
                                      ]),
                                      if (deck.cards.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: deck.cards
                                                .take(3)
                                                .map((c) => Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                          color: kCardBgLight,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(20),
                                                          border: Border.all(
                                                              color: kAccentLight
                                                                  .withAlpha(
                                                                      30))),
                                                      child: Text(
                                                          c.question.length > 25
                                                              ? c.question
                                                                  .substring(
                                                                      0, 25)
                                                              : c.question,
                                                          style: const TextStyle(
                                                              color:
                                                                  kTextSecondary,
                                                              fontSize: 11)),
                                                    ))
                                                .toList()),
                                      ],
                                    ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: glowButton(
                      label: "New Deck",
                      onTap: _newDeck,
                      icon: Icons.add_rounded)),
            ]),
    );
  }
}

// ─── SCREEN 4b: DECK EDITOR ───────────────────────────────────────────────────
class DeckEditorScreen extends StatefulWidget {
  final int deckIndex;
  const DeckEditorScreen({super.key, required this.deckIndex});
  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _CardEntry {
  final TextEditingController qCtrl;
  final TextEditingController aCtrl;
  String mode;
  String? existingId;
  _CardEntry(
      {String q = '',
      String a = '',
      this.mode = 'Identification',
      this.existingId})
      : qCtrl = TextEditingController(text: q),
        aCtrl = TextEditingController(text: a);
  void dispose() {
    qCtrl.dispose();
    aCtrl.dispose();
  }
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  final _fs = FirestoreService();
  final _nameCtrl = TextEditingController();
  final List<_CardEntry> _entries = [];
  bool _saving = false;
  late Deck _deck;

  static const _modes = [
    {
      "label": "Identification",
      "icon": Icons.text_fields_rounded,
      "color": Color(0xFF00796B)
    },
    {
      "label": "Enumeration",
      "icon": Icons.format_list_numbered_rounded,
      "color": Color(0xFF6A1B9A)
    },
    {
      "label": "True or False",
      "icon": Icons.toggle_on_rounded,
      "color": Color(0xFFE65100)
    },
  ];

  @override
  void initState() {
    super.initState();
    _deck = globalDecks[widget.deckIndex];
    _nameCtrl.text = _deck.name;
    for (final c in _deck.cards) {
      _entries.add(_CardEntry(
          q: c.question, a: c.answer, mode: c.mode, existingId: c.id));
    }
    if (_entries.isEmpty) _entries.add(_CardEntry());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  final ScrollController _scrollCtrl = ScrollController();

  void _addCard() {
    setState(() => _entries.add(_CardEntry()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _removeEntry(int i) => setState(() => _entries.removeAt(i));

  Future<void> _saveDeck() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Deck name cannot be empty."),
          backgroundColor: kError));
      return;
    }
    final valid = _entries
        .where((e) =>
            e.qCtrl.text.trim().isNotEmpty && e.aCtrl.text.trim().isNotEmpty)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Add at least one card with a question and answer."),
          backgroundColor: kError));
      return;
    }
    setState(() => _saving = true);
    try {
      final deckId = _deck.id;
      // Update deck name if changed
      if (newName != _deck.name) {
        await _fs.updateDeckName(deckId, newName);
        globalDecks[widget.deckIndex].name = newName;
      }
      List<Flashcard> savedCards = [];
      for (final e in _entries) {
        final q = e.qCtrl.text.trim();
        final a = e.aCtrl.text.trim();
        if (q.isEmpty || a.isEmpty) continue;
        if (e.existingId != null) {
          await _fs.updateCard(deckId, e.existingId!, q, a, e.mode);
          savedCards.add(Flashcard(
              id: e.existingId!, question: q, answer: a, mode: e.mode));
        } else {
          final cardId = await _fs.addCard(deckId, q, a, e.mode);
          savedCards
              .add(Flashcard(id: cardId, question: q, answer: a, mode: e.mode));
        }
      }
      final savedIds = savedCards.map((c) => c.id).toSet();
      for (final old in _deck.cards) {
        if (!savedIds.contains(old.id)) {
          await _fs.deleteCard(deckId, old.id);
        }
      }
      globalDecks[widget.deckIndex].cards = savedCards;
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Deck \"$newName\" saved"),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Save deck error: $e");
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _inputField(TextEditingController ctrl, String label,
      {String? hint, int maxLines = 1}) {
    return TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: kTextPrimary, fontSize: 15),
        decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
            hintStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
            filled: true,
            fillColor: kCardBgLight,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: kAccentLight, width: 1.5))));
  }

  Widget _modeChip(int entryIdx) {
    final entry = _entries[entryIdx];
    final modeData = _modes.firstWhere((m) => m["label"] == entry.mode,
        orElse: () => _modes[0]);
    final color = modeData["color"] as Color;
    final icon = modeData["icon"] as IconData;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: kCardBg,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Question Type",
                      style: TextStyle(
                          color: kTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  ..._modes.map((m) {
                    final ml = m["label"] as String;
                    final mc = m["color"] as Color;
                    final mi = m["icon"] as IconData;
                    final selected = ml == entry.mode;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _entries[entryIdx].mode = ml);
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                            color: selected ? mc.withAlpha(200) : kCardBgLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: selected
                                    ? mc
                                    : kAccentLight.withAlpha(20))),
                        child: Row(children: [
                          Icon(mi,
                              color: selected ? Colors.white : kTextSecondary,
                              size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(ml,
                                  style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : kTextPrimary,
                                      fontWeight: FontWeight.w600))),
                          if (selected)
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 18),
                        ]),
                      ),
                    );
                  }),
                ]),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: color.withAlpha(50),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(120))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(entry.mode,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded, color: color, size: 16),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("Edit Deck", actions: [
        Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
                onPressed: _saving ? null : _saveDeck,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: kAccentLight, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_rounded,
                        color: kAccentLight, size: 18),
                label: Text(_saving ? "Saving" : "Save",
                    style: const TextStyle(
                        color: kAccentLight, fontWeight: FontWeight.w700)))),
      ]),
      bottomNav: buildBottomNav(context, 0),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 80, 20, 12),
            itemCount:
                _entries.length + 2, // +1 for name field, +1 for add button
            itemBuilder: (_, i) {
              // First item: deck name editor
              if (i == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: kCardDecoration(),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("DECK NAME",
                              style: TextStyle(
                                  color: kTextSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 8),
                          TextField(
                              controller: _nameCtrl,
                              style: const TextStyle(
                                  color: kTextPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                              decoration: InputDecoration(
                                  filled: true,
                                  fillColor: kCardBgLight,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: kAccentLight, width: 1.5)))),
                        ]),
                  ),
                );
              }
              // Last item: Add Card button
              if (i == _entries.length + 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: GestureDetector(
                    onTap: _addCard,
                    child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: kAccentLight.withAlpha(80), width: 1.5),
                            borderRadius: BorderRadius.circular(16),
                            color: kAccentGlow.withAlpha(20)),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline_rounded,
                                  color: kAccentLight, size: 20),
                              SizedBox(width: 8),
                              Text("Add Card",
                                  style: TextStyle(
                                      color: kAccentLight,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ])),
                  ),
                );
              }
              // Card entries (offset by 1 due to name field)
              final entryIdx = i - 1;
              final entry = _entries[entryIdx];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: kCardDecoration(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  gradient: kButtonGradient,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text("${entryIdx + 1}",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13))),
                          const SizedBox(width: 10),
                          _modeChip(entryIdx),
                          const Spacer(),
                          if (_entries.length > 1)
                            GestureDetector(
                                onTap: () => _removeEntry(entryIdx),
                                child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: kError.withAlpha(40),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: const Icon(Icons.close_rounded,
                                        color: kError, size: 16))),
                        ]),
                        const SizedBox(height: 12),
                        _inputField(entry.qCtrl, "Question"),
                        const SizedBox(height: 10),
                        if (entry.mode == "True or False")
                          _trueFalseAnswerPicker(entry)
                        else
                          _inputField(entry.aCtrl, "Answer",
                              hint: entry.mode == "Enumeration"
                                  ? "e.g. item1, item2, item3"
                                  : null,
                              maxLines: entry.mode == "Enumeration" ? 2 : 1),
                      ]),
                ),
              );
            },
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: _saving
                ? const Center(
                    child: CircularProgressIndicator(color: kAccentLight))
                : glowButton(
                    label: "Save Deck",
                    onTap: _saveDeck,
                    icon: Icons.save_rounded)),
      ]),
    );
  }

  Widget _trueFalseAnswerPicker(_CardEntry entry) {
    return Row(
        children: ["True", "False"].map((val) {
      final selected = entry.aCtrl.text == val;
      final color = val == "True" ? kSuccess : kError;
      return Expanded(
          child: Padding(
        padding: EdgeInsets.only(
            right: val == "True" ? 6 : 0, left: val == "False" ? 6 : 0),
        child: GestureDetector(
          onTap: () => setState(() => entry.aCtrl.text = val),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: selected ? color.withAlpha(200) : kCardBgLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? color : kAccentLight.withAlpha(30),
                    width: selected ? 2 : 1)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(
                  val == "True"
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: selected ? Colors.white : kTextSecondary,
                  size: 18),
              const SizedBox(width: 6),
              Text(val,
                  style: TextStyle(
                      color: selected ? Colors.white : kTextSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
          ),
        ),
      ));
    }).toList());
  }
}

// ─── SCREEN 5: STATS ──────────────────────────────────────────────────────────
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    double quizAvg = totalQuestionsAnswered == 0
        ? 0
        : (totalCorrectAnswers / totalQuestionsAnswered) * 100;
    int totalFlashcardsReviewed = totalFlashcardsKnown + totalFlashcardsUnknown;
    double flashcardMastery = totalFlashcardsReviewed == 0
        ? 0
        : (totalFlashcardsKnown / totalFlashcardsReviewed) * 100;

    return gradientScaffold(
      appBar: gradientAppBar("Stats Overview"),
      bottomNav: buildBottomNav(context, 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
        child: Column(children: [
          // Top mini-stat cards
          Row(children: [
            _miniCard("Days\nStudied", "${daysStudied.length}",
                Icons.calendar_today_rounded, const Color(0xFF7C3AED)),
            const SizedBox(width: 12),
            _miniCard("Cards\nStudied", "$totalCardsStudied",
                Icons.style_rounded, const Color(0xFF1565C0)),
            const SizedBox(width: 12),
            _miniCard("Quizzes\nTaken", "$totalQuizzesTaken",
                Icons.quiz_rounded, const Color(0xFF00796B)),
          ]),
          const SizedBox(height: 20),
          // Quiz Performance
          Container(
              padding: const EdgeInsets.all(24),
              decoration: kCardDecoration(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Quiz Performance",
                        style: TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Average Score",
                              style: TextStyle(
                                  color: kTextSecondary, fontSize: 14)),
                          Text("${quizAvg.toInt()}%",
                              style: const TextStyle(
                                  color: kAccentLight,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900)),
                        ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                            value: quizAvg / 100,
                            minHeight: 10,
                            backgroundColor: kCardBgLight,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                kAccentLight))),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                          child: _statBox(
                              "Total Questions", "$totalQuestionsAnswered")),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statBox(
                              "Correct Answers", "$totalCorrectAnswers",
                              color: kSuccess)),
                    ]),
                  ])),
          const SizedBox(height: 20),
          // Flashcard Performance
          Container(
              padding: const EdgeInsets.all(24),
              decoration: kCardDecoration(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Flashcard Performance",
                        style: TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Mastery Rate",
                              style: TextStyle(
                                  color: kTextSecondary, fontSize: 14)),
                          Text("${flashcardMastery.toInt()}%",
                              style: const TextStyle(
                                  color: kSuccess,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900)),
                        ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                            value: flashcardMastery / 100,
                            minHeight: 10,
                            backgroundColor: kCardBgLight,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(kSuccess))),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                          child: _statBox("Sessions", "$totalFlashcardSessions",
                              color: const Color(0xFF7C3AED))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statBox(
                              "Cards Known", "$totalFlashcardsKnown",
                              color: kSuccess)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statBox(
                              "Still Learning", "$totalFlashcardsUnknown",
                              color: kError)),
                    ]),
                  ])),
        ]),
      ),
    );
  }

  Widget _miniCard(String label, String value, IconData icon, Color color) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(80), width: 1)),
      child: Column(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: kTextSecondary, fontSize: 11),
            textAlign: TextAlign.center),
      ]),
    ));
  }

  Widget _statBox(String label, String value, {Color? color}) {
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kCardBgLight, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color ?? kTextPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: kTextSecondary, fontSize: 11),
              textAlign: TextAlign.center),
        ]));
  }
}

// ─── SCREEN 6: DECK SELECT ────────────────────────────────────────────────────
class DeckSelectScreen extends StatefulWidget {
  const DeckSelectScreen({super.key});
  @override
  State<DeckSelectScreen> createState() => _DeckSelectScreenState();
}

class _DeckSelectScreenState extends State<DeckSelectScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final decks = await _fs.loadDecks();
      if (mounted)
        setState(() {
          globalDecks = decks;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("Choose a Deck"),
      bottomNav: buildBottomNav(context, 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentLight))
          : globalDecks.isEmpty
              ? const Center(
                  child: Text("No decks yet! Create flashcards first.",
                      style: TextStyle(color: kTextSecondary)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: kAccentLight,
                  backgroundColor: kCardBg,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                    itemCount: globalDecks.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  DeckStudyOptionsScreen(deckIndex: i))),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(20),
                        decoration: kCardDecoration(),
                        child: Row(children: [
                          Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  gradient: kButtonGradient,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.folder_rounded,
                                  color: Colors.white)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(globalDecks[i].name,
                                    style: const TextStyle(
                                        color: kTextPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700)),
                                Text("${globalDecks[i].cards.length} cards",
                                    style: const TextStyle(
                                        color: kTextSecondary, fontSize: 12)),
                              ])),
                          const Icon(Icons.chevron_right_rounded,
                              color: kTextSecondary),
                        ]),
                      ),
                    ),
                  )),
    );
  }
}

// ─── SCREEN 6b: DECK STUDY OPTIONS ───────────────────────────────────────────
class DeckStudyOptionsScreen extends StatefulWidget {
  final int deckIndex;
  const DeckStudyOptionsScreen({super.key, required this.deckIndex});
  @override
  State<DeckStudyOptionsScreen> createState() => _DeckStudyOptionsScreenState();
}

class _DeckStudyOptionsScreenState extends State<DeckStudyOptionsScreen> {
  void _startFlashcard(Deck deck) {
    if (deck.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No cards in this deck!")));
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FlashcardReviewScreen(
                cards: List<Flashcard>.from(deck.cards), deckName: deck.name)));
  }

  void _startMixedQuiz(Deck deck) {
    if (deck.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No cards in this deck!")));
      return;
    }
    final cards = List<Flashcard>.from(deck.cards)..shuffle();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ActualQuizScreen(cards: cards, deckName: deck.name)));
  }

  void _showLinkReviewerSheet(BuildContext context, Deck deck) async {
    final messenger = ScaffoldMessenger.of(context);
    if (globalReviewers.isEmpty) {
      try {
        globalReviewers = await FirestoreService().loadReviewers();
      } catch (_) {}
    }
    if (!mounted) return;
    if (globalReviewers.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text("No reviewers saved yet. Go to Reviewers to create one."),
          backgroundColor: kWarning,
          behavior: SnackBarBehavior.floating));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: this.context,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: kTextSecondary.withAlpha(80),
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text("Link a Reviewer",
                  style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text("Choose a reviewer to attach to this deck",
                  style: TextStyle(color: kTextSecondary, fontSize: 13)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: globalReviewers.length,
                  itemBuilder: (_, i) {
                    final r = globalReviewers[i];
                    final isLinked = deck.reviewerText == r.content;
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await FirestoreService()
                            .saveReviewerText(deck.id, r.content);
                        setState(() {
                          final idx =
                              globalDecks.indexWhere((d) => d.id == deck.id);
                          if (idx != -1)
                            globalDecks[idx].reviewerText = r.content;
                        });
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                              content:
                                  Text("\"${r.title}\" linked to this deck"),
                              backgroundColor: kSuccess,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))));
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: isLinked
                                ? const Color(0xFF00796B).withAlpha(40)
                                : kCardBgLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: isLinked
                                    ? const Color(0xFF00796B).withAlpha(100)
                                    : kAccentLight.withAlpha(30))),
                        child: Row(children: [
                          const Icon(Icons.menu_book_rounded,
                              color: Color(0xFF4DB6AC), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(r.title,
                                    style: const TextStyle(
                                        color: kTextPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                Text("${r.content.split(' ').length} words",
                                    style: const TextStyle(
                                        color: kTextSecondary, fontSize: 11)),
                              ])),
                          if (isLinked)
                            const Icon(Icons.check_circle_rounded,
                                color: kSuccess, size: 18),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = globalDecks[widget.deckIndex];
    final hasReviewer =
        deck.reviewerText != null && deck.reviewerText!.isNotEmpty;

    return gradientScaffold(
      appBar: gradientAppBar(deck.name),
      bottomNav: buildBottomNav(context, 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader("Reviewer"),
          const SizedBox(height: 10),
          if (hasReviewer) ...[
            _optionCard(
                label: "Read Reviewer",
                subtitle: "Study the attached material first",
                icon: Icons.menu_book_rounded,
                color: const Color(0xFF00796B),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReviewerReadScreen(deck: deck)))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showLinkReviewerSheet(context, deck),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                      color: kCardBgLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAccentLight.withAlpha(30))),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            color: kAccentLight, size: 16),
                        SizedBox(width: 6),
                        Text("Change Linked Reviewer",
                            style: TextStyle(
                                color: kAccentLight,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ])),
            ),
          ] else ...[
            GestureDetector(
              onTap: () => _showLinkReviewerSheet(context, deck),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFF00796B).withAlpha(20),
                    border: Border.all(
                        color: const Color(0xFF00796B).withAlpha(60)),
                    borderRadius: BorderRadius.circular(16)),
                child: const Row(children: [
                  Icon(Icons.link_rounded, color: Color(0xFF4DB6AC), size: 22),
                  SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text("Link a Reviewer",
                            style: TextStyle(
                                color: kTextPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text("Attach your saved reviewer notes to this deck",
                            style:
                                TextStyle(color: kTextSecondary, fontSize: 12)),
                      ])),
                  Icon(Icons.chevron_right_rounded, color: kTextSecondary),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _sectionHeader("Study Mode"),
          const SizedBox(height: 14),
          _optionCard(
              label: "Flashcard Mode",
              subtitle: "Swipe through cards, mark right or wrong",
              icon: Icons.style_rounded,
              color: kAccentGlow,
              onTap: () => _startFlashcard(deck)),
          const SizedBox(height: 12),
          _optionCard(
              label: "Quiz Mode",
              subtitle: "Mixed quiz  all question types shuffled",
              icon: Icons.quiz_rounded,
              color: const Color(0xFFE53935),
              onTap: () => _startMixedQuiz(deck)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(text,
      style: const TextStyle(
          color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w800));

  Widget _optionCard(
      {required String label,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(100), width: 1),
            boxShadow: [
              BoxShadow(
                  color: color.withAlpha(40),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ]),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style:
                        const TextStyle(color: kTextSecondary, fontSize: 12)),
              ])),
          const Icon(Icons.chevron_right_rounded, color: kTextSecondary),
        ]),
      ),
    );
  }
}

// ─── SCREEN 7: ACTUAL QUIZ ────────────────────────────────────────────────────
class ActualQuizScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String deckName;
  const ActualQuizScreen(
      {super.key, required this.cards, required this.deckName});
  @override
  State<ActualQuizScreen> createState() => _ActualQuizScreenState();
}

class _ActualQuizScreenState extends State<ActualQuizScreen> {
  int currentIndex = 0;
  final TextEditingController _ansCtrl = TextEditingController();
  String? selectedChoice;
  List<String> enumItems = [];
  List<TextEditingController> enumControllers = [];
  List<int> skippedIndices = []; // tracks skipped question indices
  bool _reviewingSkipped = false;
  List<int> _skippedQueue = [];

  @override
  void initState() {
    super.initState();
    _setupCard();
  }

  void _setupCard() {
    var card = widget.cards[currentIndex];
    selectedChoice = null;
    _ansCtrl.clear();
    if (card.mode == "Enumeration") _setupEnumeration(card);
  }

  void _setupEnumeration(Flashcard card) {
    enumItems = card.answer
        .split(",")
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (var c in enumControllers) {
      c.dispose();
    }
    enumControllers =
        List.generate(enumItems.length, (_) => TextEditingController());
  }

  void _skip() {
    if (!skippedIndices.contains(currentIndex)) {
      skippedIndices.add(currentIndex);
    }
    _goNext();
  }

  void _goNext() {
    if (_reviewingSkipped) {
      // Move to next skipped question
      _skippedQueue.removeAt(0);
      if (_skippedQueue.isNotEmpty) {
        setState(() => currentIndex = _skippedQueue.first);
        _setupCard();
      } else {
        _finish();
      }
      return;
    }

    if (currentIndex < widget.cards.length - 1) {
      setState(() => currentIndex++);
      _setupCard();
      // Skip over already-answered skipped ones only if reviewing
    } else {
      // Reached end of main questions
      final unanswered = skippedIndices
          .where((i) => widget.cards[i].userAnswer == null)
          .toList();
      if (unanswered.isNotEmpty) {
        _showSkippedDialog(unanswered);
      } else {
        _finish();
      }
    }
  }

  void _showSkippedDialog(List<int> unanswered) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Skipped Questions",
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
        content: Text(
            "You skipped ${unanswered.length} question(s). Would you like to go back and answer them now?",
            style: const TextStyle(color: kTextSecondary, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _finish();
              },
              child: const Text("Finish Anyway",
                  style: TextStyle(color: kTextSecondary))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kAccentGlow, shape: const StadiumBorder()),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _reviewingSkipped = true;
                  _skippedQueue = List.from(unanswered);
                  currentIndex = _skippedQueue.first;
                });
                _setupCard();
              },
              child: const Text("Answer Skipped",
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _finish() {
    totalQuizzesTaken++;
    totalQuestionsAnswered += widget.cards.length;
    final score = _calculateScore();
    totalCorrectAnswers += score;
    daysStudied.add(DateTime.now().toString().substring(0, 10));
    FirestoreService().saveStats();
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => QuizResultScreen(
                cards: widget.cards, deckName: widget.deckName)));
  }

  void _next() {
    var card = widget.cards[currentIndex];
    if (card.mode == "True or False") {
      card.userAnswer = selectedChoice;
    } else if (card.mode == "Enumeration") {
      card.userAnswer = enumControllers.map((c) => c.text.trim()).join(", ");
    } else {
      card.userAnswer = _ansCtrl.text;
    }
    // Remove from skipped if they answered it during review
    skippedIndices.remove(currentIndex);
    _goNext();
  }

  int _calculateScore() {
    int score = 0;
    for (var c in widget.cards) {
      if (c.mode == "Enumeration") {
        List<String> correct =
            c.answer.split(",").map((s) => s.trim().toLowerCase()).toList();
        List<String> user = (c.userAnswer ?? "")
            .split(",")
            .map((s) => s.trim().toLowerCase())
            .toList();
        if (correct.length == user.length &&
            correct.every((item) => user.contains(item))) score++;
      } else {
        if (c.userAnswer?.trim().toLowerCase() == c.answer.trim().toLowerCase())
          score++;
      }
    }
    return score;
  }

  bool get _canProceed {
    var card = widget.cards[currentIndex];
    if (card.mode == "True or False") return selectedChoice != null;
    if (card.mode == "Enumeration")
      return enumControllers.any((c) => c.text.isNotEmpty);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    var card = widget.cards[currentIndex];
    Color modeColor = card.mode == "Identification"
        ? const Color(0xFF00796B)
        : card.mode == "Enumeration"
            ? const Color(0xFF6A1B9A)
            : card.mode == "True or False"
                ? const Color(0xFFE65100)
                : kAccentGlow;

    return gradientScaffold(
      body: SafeArea(
          child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.close_rounded,
                        color: kTextPrimary, size: 20))),
            const SizedBox(width: 12),
            Expanded(
                child: Text(widget.deckName,
                    style:
                        const TextStyle(color: kTextSecondary, fontSize: 12))),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: kCardDecoration(),
                child: Column(children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: modeColor.withAlpha(60),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(card.mode,
                          style: TextStyle(
                              color: modeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600))),
                  const SizedBox(height: 16),
                  Text(card.question,
                      style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center),
                ]))),
        const SizedBox(height: 20),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAnswerArea(card))),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _reviewingSkipped
                          ? "Reviewing skipped (${_skippedQueue.length} left)"
                          : "Question ${currentIndex + 1} of ${widget.cards.length}",
                      style:
                          const TextStyle(color: kTextSecondary, fontSize: 12)),
                  if (skippedIndices.isNotEmpty && !_reviewingSkipped)
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: kWarning.withAlpha(40),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kWarning.withAlpha(80))),
                        child: Text("${skippedIndices.length} skipped",
                            style: const TextStyle(
                                color: kWarning,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))),
                ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(children: [
              Row(children: [
                if (currentIndex > 0 && !_reviewingSkipped)
                  Expanded(
                      flex: 1,
                      child: GestureDetector(
                          onTap: () {
                            setState(() => currentIndex--);
                            _setupCard();
                          },
                          child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: kAccentLight.withAlpha(60)),
                                  borderRadius: BorderRadius.circular(16)),
                              child: const Text("Back",
                                  style: TextStyle(
                                      color: kTextSecondary,
                                      fontWeight: FontWeight.w600))))),
                if (currentIndex > 0 && !_reviewingSkipped)
                  const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: GestureDetector(
                        onTap: _canProceed ? _next : null,
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                gradient: _canProceed ? kButtonGradient : null,
                                color: _canProceed ? null : kCardBgLight,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: _canProceed
                                    ? [
                                        BoxShadow(
                                            color: kAccentGlow.withAlpha(80),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4))
                                      ]
                                    : []),
                            child: Text(
                                _reviewingSkipped
                                    ? (_skippedQueue.length > 1
                                        ? "Next Skipped"
                                        : "Finish")
                                    : (currentIndex < widget.cards.length - 1
                                        ? "Next"
                                        : "Finish"),
                                style: TextStyle(
                                    color: _canProceed
                                        ? Colors.white
                                        : kTextSecondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16))))),
              ]),
              if (!_reviewingSkipped) ...[
                const SizedBox(height: 10),
                GestureDetector(
                    onTap: _skip,
                    child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: kWarning.withAlpha(80), width: 1.5),
                            borderRadius: BorderRadius.circular(14),
                            color: kWarning.withAlpha(15)),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.skip_next_rounded,
                                  color: kWarning, size: 18),
                              SizedBox(width: 6),
                              Text("Skip",
                                  style: TextStyle(
                                      color: kWarning,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ]))),
              ],
            ])),
      ])),
    );
  }

  Widget _buildAnswerArea(Flashcard card) {
    if (card.mode == "True or False") {
      return Row(
          children: ["True", "False"].map((val) {
        final isSelected = selectedChoice == val;
        final color = val == "True" ? kSuccess : kError;
        return Expanded(
            child: Padding(
          padding: EdgeInsets.only(
              right: val == "True" ? 8 : 0, left: val == "False" ? 8 : 0),
          child: GestureDetector(
            onTap: () => setState(() => selectedChoice = val),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: isSelected ? color.withAlpha(200) : kCardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: isSelected ? color : kAccentLight.withAlpha(30),
                      width: isSelected ? 2 : 1),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withAlpha(80), blurRadius: 14)]
                      : []),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        val == "True"
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: isSelected ? Colors.white : kTextSecondary,
                        size: 32),
                    const SizedBox(height: 6),
                    Text(val,
                        style: TextStyle(
                            color: isSelected ? Colors.white : kTextSecondary,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
                  ]),
            ),
          ),
        ));
      }).toList());
    }

    if (card.mode == "Enumeration") {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Fill in each blank:",
            style: TextStyle(color: kTextSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        ...List.generate(
            enumItems.length,
            (i) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          gradient: kButtonGradient,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text("${i + 1}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: TextField(
                          controller: enumControllers[i],
                          style: const TextStyle(color: kTextPrimary),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                              hintText: "Item ${i + 1}",
                              hintStyle: const TextStyle(
                                  color: kTextSecondary, fontSize: 13),
                              filled: true,
                              fillColor: kCardBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: kAccentLight, width: 1.5))))),
                ]))),
      ]);
    }

    return TextField(
        controller: _ansCtrl,
        style: const TextStyle(color: kTextPrimary, fontSize: 16),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            hintText: "Type your answer",
            hintStyle: const TextStyle(color: kTextSecondary),
            filled: true,
            fillColor: kCardBg,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: kAccentLight, width: 1.5))));
  }
}

// ─── SCREEN 8: FLASHCARD REVIEW ───────────────────────────────────────────────
class FlashcardReviewScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String deckName;
  const FlashcardReviewScreen(
      {super.key, required this.cards, required this.deckName});
  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen>
    with TickerProviderStateMixin {
  late List<Flashcard> _deck;
  List<Flashcard> _skipped = [];
  final List<Flashcard> _known = [];
  final List<Flashcard> _unknown = [];

  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isShuffled = false;

  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  late AnimationController _swipeCtrl;
  late Animation<Offset> _swipeAnim;
  Offset _dragOffset = Offset.zero;
  bool _isSwiping = false;

  @override
  void initState() {
    super.initState();
    _deck = List<Flashcard>.from(widget.cards);
    _flipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _flipAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));
    _swipeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _swipeAnim =
        Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_swipeCtrl);
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_isSwiping) return;
    _isFlipped ? _flipCtrl.reverse() : _flipCtrl.forward();
    setState(() => _isFlipped = !_isFlipped);
  }

  void _resetFlip() {
    _flipCtrl.reset();
    setState(() {
      _isFlipped = false;
      _dragOffset = Offset.zero;
      _isSwiping = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += Offset(d.delta.dx, d.delta.dy * 0.3);
      _isSwiping = true;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final dx = _dragOffset.dx;
    if (dx > 80) {
      _animateSwipe(const Offset(2, 0), onDone: () => _markCard('known'));
    } else if (dx < -80) {
      _animateSwipe(const Offset(-2, 0), onDone: () => _markCard('unknown'));
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _isSwiping = false;
      });
    }
  }

  void _animateSwipe(Offset target, {required VoidCallback onDone}) {
    final size = MediaQuery.of(context).size;
    _swipeAnim = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(target.dx * size.width, target.dy * 80),
    ).animate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOut));
    _swipeCtrl.forward(from: 0).then((_) {
      onDone();
      _swipeCtrl.reset();
    });
  }

  void _markCard(String result) {
    if (_currentIndex >= _deck.length) return;
    final card = _deck[_currentIndex];
    if (result == 'known') _known.add(card);
    if (result == 'unknown') _unknown.add(card);
    if (result == 'skip') _skipped.add(card);
    _advance();
  }

  void _advance() {
    if (_currentIndex + 1 >= _deck.length) {
      if (_skipped.isNotEmpty) {
        _showSkippedDialog();
      } else {
        _showResults();
      }
    } else {
      setState(() => _currentIndex++);
      _resetFlip();
    }
  }

  void _showSkippedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Skipped Cards",
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
        content: Text(
            "You skipped ${_skipped.length} card(s). Would you like to review them now?",
            style: const TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showResults();
              },
              child: const Text("Skip and Finish",
                  style: TextStyle(color: kTextSecondary))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kAccentGlow, shape: const StadiumBorder()),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _deck = List<Flashcard>.from(_skipped);
                  _skipped = [];
                  _currentIndex = 0;
                });
                _resetFlip();
              },
              child: const Text("Review Skipped",
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _showResults() {
    totalFlashcardSessions++;
    totalFlashcardsKnown += _known.length;
    totalFlashcardsUnknown += _unknown.length;
    totalCardsStudied += _known.length + _unknown.length + _skipped.length;
    daysStudied.add(DateTime.now().toString().substring(0, 10));
    FirestoreService().saveStats();
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => FlashcardResultScreen(
                known: _known,
                unknown: _unknown,
                skipped: _skipped,
                deckName: widget.deckName)));
  }

  void _shuffle() {
    setState(() {
      _deck.shuffle();
      _currentIndex = 0;
      _isShuffled = !_isShuffled;
    });
    _resetFlip();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _isShuffled ? "Cards shuffled" : "Cards reset to original order"),
        backgroundColor: kAccentGlow,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  @override
  Widget build(BuildContext context) {
    if (_deck.isEmpty) {
      return gradientScaffold(
          appBar: gradientAppBar("Flashcard Review"),
          body: const Center(
              child: Text("No cards to review!",
                  style: TextStyle(color: kTextSecondary))));
    }

    final card = _deck[_currentIndex];
    final swipeDx = _dragOffset.dx;
    final isKnownHint = swipeDx > 40;
    final isUnknownHint = swipeDx < -40;

    return gradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: Text(widget.deckName,
            style: const TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        actions: [
          IconButton(
              tooltip: "Shuffle",
              onPressed: _shuffle,
              icon: Icon(Icons.shuffle_rounded,
                  color: _isShuffled ? kAccentLight : kTextSecondary,
                  size: 22)),
          const SizedBox(width: 8),
        ],
      ),
      bottomNav: buildBottomNav(context, 0),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 12),
        child: Column(children: [
          // Swipe hint indicators (no progress bar, no counter)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            AnimatedOpacity(
                opacity: isUnknownHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: kError.withAlpha(40),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kError.withAlpha(100))),
                    child: const Row(children: [
                      Icon(Icons.close_rounded, color: kError, size: 16),
                      SizedBox(width: 4),
                      Text("Wrong",
                          style: TextStyle(
                              color: kError,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ]))),
            AnimatedOpacity(
                opacity: isKnownHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: kSuccess.withAlpha(40),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kSuccess.withAlpha(100))),
                    child: const Row(children: [
                      Text("Right",
                          style: TextStyle(
                              color: kSuccess,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      SizedBox(width: 4),
                      Icon(Icons.check_rounded, color: kSuccess, size: 16),
                    ]))),
          ]),
          const SizedBox(height: 8),
          // Flashcard
          Expanded(
            child: GestureDetector(
              onTap: _flip,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: AnimatedBuilder(
                animation: Listenable.merge([_flipAnim, _swipeCtrl]),
                builder: (_, __) {
                  final swipeOffset = _isSwiping && _swipeCtrl.isAnimating
                      ? _swipeAnim.value
                      : _dragOffset;
                  final tilt = swipeOffset.dx / 400;
                  final angle = _flipAnim.value * pi;
                  final isFront = angle < pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setTranslationRaw(swipeOffset.dx, swipeOffset.dy, 0)
                      ..rotateZ(tilt)
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: isFront
                        ? _buildFace(
                            label: "QUESTION",
                            content: card.question,
                            hint: "Tap to reveal answer",
                            flipped: false,
                            tintColor: swipeOffset.dx > 40
                                ? kSuccess
                                : swipeOffset.dx < -40
                                    ? kError
                                    : null)
                        : Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(pi),
                            child: _buildFace(
                                label: "ANSWER",
                                content: card.answer,
                                hint: "Tap to flip back",
                                flipped: true,
                                tintColor: swipeOffset.dx > 40
                                    ? kSuccess
                                    : swipeOffset.dx < -40
                                        ? kError
                                        : null)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons: X | skip | check — icon only, labels below
          Row(children: [
            // Wrong (X)
            Expanded(
                child: GestureDetector(
              onTap: () => _markCard('unknown'),
              child: Column(children: [
                Container(
                    height: 60,
                    decoration: BoxDecoration(
                        color: kError.withAlpha(40),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kError.withAlpha(100)),
                        boxShadow: [
                          BoxShadow(
                              color: kError.withAlpha(40),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ]),
                    child: const Center(
                        child: Icon(Icons.close_rounded,
                            color: kError, size: 30))),
                const SizedBox(height: 6),
                const Text("Wrong",
                    style: TextStyle(
                        color: kError,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            )),
            const SizedBox(width: 8),
            // Skip
            Column(children: [
              GestureDetector(
                  onTap: () => _markCard('skip'),
                  child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                          color: kWarning.withAlpha(30),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kWarning.withAlpha(100))),
                      child: const Center(
                          child: Icon(Icons.skip_next_rounded,
                              color: kWarning, size: 28)))),
              const SizedBox(height: 6),
              const Text("Skip",
                  style: TextStyle(
                      color: kWarning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(width: 8),
            // Right (check)
            Expanded(
                child: GestureDetector(
              onTap: () => _markCard('known'),
              child: Column(children: [
                Container(
                    height: 60,
                    decoration: BoxDecoration(
                        color: kSuccess.withAlpha(40),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kSuccess.withAlpha(100)),
                        boxShadow: [
                          BoxShadow(
                              color: kSuccess.withAlpha(40),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ]),
                    child: const Center(
                        child: Icon(Icons.check_rounded,
                            color: kSuccess, size: 30))),
                const SizedBox(height: 6),
                const Text("Right",
                    style: TextStyle(
                        color: kSuccess,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            )),
          ]),
          const SizedBox(height: 8),
          const Text("",
              style: TextStyle(color: kTextSecondary, fontSize: 11),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildFace(
      {required String label,
      required String content,
      required String hint,
      required bool flipped,
      Color? tintColor}) {
    final baseColors = flipped
        ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
        : [kCardBg, kCardBgLight];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: baseColors),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: tintColor?.withAlpha(160) ??
                  (flipped
                      ? kSuccess.withAlpha(80)
                      : kAccentLight.withAlpha(40)),
              width: tintColor != null ? 2 : 1),
          boxShadow: [
            BoxShadow(
                color: (tintColor ?? (flipped ? kSuccess : kAccentGlow))
                    .withAlpha(60),
                blurRadius: 25,
                spreadRadius: 2)
          ]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
                color: (tintColor ?? (flipped ? kSuccess : kAccentGlow))
                    .withAlpha(60),
                borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: tintColor ?? (flipped ? kSuccess : kAccentLight),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2))),
        const SizedBox(height: 24),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(content,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary),
                textAlign: TextAlign.center)),
        const SizedBox(height: 24),
        Text(hint, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
      ]),
    );
  }
}

// ─── SCREEN 8b: FLASHCARD RESULT ──────────────────────────────────────────────
class FlashcardResultScreen extends StatelessWidget {
  final List<Flashcard> known;
  final List<Flashcard> unknown;
  final List<Flashcard> skipped;
  final String deckName;
  const FlashcardResultScreen(
      {super.key,
      required this.known,
      required this.unknown,
      required this.skipped,
      required this.deckName});

  @override
  Widget build(BuildContext context) {
    final total = known.length + unknown.length + skipped.length;
    final pct = total == 0 ? 0 : (known.length / total * 100).toInt();
    final scoreColor = pct >= 80
        ? kSuccess
        : pct >= 50
            ? kWarning
            : kError;

    return gradientScaffold(
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Score card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  scoreColor.withAlpha(60),
                  scoreColor.withAlpha(20)
                ]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: scoreColor.withAlpha(100))),
            child: Column(children: [
              Text("$pct%",
                  style: TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.w900,
                      color: scoreColor)),
              Text("$total cards reviewed",
                  style: const TextStyle(color: kTextSecondary, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                  pct >= 80
                      ? "Excellent!"
                      : pct >= 50
                          ? "Good effort!"
                          : "Keep studying!",
                  style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            _chip("Right", known.length, kSuccess, Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _chip("Wrong", unknown.length, kError, Icons.cancel_rounded),
            const SizedBox(width: 10),
            _chip("Skipped", skipped.length, kWarning, Icons.skip_next_rounded),
          ]),
          const SizedBox(height: 24),
          if (known.isNotEmpty) ...[
            _sectionLabel("Right (${known.length})", kSuccess),
            const SizedBox(height: 8),
            ...known.map((c) => _cardRow(c, kSuccess)),
            const SizedBox(height: 16),
          ],
          if (unknown.isNotEmpty) ...[
            _sectionLabel("Wrong (${unknown.length})", kError),
            const SizedBox(height: 8),
            ...unknown.map((c) => _cardRow(c, kError)),
            const SizedBox(height: 16),
          ],
          if (skipped.isNotEmpty) ...[
            _sectionLabel("Skipped (${skipped.length})", kWarning),
            const SizedBox(height: 8),
            ...skipped.map((c) => _cardRow(c, kWarning)),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          // Retry all cards
          glowButton(
              label: "Retry",
              onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => FlashcardReviewScreen(
                          cards: List<Flashcard>.from(
                              [...known, ...unknown, ...skipped])
                            ..shuffle(),
                          deckName: deckName))),
              icon: Icons.refresh_rounded,
              color: kAccentGlow,
              height: 52),
          const SizedBox(height: 12),
          // Retry wrong only
          if (unknown.isNotEmpty) ...[
            glowButton(
                label: "Retry Wrong Cards",
                onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => FlashcardReviewScreen(
                            cards: List<Flashcard>.from(unknown),
                            deckName: deckName))),
                icon: Icons.close_rounded,
                color: kError,
                height: 52),
            const SizedBox(height: 12),
          ],
          glowButton(
              label: "Back to Home",
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: Icons.home_rounded,
              color: const Color(0xFF1565C0),
              height: 52),
          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Widget _chip(String label, int count, Color color, IconData icon) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(80))),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text("$count",
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label,
            style: const TextStyle(color: kTextSecondary, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    ));
  }

  Widget _sectionLabel(String text, Color color) => Text(text,
      style:
          TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800));

  Widget _cardRow(Flashcard c, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.question,
            style: const TextStyle(
                color: kTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(c.answer,
            style: const TextStyle(color: kTextSecondary, fontSize: 12)),
      ]),
    );
  }
}

// ─── SCREEN 9: TRASH ─────────────────────────────────────────────────────────
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _fs = FirestoreService();
  bool _restoring = false;

  Future<void> _restore(int i) async {
    setState(() => _restoring = true);
    try {
      final deck = trashedDecks[i];
      final newId = await _fs.restoreDeck(deck);
      final cardSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('decks')
          .doc(newId)
          .collection('cards')
          .get();
      final restoredCards =
          cardSnap.docs.map((c) => Flashcard.fromMap(c.data(), c.id)).toList();
      final restoredDeck = Deck(
          id: newId,
          name: deck.name,
          cards: restoredCards,
          reviewerText: deck.reviewerText);
      setState(() {
        trashedDecks.removeAt(i);
        globalDecks.add(restoredDeck);
        _restoring = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Deck restored to My Decks"),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))));
      }
    } catch (e) {
      debugPrint("Restore error: $e");
      setState(() => _restoring = false);
    }
  }

  void _deletePermanently(int i) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: kCardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("Delete Permanently?",
                  style: TextStyle(color: kTextPrimary)),
              content: Text(
                  "\"${trashedDecks[i].name}\" will be deleted forever.",
                  style: const TextStyle(color: kTextSecondary)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel",
                        style: TextStyle(color: kTextSecondary))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kError, shape: const StadiumBorder()),
                    onPressed: () {
                      setState(() => trashedDecks.removeAt(i));
                      Navigator.pop(context);
                    },
                    child: const Text("Delete Forever",
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  void _emptyTrash() {
    if (trashedDecks.isEmpty) return;
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: kCardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("Empty Trash?",
                  style: TextStyle(color: kTextPrimary)),
              content: const Text(
                  "All decks in the trash will be permanently deleted.",
                  style: TextStyle(color: kTextSecondary)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel",
                        style: TextStyle(color: kTextSecondary))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kError, shape: const StadiumBorder()),
                    onPressed: () {
                      setState(() => trashedDecks.clear());
                      Navigator.pop(context);
                    },
                    child: const Text("Empty Trash",
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: kTextPrimary),
          title: const Text("Trash",
              style: TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          actions: [
            if (trashedDecks.isNotEmpty)
              TextButton.icon(
                  onPressed: _emptyTrash,
                  icon: const Icon(Icons.delete_forever_rounded,
                      color: kError, size: 18),
                  label: const Text("Empty",
                      style: TextStyle(
                          color: kError, fontWeight: FontWeight.w700))),
          ]),
      bottomNav: buildBottomNav(context, 2),
      body: _restoring
          ? const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  CircularProgressIndicator(color: kAccentLight),
                  SizedBox(height: 14),
                  Text("Restoring deck",
                      style: TextStyle(color: kTextSecondary)),
                ]))
          : trashedDecks.isEmpty
              ? const Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.delete_rounded,
                          size: 48, color: kTextSecondary),
                      SizedBox(height: 20),
                      Text("Trash is empty",
                          style: TextStyle(
                              color: kTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                  itemCount: trashedDecks.length,
                  itemBuilder: (_, i) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: kError.withAlpha(50), width: 1)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      leading: const Icon(Icons.folder_rounded,
                          color: kError, size: 22),
                      title: Text(trashedDecks[i].name,
                          style: const TextStyle(
                              color: kTextPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      subtitle: Text("${trashedDecks[i].cards.length} cards",
                          style: const TextStyle(
                              color: kTextSecondary, fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                            onTap: () => _restore(i),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: kSuccess.withAlpha(40),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: kSuccess.withAlpha(80))),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.restore_rounded,
                                          color: kSuccess, size: 16),
                                      SizedBox(width: 4),
                                      Text("Restore",
                                          style: TextStyle(
                                              color: kSuccess,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    ]))),
                        const SizedBox(width: 8),
                        GestureDetector(
                            onTap: () => _deletePermanently(i),
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: kError.withAlpha(40),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: kError.withAlpha(80))),
                                child: const Icon(Icons.delete_forever_rounded,
                                    color: kError, size: 18))),
                      ]),
                    ),
                  ),
                ),
    );
  }
}

// ─── SCREEN 10: QUIZ RESULT ───────────────────────────────────────────────────
class QuizResultScreen extends StatelessWidget {
  final List<Flashcard> cards;
  final String deckName;
  const QuizResultScreen(
      {super.key, required this.cards, required this.deckName});

  bool _isCorrect(Flashcard c) {
    if (c.mode == "Enumeration") {
      List<String> correct =
          c.answer.split(",").map((s) => s.trim().toLowerCase()).toList();
      List<String> user = (c.userAnswer ?? "")
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .toList();
      return correct.length == user.length &&
          correct.every((item) => user.contains(item));
    }
    return c.userAnswer?.trim().toLowerCase() == c.answer.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    int score = cards.where(_isCorrect).length;
    double pct = score / cards.length * 100;
    Color scoreColor = pct >= 80
        ? kSuccess
        : pct >= 50
            ? kWarning
            : kError;

    return gradientScaffold(
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    scoreColor.withAlpha(60),
                    scoreColor.withAlpha(20)
                  ]),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: scoreColor.withAlpha(100))),
              child: Column(children: [
                Text("${pct.toInt()}%",
                    style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: scoreColor)),
                Text("$score out of ${cards.length} correct",
                    style:
                        const TextStyle(color: kTextSecondary, fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                    pct >= 80
                        ? "Excellent!"
                        : pct >= 50
                            ? "Good effort!"
                            : "Keep studying!",
                    style: TextStyle(
                        color: scoreColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ])),
          const SizedBox(height: 24),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text("Review Answers",
                  style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800))),
          const SizedBox(height: 12),
          ...cards.map((c) {
            bool correct = _isCorrect(c);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: kCardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: correct
                          ? kSuccess.withAlpha(100)
                          : kError.withAlpha(100))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: kCardBgLight,
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(c.mode,
                              style: const TextStyle(
                                  color: kTextSecondary, fontSize: 11))),
                      const Spacer(),
                      Icon(
                          correct
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: correct ? kSuccess : kError,
                          size: 20),
                    ]),
                    const SizedBox(height: 8),
                    Text(c.question,
                        style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 6),
                    Text("Your answer: ${c.userAnswer ?? 'No answer'}",
                        style: TextStyle(
                            color: correct ? kSuccess : kError, fontSize: 13)),
                    if (!correct) ...[
                      const SizedBox(height: 2),
                      Text("Correct: ${c.answer}",
                          style: const TextStyle(
                              color: kSuccess,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ]),
            );
          }),
          const SizedBox(height: 24),
          // Retry quiz
          glowButton(
              label: "Retry Quiz",
              onTap: () {
                final retryCards = List<Flashcard>.from(cards)
                  ..forEach((c) => c.userAnswer = null)
                  ..shuffle();
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ActualQuizScreen(
                            cards: retryCards, deckName: deckName)));
              },
              icon: Icons.refresh_rounded,
              color: kAccentGlow,
              height: 52),
          const SizedBox(height: 12),
          glowButton(
              label: "Back to Home",
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: Icons.home_rounded,
              height: 52),
          const SizedBox(height: 20),
        ]),
      )),
    );
  }
}

// ─── SCREEN 11: REVIEWER LIST ─────────────────────────────────────────────────
class ReviewerListScreen extends StatefulWidget {
  const ReviewerListScreen({super.key});
  @override
  State<ReviewerListScreen> createState() => _ReviewerListScreenState();
}

class _ReviewerListScreenState extends State<ReviewerListScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final revs = await _fs.loadReviewers();
      if (mounted)
        setState(() {
          globalReviewers = revs;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Reviewer r) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: kCardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("Delete Reviewer?",
                  style: TextStyle(color: kTextPrimary)),
              content: Text("\"${r.title}\" will be permanently deleted.",
                  style: const TextStyle(color: kTextSecondary)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel",
                        style: TextStyle(color: kTextSecondary))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kError, shape: const StadiumBorder()),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Delete",
                        style: TextStyle(color: Colors.white))),
              ],
            ));
    if (confirm != true) return;
    await _fs.deleteReviewer(r.id);
    setState(() => globalReviewers.removeWhere((x) => x.id == r.id));
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "Just now";
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar("My Reviewers"),
      bottomNav: buildBottomNav(context, 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccentLight))
          : Stack(children: [
              globalReviewers.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                  color: kCardBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: kAccentLight.withAlpha(40))),
                              child: const Icon(Icons.menu_book_rounded,
                                  color: kAccentLight, size: 48)),
                          const SizedBox(height: 16),
                          const Text("No reviewers yet",
                              style: TextStyle(
                                  color: kTextPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          const Text("Tap below to add your first reviewer",
                              style: TextStyle(
                                  color: kTextSecondary, fontSize: 13)),
                        ]))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: kAccentLight,
                      backgroundColor: kCardBg,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 80, 20, 100),
                        itemCount: globalReviewers.length,
                        itemBuilder: (_, i) {
                          final r = globalReviewers[i];
                          final colors = [
                            const Color(0xFF7C3AED),
                            const Color(0xFF1565C0),
                            const Color(0xFF00796B),
                            const Color(0xFFE65100),
                            const Color(0xFFAD1457),
                          ];
                          final cardColor = colors[i % colors.length];
                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          ViewReviewerScreen(reviewer: r)));
                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [kCardBg, kCardBgLight]),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: cardColor.withAlpha(60), width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                        color: cardColor.withAlpha(30),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4))
                                  ]),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: cardColor,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                    top: Radius.circular(20)))),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          18, 14, 12, 14),
                                      child: Row(children: [
                                        Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                                color: cardColor.withAlpha(40),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: cardColor
                                                        .withAlpha(80))),
                                            child: Icon(Icons.article_rounded,
                                                color: cardColor, size: 22)),
                                        const SizedBox(width: 14),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(r.title,
                                                  style: const TextStyle(
                                                      color: kTextPrimary,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              const SizedBox(height: 4),
                                              Row(children: [
                                                Icon(Icons.schedule_rounded,
                                                    color: kTextSecondary,
                                                    size: 12),
                                                const SizedBox(width: 4),
                                                Text(_timeAgo(r.createdAt),
                                                    style: const TextStyle(
                                                        color: kTextSecondary,
                                                        fontSize: 11)),
                                                if (r.linkedDeckId != null) ...[
                                                  const SizedBox(width: 10),
                                                  const Icon(Icons.link_rounded,
                                                      color: kAccentLight,
                                                      size: 12),
                                                  const SizedBox(width: 4),
                                                  Text("Linked",
                                                      style: const TextStyle(
                                                          color: kAccentLight,
                                                          fontSize: 11)),
                                                ],
                                              ]),
                                            ])),
                                        PopupMenuButton<String>(
                                          color: kCardBg,
                                          icon: const Icon(
                                              Icons.more_vert_rounded,
                                              color: kTextSecondary),
                                          onSelected: (v) async {
                                            if (v == 'edit') {
                                              await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          AddReviewerScreen(
                                                              existing: r)));
                                              _refresh();
                                            } else if (v == 'delete') {
                                              await _delete(r);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                                value: 'edit',
                                                child: Row(children: [
                                                  Icon(Icons.edit_rounded,
                                                      color: kAccentLight,
                                                      size: 16),
                                                  SizedBox(width: 10),
                                                  Text("Edit",
                                                      style: TextStyle(
                                                          color: kTextPrimary)),
                                                ])),
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Row(children: [
                                                  Icon(Icons.delete_rounded,
                                                      color: kError, size: 16),
                                                  SizedBox(width: 10),
                                                  Text("Delete",
                                                      style: TextStyle(
                                                          color: kError)),
                                                ])),
                                          ],
                                        ),
                                      ]),
                                    ),
                                    if (r.content.isNotEmpty)
                                      Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              18, 0, 18, 14),
                                          child: Text(
                                              r.content.length > 100
                                                  ? r.content.substring(0, 100)
                                                  : r.content,
                                              style: const TextStyle(
                                                  color: kTextSecondary,
                                                  fontSize: 13,
                                                  height: 1.4),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis)),
                                  ]),
                            ),
                          );
                        },
                      ),
                    ),
              Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: glowButton(
                      label: "Add Reviewer",
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AddReviewerScreen()));
                        _refresh();
                      },
                      icon: Icons.add_rounded,
                      color: const Color(0xFF00796B))),
            ]),
    );
  }
}

// ─── SCREEN 11b: ADD / EDIT REVIEWER ─────────────────────────────────────────
class AddReviewerScreen extends StatefulWidget {
  final Reviewer? existing;
  const AddReviewerScreen({super.key, this.existing});
  @override
  State<AddReviewerScreen> createState() => _AddReviewerScreenState();
}

class _AddReviewerScreenState extends State<AddReviewerScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _fs = FirestoreService();
  bool _saving = false;
  String? _selectedDeckId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _titleCtrl.text = widget.existing!.title;
      _contentCtrl.text = widget.existing!.content;
      _selectedDeckId = widget.existing!.linkedDeckId;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please fill in the title and content."),
          backgroundColor: kError));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _fs.updateReviewer(widget.existing!.id, title, content,
            linkedDeckId: _selectedDeckId);
        final idx =
            globalReviewers.indexWhere((r) => r.id == widget.existing!.id);
        if (idx != -1) {
          globalReviewers[idx] = Reviewer(
              id: widget.existing!.id,
              title: title,
              content: content,
              linkedDeckId: _selectedDeckId,
              createdAt: widget.existing!.createdAt);
        }
        // Also update deck's reviewerText if linked
        if (_selectedDeckId != null) {
          await _fs.saveReviewerText(_selectedDeckId!, content);
          final dIdx = globalDecks.indexWhere((d) => d.id == _selectedDeckId);
          if (dIdx != -1) globalDecks[dIdx].reviewerText = content;
        }
      } else {
        final id = await _fs.addReviewer(title, content,
            linkedDeckId: _selectedDeckId);
        globalReviewers.insert(
            0,
            Reviewer(
                id: id,
                title: title,
                content: content,
                linkedDeckId: _selectedDeckId,
                createdAt: DateTime.now()));
        // Link content to the selected deck
        if (_selectedDeckId != null) {
          await _fs.saveReviewerText(_selectedDeckId!, content);
          final dIdx = globalDecks.indexWhere((d) => d.id == _selectedDeckId);
          if (dIdx != -1) globalDecks[dIdx].reviewerText = content;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEdit ? "Reviewer updated" : "Reviewer saved"),
            backgroundColor: kSuccess,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Save reviewer error: $e");
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error saving reviewer: $e"),
            backgroundColor: kError,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: gradientAppBar(_isEdit ? "Edit Reviewer" : "New Reviewer"),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFF00796B).withAlpha(30),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFF00796B).withAlpha(80))),
                child: const Row(children: [
                  Icon(Icons.menu_book_rounded,
                      color: Color(0xFF4DB6AC), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          "Add your study notes or reviewer material. You can read it before taking a quiz.",
                          style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 13,
                              height: 1.4))),
                ]),
              ),
              const SizedBox(height: 22),
              const Text("Title",
                  style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                  decoration: BoxDecoration(
                      color: kCardBgLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kAccentLight.withAlpha(30))),
                  child: TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                          hintText: "e.g. Chapter 5 Photosynthesis",
                          hintStyle: TextStyle(
                              color: kTextSecondary,
                              fontWeight: FontWeight.w400),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          prefixIcon: Icon(Icons.title_rounded,
                              color: kAccentLight, size: 20)))),
              const SizedBox(height: 20),
              // Link to deck (optional)
              const Text("Link to Flashcard Deck (optional)",
                  style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: kCardBgLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kAccentLight.withAlpha(30))),
                child: DropdownButton<String?>(
                  value: _selectedDeckId,
                  isExpanded: true,
                  dropdownColor: kCardBg,
                  underline: const SizedBox(),
                  style: const TextStyle(color: kTextPrimary, fontSize: 14),
                  hint: const Text("No deck linked",
                      style: TextStyle(color: kTextSecondary, fontSize: 13)),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child: Text("No deck linked",
                            style: TextStyle(
                                color: kTextSecondary, fontSize: 13))),
                    ...globalDecks.map((d) => DropdownMenuItem<String?>(
                        value: d.id,
                        child: Text(d.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _selectedDeckId = v),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Content",
                  style: TextStyle(
                      color: kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Container(
                  decoration: BoxDecoration(
                      color: kCardBgLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kAccentLight.withAlpha(30))),
                  child: TextField(
                      controller: _contentCtrl,
                      maxLines: 16,
                      style: const TextStyle(
                          color: kTextPrimary, fontSize: 14, height: 1.7),
                      decoration: const InputDecoration(
                          hintText: "Type or paste your reviewer notes here",
                          hintStyle: TextStyle(
                              color: kTextSecondary, fontSize: 13, height: 1.6),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16)))),
            ]),
          ),
        ),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: _saving
                ? const Center(
                    child: CircularProgressIndicator(color: kAccentLight))
                : glowButton(
                    label: _isEdit ? "Update Reviewer" : "Save Reviewer",
                    onTap: _save,
                    icon: _isEdit
                        ? Icons.save_rounded
                        : Icons.cloud_upload_rounded,
                    color: const Color(0xFF00796B))),
      ]),
    );
  }
}

// ─── SCREEN 12: VIEW REVIEWER — iPhone Notes style ────────────────────────────
class ViewReviewerScreen extends StatelessWidget {
  final Reviewer reviewer;
  const ViewReviewerScreen({super.key, required this.reviewer});

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: kTextPrimary),
          title: const Text("Reviewer",
              style: TextStyle(color: kTextSecondary, fontSize: 14)),
          actions: [
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: kSuccess.withAlpha(40),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text("READ MODE",
                            style: TextStyle(
                                color: kSuccess,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)))))
          ]),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Large title — iPhone Notes style
              Text(reviewer.title,
                  style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              const SizedBox(height: 16),
              Divider(color: kAccentLight.withAlpha(30), height: 1),
              const SizedBox(height: 16),
              // Body text — left aligned, no bubble
              SelectableText(reviewer.content,
                  style: const TextStyle(
                      color: kTextPrimary, fontSize: 16, height: 1.85)),
              const SizedBox(height: 40),
            ]),
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(20),
            child: glowButton(
                label: "Done Reading",
                onTap: () => Navigator.pop(context),
                icon: null,
                color: kSuccess)),
      ]),
    );
  }
}

// ─── SCREEN 12B: REVIEWER READ
class ReviewerReadScreen extends StatelessWidget {
  final Deck deck;
  const ReviewerReadScreen({super.key, required this.deck});

  @override
  Widget build(BuildContext context) {
    return gradientScaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: kTextPrimary),
          title: const Text("Reviewer",
              style: TextStyle(color: kTextSecondary, fontSize: 14)),
          actions: [
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: kSuccess.withAlpha(40),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text("READ MODE",
                            style: TextStyle(
                                color: kSuccess,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)))))
          ]),
      body: Column(children: [
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Large title
            Text(deck.name,
                style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.2)),
            const SizedBox(height: 16),
            Divider(color: kAccentLight.withAlpha(30), height: 1),
            const SizedBox(height: 16),
            SelectableText(deck.reviewerText ?? '',
                style: const TextStyle(
                    color: kTextPrimary, fontSize: 16, height: 1.8)),
            const SizedBox(height: 40),
          ]),
        )),
        Padding(
            padding: const EdgeInsets.all(20),
            child: glowButton(
                label: "Done Reading",
                onTap: () => Navigator.pop(context),
                icon: null,
                color: kSuccess)),
      ]),
    );
  }
}
