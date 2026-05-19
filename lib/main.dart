// ═══════════════════════════════════════════════════════════════════
// PART 1 — main.dart · Tokens · Models · Global State
// ═══════════════════════════════════════════════════════════════════
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

class FlashLearnApp extends StatelessWidget {
  const FlashLearnApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A00E0))),
        home: const AuthGateScreen(),
      );
}

// ─── TOKENS ──────────────────────────────────────────────────────────────────
const kGradientStart = Color(0xFF0F0C29);
const kGradientMid   = Color(0xFF302B63);
const kGradientEnd   = Color(0xFF24243E);
const kAccent        = Color(0xFF9B59B6);
const kAccentLight   = Color(0xFFBB86FC);
const kAccentGlow    = Color(0xFF7C3AED);
const kCardBg        = Color(0xFF1E1B3A);
const kCardBgLight   = Color(0xFF2A2750);
const kTextPrimary   = Color(0xFFF0EEFF);
const kTextSecondary = Color(0xFFAA9FCC);
const kSuccess       = Color(0xFF4CAF50);
const kError         = Color(0xFFEF5350);
const kWarning       = Color(0xFFFF9800);

LinearGradient get kBgGradient => const LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [kGradientStart, kGradientMid, kGradientEnd]);

LinearGradient get kButtonGradient =>
    const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF9B59B6)]);

BoxDecoration kCardDecoration({Color? color, double radius = 20}) => BoxDecoration(
      color: color ?? kCardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: kAccentLight.withAlpha(40)),
      boxShadow: [BoxShadow(color: kAccentGlow.withAlpha(30), blurRadius: 20, spreadRadius: 2)],
    );

// ─── MODELS ───────────────────────────────────────────────────────────────────
class Flashcard {
  String id, question, answer, mode;
  String? userAnswer;
  Flashcard({this.id = '', required this.question, required this.answer,
      required this.mode, this.userAnswer});
  factory Flashcard.fromMap(Map<String, dynamic> m, String id) =>
      Flashcard(id: id, question: m['question'] ?? '', answer: m['answer'] ?? '', mode: m['mode'] ?? 'Identification');
  Map<String, dynamic> toMap() => {'question': question, 'answer': answer, 'mode': mode};
}

class Deck {
  String id, name;
  List<Flashcard> cards;
  String? reviewerText;
  Deck({this.id = '', required this.name, required this.cards, this.reviewerText});
  factory Deck.fromMap(Map<String, dynamic> m, String id) =>
      Deck(id: id, name: m['name'] ?? '', cards: [], reviewerText: m['reviewerText']);
  Map<String, dynamic> toMap() =>
      {'name': name, if (reviewerText != null) 'reviewerText': reviewerText};
}

class Reviewer {
  String id, title, content;
  String? linkedDeckId;
  DateTime? createdAt;
  Reviewer({this.id = '', required this.title, required this.content,
      this.linkedDeckId, this.createdAt});
  factory Reviewer.fromMap(Map<String, dynamic> m, String id) => Reviewer(
        id: id, title: m['title'] ?? 'Untitled', content: m['content'] ?? '',
        linkedDeckId: m['linkedDeckId'],
        createdAt: (m['createdAt'] as Timestamp?)?.toDate());
  Map<String, dynamic> toMap() => {
        'title': title, 'content': content,
        if (linkedDeckId != null) 'linkedDeckId': linkedDeckId,
        'createdAt': FieldValue.serverTimestamp()};
}

class Note {
  String id, title, description;
  Note({this.id = '', required this.title, required this.description});
  factory Note.fromMap(Map<String, dynamic> m, String id) =>
      Note(id: id, title: m['title'] ?? '', description: m['description'] ?? '');
  Map<String, dynamic> toMap() => {'title': title, 'description': description};
}

// ─── GLOBAL STATE ─────────────────────────────────────────────────────────────
List<Deck>     globalDecks     = [];
List<Deck>     trashedDecks    = [];
List<Reviewer> globalReviewers = [];
List<Note>     globalNotes     = [];
int  totalQuizzesTaken = 0, totalQuestionsAnswered = 0,
     totalCorrectAnswers = 0, totalCardsStudied = 0,
     totalFlashcardSessions = 0, totalFlashcardsKnown = 0,
     totalFlashcardsUnknown = 0;
Set<String> daysStudied = {};

// ─── AUTH GATE ────────────────────────────────────────────────────────────────
class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Container(decoration: BoxDecoration(gradient: kBgGradient),
                child: const Center(child: CircularProgressIndicator(color: kAccentLight)));
          }
          return snap.hasData ? const MainMenuScreen() : const LoginScreen();
        });
}

// ═══════════════════════════════════════════════════════════════════
// PART 2 — Services · Helpers · Shared Widgets · Auth Screens
// ═══════════════════════════════════════════════════════════════════

// ─── FIRESTORE SERVICE ────────────────────────────────────────────────────────
class FirestoreService {
  final _db = FirebaseFirestore.instance;
  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _decks     => _db.collection('users').doc(uid).collection('decks');
  CollectionReference get _reviewers => _db.collection('users').doc(uid).collection('reviewers');
  CollectionReference get _notes     => _db.collection('users').doc(uid).collection('notes');
  DocumentReference   get _stats     => _db.collection('users').doc(uid);

  Future<List<Deck>> loadDecks() async {
    if (uid.isEmpty) return [];
    final snap = await _decks.get();
    List<Deck> decks = [];
    for (var doc in snap.docs) {
      final deck = Deck.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      final cs = await _decks.doc(doc.id).collection('cards').get();
      deck.cards = cs.docs.map((c) => Flashcard.fromMap(c.data(), c.id)).toList();
      decks.add(deck);
    }
    return decks;
  }

  Future<String> createOrGetDeck(String name) async {
    if (uid.isEmpty) throw Exception('Not authenticated');
    final ex = await _decks.where('name', isEqualTo: name).limit(1).get();
    if (ex.docs.isNotEmpty) return ex.docs.first.id;
    final doc = await _decks.add({'name': name, 'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  Future<String> restoreDeck(Deck deck) async {
    if (uid.isEmpty) throw Exception('Not authenticated');
    final ref = await _decks.add({
      'name': deck.name, 'uid': uid, 'createdAt': FieldValue.serverTimestamp(),
      if (deck.reviewerText != null) 'reviewerText': deck.reviewerText});
    for (final c in deck.cards) {
      await ref.collection('cards').add({'question': c.question, 'answer': c.answer, 'mode': c.mode});
    }
    return ref.id;
  }

  Future<String> addCard(String deckId, String q, String a, String mode) async {
    final doc = await _decks.doc(deckId).collection('cards').add({'question': q, 'answer': a, 'mode': mode});
    return doc.id;
  }
  Future<void> updateCard(String deckId, String cardId, String q, String a, String mode) =>
      _decks.doc(deckId).collection('cards').doc(cardId).update({'question': q, 'answer': a, 'mode': mode});
  Future<void> deleteCard(String deckId, String cardId) =>
      _decks.doc(deckId).collection('cards').doc(cardId).delete();
  Future<void> deleteDeck(String deckId) async {
    final cards = await _decks.doc(deckId).collection('cards').get();
    for (var c in cards.docs) {
      await c.reference.delete();
    }
    await _decks.doc(deckId).delete();
  }
  Future<void> updateDeckName(String deckId, String name) => _decks.doc(deckId).update({'name': name});
  Future<void> saveReviewerText(String deckId, String text) => _decks.doc(deckId).update({'reviewerText': text});

  Future<List<Reviewer>> loadReviewers() async {
    if (uid.isEmpty) return [];
    final snap = await _reviewers.orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => Reviewer.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }
  Future<String> addReviewer(String title, String content, {String? linkedDeckId}) async {
    if (uid.isEmpty) throw Exception('Not authenticated');
    final doc = await _reviewers.add({
      'title': title, 'content': content, 'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (linkedDeckId != null) 'linkedDeckId': linkedDeckId});
    return doc.id;
  }
  Future<void> updateReviewer(String id, String title, String content, {String? linkedDeckId}) =>
      _reviewers.doc(id).update({'title': title, 'content': content, 'linkedDeckId': linkedDeckId});
  Future<void> deleteReviewer(String id) => _reviewers.doc(id).delete();

  Future<List<Note>> loadNotes() async {
    if (uid.isEmpty) return [];
    final snap = await _notes.orderBy('createdAt').get();
    return snap.docs.map((d) => Note.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }
  Future<String> addNote(String title, String desc) async {
    if (uid.isEmpty) throw Exception('Not authenticated');
    final doc = await _notes.add({'title': title, 'description': desc, 'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
    return doc.id;
  }
  Future<void> updateNote(String id, String title, String desc) =>
      _notes.doc(id).update({'title': title, 'description': desc});
  Future<void> deleteNote(String id) => _notes.doc(id).delete();

  Future<void> saveStats() async {
    if (uid.isEmpty) return;
    await _stats.set({'stats': {
      'totalQuizzesTaken': totalQuizzesTaken, 'totalQuestionsAnswered': totalQuestionsAnswered,
      'totalCorrectAnswers': totalCorrectAnswers, 'totalCardsStudied': totalCardsStudied,
      'totalFlashcardSessions': totalFlashcardSessions, 'totalFlashcardsKnown': totalFlashcardsKnown,
      'totalFlashcardsUnknown': totalFlashcardsUnknown, 'daysStudied': daysStudied.toList()}},
        SetOptions(merge: true));
  }

  Future<void> loadStats() async {
    if (uid.isEmpty) return;
    final doc = await _stats.get();
    if (!doc.exists) return;
    final s = (doc.data() as Map<String, dynamic>?)?['stats'] as Map<String, dynamic>?;
    if (s == null) return;
    totalQuizzesTaken        = (s['totalQuizzesTaken']        ?? 0) as int;
    totalQuestionsAnswered   = (s['totalQuestionsAnswered']   ?? 0) as int;
    totalCorrectAnswers      = (s['totalCorrectAnswers']      ?? 0) as int;
    totalCardsStudied        = (s['totalCardsStudied']        ?? 0) as int;
    totalFlashcardSessions   = (s['totalFlashcardSessions']   ?? 0) as int;
    totalFlashcardsKnown     = (s['totalFlashcardsKnown']     ?? 0) as int;
    totalFlashcardsUnknown   = (s['totalFlashcardsUnknown']   ?? 0) as int;
    daysStudied = Set<String>.from((s['daysStudied'] as List? ?? []));
  }
}

// ─── AUTH SERVICE ─────────────────────────────────────────────────────────────
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  String _enc(String v, String k) {
    final kb = k.codeUnits;
    final r  = StringBuffer();
    for (var i = 0; i < v.length; i++) r.writeCharCode(v.codeUnitAt(i) ^ kb[i % kb.length]);
    return r.toString().codeUnits.map((b) => b.toString().padLeft(3, '0')).join();
  }
  String _dec(String enc, String k) {
    final sb = StringBuffer();
    for (var i = 0; i < enc.length; i += 3) sb.writeCharCode(int.parse(enc.substring(i, i + 3)));
    final raw = sb.toString(); final kb = k.codeUnits; final r = StringBuffer();
    for (var i = 0; i < raw.length; i++) r.writeCharCode(raw.codeUnitAt(i) ^ kb[i % kb.length]);
    return r.toString();
  }

  Future<String?> signUp(String email, String password, String name) async {
    try {
      final c = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await c.user!.updateDisplayName(name);
      await _db.collection('users').doc(c.user!.uid).set({
        'name': name, 'email': email, 'createdAt': FieldValue.serverTimestamp(),
        '_pk': _enc(password, email.trim() + name.trim())});
      return null;
    } on FirebaseAuthException catch (e) { return e.message; }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final c = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final name = c.user!.displayName ?? '';
      await _db.collection('users').doc(c.user!.uid)
          .set({'_pk': _enc(password, email.trim() + name.trim())}, SetOptions(merge: true));
      return null;
    } on FirebaseAuthException catch (e) { return e.message; }
  }

  Future<void> signOut(BuildContext context) async {
    globalDecks.clear(); trashedDecks.clear(); globalReviewers.clear(); globalNotes.clear();
    await _auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  Future<String?> verifyEmailAndName(String email, String name) async {
    try {
      final snap = await _db.collection('users').where('email', isEqualTo: email.trim()).limit(1).get();
      if (snap.docs.isEmpty) return 'No account found with this email address.';
      final stored = (snap.docs.first.data()['name'] ?? '') as String;
      return stored.trim().toLowerCase() == name.trim().toLowerCase() ? null : 'The name you entered does not match the account.';
    } catch (_) { return 'No account found with this email address.'; }
  }

  Future<String?> changePasswordWithEmail(String email, String name, String newPass) async {
    try {
      final snap = await _db.collection('users').where('email', isEqualTo: email.trim()).limit(1).get();
      if (snap.docs.isEmpty) return 'Account not found.';
      final data = snap.docs.first.data(); final uid = snap.docs.first.id;
      final pk = data['_pk'] as String? ?? '';
      if (pk.isEmpty) return 'Unable to reset. Please contact support.';
      final key = email.trim() + (data['name'] as String? ?? name).trim();
      final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: _dec(pk, key));
      await c.user!.updatePassword(newPass);
      await _db.collection('users').doc(uid).update({'_pk': _enc(newPass, key)});
      await _auth.signOut();
      return null;
    } catch (_) { return 'Failed to reset password. Please try again.'; }
  }

  User? get currentUser => _auth.currentUser;
}

// ─── HELPERS / SHARED WIDGETS ─────────────────────────────────────────────────
Widget gradientScaffold({required Widget body, PreferredSizeWidget? appBar,
    Widget? bottomNav, bool safeArea = true}) {
  Widget c = safeArea ? SafeArea(child: body) : body;
  return Scaffold(
    extendBodyBehindAppBar: true, backgroundColor: kGradientStart,
    appBar: appBar, bottomNavigationBar: bottomNav,
    body: Container(decoration: BoxDecoration(gradient: kBgGradient), child: c));
}

AppBar gradientAppBar(String title, {List<Widget>? actions}) => AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    iconTheme: const IconThemeData(color: kTextPrimary),
    title: Text(title, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 20)),
    actions: actions);

Widget glowButton({required String label, required VoidCallback onTap,
    Color? color, IconData? icon, double height = 56}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: height,
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color ?? kAccentGlow, (color ?? kAccentGlow).withAlpha(180)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: (color ?? kAccentGlow).withAlpha(80), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),
    ),
  );
}

Widget buildBottomNav(BuildContext context, int current) => Container(
      decoration: BoxDecoration(color: kCardBg,
          border: Border(top: BorderSide(color: kAccentLight.withAlpha(50)))),
      child: BottomNavigationBar(
        currentIndex: current, backgroundColor: Colors.transparent, elevation: 0,
        selectedItemColor: kAccentLight, unselectedItemColor: kTextSecondary,
        onTap: (i) {
          if (i == 0) {
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainMenuScreen()), (_) => false);
          }
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
          if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen()));
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded),       label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded),  label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.delete_rounded),     label: 'Trash'),
        ],
      ));

// Shared styled text field
Widget _styledField(TextEditingController ctrl, String label, IconData icon,
    {bool isPass = false, bool isEmail = false, bool obscure = false, VoidCallback? toggleObscure}) {
  return TextField(
    controller: ctrl,
    obscureText: isPass && obscure,
    keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
    style: const TextStyle(color: kTextPrimary),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: kTextSecondary),
      prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
      suffixIcon: isPass && toggleObscure != null
          ? IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: kTextSecondary, size: 20),
              onPressed: toggleObscure)
          : null,
      filled: true, fillColor: kCardBgLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
    ),
  );
}

Widget _errBox(String msg) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.error_outline, color: kError, size: 18), const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(color: kError, fontSize: 13))),
    ]));

// ─── LOGIN SCREEN ─────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading = false, _obscure = true;
  String? _error;
  final _auth = AuthService();

  void _login() async {
    final email = _emailCtrl.text.trim(), pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) { setState(() => _error = "Please fill in all fields."); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final err = await _auth.signIn(email, pass);
      if (!mounted) return;
      if (err != null) {
        setState(() { _loading = false; _error = "There was an error with your email/password combination, please double check and try again."; });
      } else {
        setState(() => _loading = false);
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainMenuScreen()), (_) => false);
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = "There was an error with your email/password combination, please double check and try again."; });
    }
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(children: [
        const SizedBox(height: 80),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4A00E0)]),
              boxShadow: [BoxShadow(color: kAccentGlow.withAlpha(120), blurRadius: 25, spreadRadius: 2)]),
          child: const Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 48)),
        const SizedBox(height: 16),
        const Text("Flash Learn", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextPrimary, letterSpacing: -0.5)),
        const Text("Quick study, smart recall", style: TextStyle(color: kTextSecondary, fontSize: 13, letterSpacing: 1)),
        const SizedBox(height: 48),
        Container(
          padding: const EdgeInsets.all(24), decoration: kCardDecoration(),
          child: Column(children: [
            const Align(alignment: Alignment.centerLeft,
                child: Text("Sign In", style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.w800))),
            const SizedBox(height: 20),
            _styledField(_emailCtrl, "Email", Icons.email_outlined, isEmail: true),
            const SizedBox(height: 14),
            _styledField(_passCtrl, "Password", Icons.lock_outline,
                isPass: true, obscure: _obscure, toggleObscure: () => setState(() => _obscure = !_obscure)),
            if (_error != null) ...[const SizedBox(height: 12), _errBox(_error!)],
            const SizedBox(height: 20),
            _loading ? const CircularProgressIndicator(color: kAccentLight)
                : glowButton(label: "Sign In", onTap: _login, icon: Icons.login_rounded),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
              child: const Text("Forgot Password?", style: TextStyle(color: kAccentLight, fontSize: 14, fontWeight: FontWeight.w600))),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
              child: RichText(text: const TextSpan(text: "Don't have an account? ",
                  style: TextStyle(color: kTextSecondary, fontSize: 14),
                  children: [TextSpan(text: "Sign Up",
                      style: TextStyle(color: kAccentLight, fontWeight: FontWeight.w700))]))),
          ]),
        ),
        const SizedBox(height: 40),
      ]),
    ));
}

// ─── FORGOT PASSWORD SCREEN ───────────────────────────────────────────────────
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController(), _nameCtrl = TextEditingController(),
        _passCtrl  = TextEditingController(), _confCtrl = TextEditingController();
  bool _loading = false, _verified = false, _op = true, _oc = true, _done = false;
  String? _error;
  final _auth = AuthService();

  void _verify() async {
    if (_emailCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty) {
      setState(() => _error = "Please enter both your email and full name."); return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await _auth.verifyEmailAndName(_emailCtrl.text.trim(), _nameCtrl.text.trim());
    if (!mounted) return;
    setState(() { _loading = false; _error = err; if (err == null) _verified = true; });
  }

  void _reset() async {
    if (_passCtrl.text.isEmpty || _confCtrl.text.isEmpty) { setState(() => _error = "Please fill in both password fields."); return; }
    if (_passCtrl.text != _confCtrl.text) { setState(() => _error = "Passwords do not match."); return; }
    if (_passCtrl.text.length < 6) { setState(() => _error = "Password must be at least 6 characters."); return; }
    setState(() { _loading = true; _error = null; });
    final err = await _auth.changePasswordWithEmail(_emailCtrl.text.trim(), _nameCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    setState(() { _loading = false; _error = err; _done = err == null; });
  }

  @override
  void dispose() { _emailCtrl.dispose(); _nameCtrl.dispose(); _passCtrl.dispose(); _confCtrl.dispose(); super.dispose(); }

  Widget _pf(TextEditingController c, String label, bool obs, VoidCallback tog) =>
      _styledField(c, label, Icons.lock_outline, isPass: true, obscure: obs, toggleObscure: tog);

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("Forgot Password"),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
      child: Container(
        padding: const EdgeInsets.all(24), decoration: kCardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_reset_rounded, color: kAccentLight, size: 40),
          const SizedBox(height: 14),
          Text(_verified ? "Set New Password" : "Reset Password",
              style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_verified ? "Your identity has been confirmed. Enter your new password below."
              : "Enter the email address and full name linked to your account.",
              style: const TextStyle(color: kTextSecondary, fontSize: 13, height: 1.5)),
          const SizedBox(height: 24),
          if (!_verified) ...[
            _styledField(_emailCtrl, "Email", Icons.email_outlined, isEmail: true),
            const SizedBox(height: 14),
            _styledField(_nameCtrl, "Full Name", Icons.person_outline),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: kSuccess.withAlpha(30), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSuccess.withAlpha(80))),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: kSuccess, size: 18), const SizedBox(width: 8),
                Expanded(child: Text("Identity confirmed: ${_emailCtrl.text.trim()}",
                    style: const TextStyle(color: kSuccess, fontSize: 13))),
              ])),
            const SizedBox(height: 16),
            _pf(_passCtrl, "New Password",     _op, () => setState(() => _op = !_op)),
            const SizedBox(height: 12),
            _pf(_confCtrl, "Confirm New Password", _oc, () => setState(() => _oc = !_oc)),
          ],
          if (_error != null) ...[const SizedBox(height: 12), _errBox(_error!)],
          if (_done) ...[const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kSuccess.withAlpha(40), borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.check_circle_outline, color: kSuccess, size: 18), SizedBox(width: 8),
                Expanded(child: Text("Password updated successfully! You can now sign in.",
                    style: TextStyle(color: kSuccess, fontSize: 13)))]))],
          const SizedBox(height: 20),
          _loading ? const Center(child: CircularProgressIndicator(color: kAccentLight))
              : _done
                  ? glowButton(label: "Back to Sign In", onTap: () => Navigator.pop(context), icon: Icons.arrow_back_rounded)
                  : glowButton(
                      label: _verified ? "Reset Password" : "Verify Identity",
                      onTap: _verified ? _reset : _verify,
                      icon: _verified ? Icons.lock_reset_rounded : Icons.verified_rounded),
          const SizedBox(height: 14),
          if (!_done) Center(child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Text("Back to Sign In", style: TextStyle(color: kAccentLight, fontSize: 14, fontWeight: FontWeight.w600)))),
        ]),
      ),
    ));
}

// ─── SIGN UP SCREEN ───────────────────────────────────────────────────────────
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override State<SignUpScreen> createState() => _SignUpScreenState();
}
class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController(), _emailCtrl = TextEditingController(),
        _passCtrl = TextEditingController(), _confCtrl  = TextEditingController();
  bool _loading = false, _obscure = true;
  String? _error;
  final _auth = AuthService();

  void _signUp() async {
    if (_passCtrl.text != _confCtrl.text) { setState(() => _error = "Passwords do not match."); return; }
    if ([_nameCtrl, _emailCtrl, _passCtrl].any((c) => c.text.isEmpty)) {
      setState(() => _error = "Please fill in all fields."); return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await _auth.signUp(_emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() { _loading = false; _error = err; });
    } else {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainMenuScreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("Create Account"),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 90, 28, 28),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(24), decoration: kCardDecoration(),
          child: Column(children: [
            _styledField(_nameCtrl,  "Full Name", Icons.person_outline),
            const SizedBox(height: 14),
            _styledField(_emailCtrl, "Email",    Icons.email_outlined,  isEmail: true),
            const SizedBox(height: 14),
            _styledField(_passCtrl,  "Password", Icons.lock_outline,    isPass: true, obscure: _obscure, toggleObscure: () => setState(() => _obscure = !_obscure)),
            const SizedBox(height: 14),
            _styledField(_confCtrl,  "Confirm Password", Icons.lock_outline, isPass: true, obscure: _obscure, toggleObscure: () => setState(() => _obscure = !_obscure)),
            if (_error != null) ...[const SizedBox(height: 12), _errBox(_error!)],
            const SizedBox(height: 20),
            _loading ? const CircularProgressIndicator(color: kAccentLight)
                : glowButton(label: "Create Account", onTap: _signUp, icon: Icons.person_add_rounded),
          ]),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: RichText(text: const TextSpan(text: "Already have an account? ",
              style: TextStyle(color: kTextSecondary, fontSize: 14),
              children: [TextSpan(text: "Sign In", style: TextStyle(color: kAccentLight, fontWeight: FontWeight.w700))]))),
      ]),
    ));
}

// ═══════════════════════════════════════════════════════════════════
// PART 3 — Main Menu · Decks · Deck Editor · Stats · Trash
// ═══════════════════════════════════════════════════════════════════

// ─── MENU ITEM DATA CLASS (replaces record tuple) ────────────────────────────
class _MenuItem {
  final String label;
  final Color color;
  final IconData icon;
  final Future<void> Function() onTap;
  const _MenuItem({required this.label, required this.color, required this.icon, required this.onTap});
}

// ─── MAIN MENU ────────────────────────────────────────────────────────────────
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override State<MainMenuScreen> createState() => _MainMenuScreenState();
}
class _MainMenuScreenState extends State<MainMenuScreen> {
  final _fs = FirestoreService(), _auth = AuthService();
  final _noteTitleCtrl = TextEditingController(), _noteDescCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadAll(); }

  Future<void> _loadAll() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final r = await Future.wait([_fs.loadDecks(), _fs.loadReviewers(), _fs.loadNotes()]);
      await _fs.loadStats();
      if (mounted) {
        setState(() {
          globalDecks     = r[0] as List<Deck>;
          globalReviewers = r[1] as List<Reviewer>;
          globalNotes     = r[2] as List<Note>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MenuItem> get _menuItems => [
    _MenuItem(
      label: "Start Review",
      color: kSuccess,
      icon: Icons.bolt_rounded,
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const DeckSelectScreen()));
        if (mounted) setState(() {});
      },
    ),
    _MenuItem(
      label: "Create FlashCards",
      color: kAccentGlow,
      icon: Icons.add_circle_rounded,
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateFlashcardScreen()));
        if (mounted) setState(() {});
      },
    ),
    _MenuItem(
      label: "My Decks",
      color: const Color(0xFF1565C0),
      icon: Icons.folder_rounded,
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDecksListScreen()));
        if (mounted) setState(() {});
      },
    ),
    _MenuItem(
      label: "My Reviewers",
      color: const Color(0xFF00796B),
      icon: Icons.menu_book_rounded,
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewerListScreen()));
        if (mounted) setState(() {});
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return gradientScaffold(
      bottomNav: buildBottomNav(context, 0),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: kAccentLight), SizedBox(height: 16),
              Text("Loading your decks...", style: TextStyle(color: kTextSecondary))]))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                const SizedBox(height: 30),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4A00E0)]),
                          boxShadow: [BoxShadow(color: kAccentGlow.withAlpha(120), blurRadius: 25, spreadRadius: 2)]),
                      child: const Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 32)),
                    const SizedBox(height: 10),
                    const Text("Flash Learn", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kTextPrimary, letterSpacing: -0.5)),
                    Text("Hello, ${user?.displayName ?? 'Learner'}!", style: const TextStyle(color: kTextSecondary, fontSize: 13)),
                  ])),
                  GestureDetector(
                    onTap: () => _auth.signOut(context),
                    child: Container(padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kAccentLight.withAlpha(40))),
                        child: const Icon(Icons.logout_rounded, color: kError, size: 20))),
                ]),
                const SizedBox(height: 30),
                ..._menuItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: item.onTap,
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(220),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: item.color.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))],
                      ),
                      child: Row(children: [
                        const SizedBox(width: 20),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                          child: Icon(item.icon, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Text(item.label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                        const SizedBox(width: 16),
                      ]),
                    ),
                  ),
                )),
                const SizedBox(height: 12),
                _buildNotesSection(),
                const SizedBox(height: 20),
              ])));
  }

  Widget _buildNotesSection() => Container(
    constraints: const BoxConstraints(minHeight: 150, maxHeight: 260),
    decoration: kCardDecoration(),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          const Icon(Icons.sticky_note_2_rounded, color: kAccentLight, size: 20), const SizedBox(width: 8),
          const Text("NOTES", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 1.5)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.add_rounded, color: kAccentLight),
              onPressed: () => showDialog(context: context, builder: (_) => _buildNoteDialog())),
        ])),
      Divider(color: kAccentLight.withAlpha(40), height: 1),
      Expanded(child: globalNotes.isEmpty
          ? const Center(child: Text("No notes yet. Tap + to add.", style: TextStyle(color: kTextSecondary, fontSize: 13)))
          : ListView.builder(
              itemCount: globalNotes.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: const Icon(Icons.circle, color: kAccentLight, size: 8),
                title: Text(globalNotes[i].title, style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: globalNotes[i].description.isNotEmpty
                    ? Text(globalNotes[i].description, style: const TextStyle(color: kTextSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () => _showNoteOptions(i)))),
    ]));

  void _showNoteOptions(int i) {
    final note = globalNotes[i];
    showModalBottomSheet(context: context, backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(note.title, style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          if (note.description.isNotEmpty) ...[const SizedBox(height: 6),
            Text(note.description, style: const TextStyle(color: kTextSecondary, fontSize: 14, height: 1.5))],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _noteAction("Edit", Icons.edit_rounded, kAccentLight, kAccentGlow, () {
              Navigator.pop(context);
              showDialog(context: context, builder: (_) => _buildNoteDialog(editIndex: i));
            })),
            const SizedBox(width: 12),
            Expanded(child: _noteAction("Delete", Icons.delete_rounded, kError, kError, () async {
              Navigator.pop(context);
              await _fs.deleteNote(note.id);
              setState(() => globalNotes.removeAt(i));
            })),
          ]),
          const SizedBox(height: 8),
        ])));
  }

  Widget _noteAction(String label, IconData icon, Color color, Color bg, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
        child: Container(height: 48, alignment: Alignment.center,
          decoration: BoxDecoration(color: bg.withAlpha(40), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: bg.withAlpha(80))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18), const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700))])));

  Widget _buildNoteDialog({int? editIndex}) {
    final isEdit = editIndex != null;
    if (isEdit) {
      _noteTitleCtrl.text = globalNotes[editIndex].title;
      _noteDescCtrl.text = globalNotes[editIndex].description;
    } else {
      _noteTitleCtrl.clear();
      _noteDescCtrl.clear();
    }
    return StatefulBuilder(builder: (ctx, _) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF1E1B3A), Color(0xFF2A2750)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: kAccentLight.withAlpha(50)),
            boxShadow: [BoxShadow(color: kAccentGlow.withAlpha(60), blurRadius: 30, spreadRadius: 2)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kAccentGlow.withAlpha(200), kAccentGlow.withAlpha(100)]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Text(isEdit ? "Edit Note" : "New Note",
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dialogFieldLabel("Title"),
              _dialogInputBox(_noteTitleCtrl, "Note title", Icons.title_rounded, maxLines: 1),
              const SizedBox(height: 14),
              _dialogFieldLabel("Description"),
              _dialogInputBox(_noteDescCtrl, "Add a description", null, maxLines: 4),
            ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () { _noteTitleCtrl.clear(); _noteDescCtrl.clear(); Navigator.pop(ctx); },
                child: Container(height: 48, alignment: Alignment.center,
                    decoration: BoxDecoration(border: Border.all(color: kAccentLight.withAlpha(50)), borderRadius: BorderRadius.circular(14)),
                    child: const Text("Cancel", style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600))))),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: () async {
                  final title = _noteTitleCtrl.text.trim();
                  if (title.isEmpty) return;
                  final desc = _noteDescCtrl.text.trim();
                  Navigator.pop(ctx);
                  if (isEdit) {
                    final note = globalNotes[editIndex];
                    await _fs.updateNote(note.id, title, desc);
                    setState(() => globalNotes[editIndex] = Note(id: note.id, title: title, description: desc));
                  } else {
                    final id = await _fs.addNote(title, desc);
                    setState(() => globalNotes.add(Note(id: id, title: title, description: desc)));
                  }
                  _noteTitleCtrl.clear(); _noteDescCtrl.clear();
                },
                child: Container(height: 48, alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: kAccentGlow.withAlpha(80), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(isEdit ? Icons.save_rounded : Icons.add_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(isEdit ? "Save" : "Add Note", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ])))),
            ])),
        ]),
      )));
  }

  Widget _dialogFieldLabel(String t) => Text(t,
      style: const TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1));
  Widget _dialogInputBox(TextEditingController ctrl, String hint, IconData? icon, {int maxLines = 1}) =>
      Container(margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kAccentLight.withAlpha(40))),
        child: TextField(controller: ctrl, maxLines: maxLines,
          style: const TextStyle(color: kTextPrimary, fontSize: 15),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: kTextSecondary),
              border: InputBorder.none, contentPadding: const EdgeInsets.all(14),
              prefixIcon: icon != null ? Icon(icon, color: kAccentLight, size: 18) : null)));
}

// ─── MY DECKS LIST ────────────────────────────────────────────────────────────
class MyDecksListScreen extends StatefulWidget {
  const MyDecksListScreen({super.key});
  @override State<MyDecksListScreen> createState() => _MyDecksListScreenState();
}
class _MyDecksListScreenState extends State<MyDecksListScreen> {
  final _fs = FirestoreService(); bool _loading = false;

  @override void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final d = await _fs.loadDecks();
      if (mounted) setState(() { globalDecks = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("My Decks"), bottomNav: buildBottomNav(context, 0),
    body: _loading ? const Center(child: CircularProgressIndicator(color: kAccentLight))
        : globalDecks.isEmpty
            ? const Center(child: Text("No decks yet. Create some flashcards!", style: TextStyle(color: kTextSecondary)))
            : RefreshIndicator(onRefresh: _refresh, color: kAccentLight, backgroundColor: kCardBg,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 20), itemCount: globalDecks.length,
                  itemBuilder: (_, i) => Container(
                    margin: const EdgeInsets.only(bottom: 12), decoration: kCardDecoration(),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: Container(width: 42, height: 42,
                          decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.folder_rounded, color: Colors.white, size: 22)),
                      title: Text(globalDecks[i].name, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                      subtitle: Text("${globalDecks[i].cards.length} cards", style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_rounded, color: kAccentLight, size: 20),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => DeckEditorScreen(deckIndex: i)));
                              setState(() {});
                            }),
                        IconButton(icon: const Icon(Icons.delete_rounded, color: kError, size: 20),
                            onPressed: () async {
                              final removed = globalDecks[i];
                              await _fs.deleteDeck(globalDecks[i].id);
                              setState(() { globalDecks.removeAt(i); trashedDecks.add(removed); });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    _snack("Deck moved to Trash.", kCardBgLight));
                              }
                            }),
                      ]),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => DeckEditorScreen(deckIndex: i)));
                        setState(() {});
                      },
                    )))));
}

SnackBar _snack(String msg, Color bg) => SnackBar(content: Text(msg), backgroundColor: bg,
    behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));

// ─── CREATE FLASHCARD (deck list + new deck) ──────────────────────────────────
class CreateFlashcardScreen extends StatefulWidget {
  const CreateFlashcardScreen({super.key});
  @override State<CreateFlashcardScreen> createState() => _CreateFlashcardScreenState();
}
class _CreateFlashcardScreenState extends State<CreateFlashcardScreen> {
  final _fs = FirestoreService(); bool _loading = false;

  @override void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final d = await _fs.loadDecks();
      if (mounted) setState(() { globalDecks = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newDeck() {
    final ctrl = TextEditingController(); String? selRevId;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("New Deck", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: kTextPrimary),
          decoration: InputDecoration(hintText: "e.g. Biology Chapter 3", hintStyle: const TextStyle(color: kTextSecondary),
              filled: true, fillColor: kCardBgLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kAccentLight, width: 1.5)))),
        if (globalReviewers.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Align(alignment: Alignment.centerLeft, child: Text("Link Reviewer (optional)",
              style: TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(12)),
            child: DropdownButton<String?>(value: selRevId, isExpanded: true, dropdownColor: kCardBg,
              underline: const SizedBox(), style: const TextStyle(color: kTextPrimary, fontSize: 14),
              hint: const Text("No reviewer linked", style: TextStyle(color: kTextSecondary, fontSize: 13)),
              items: [const DropdownMenuItem<String?>(value: null, child: Text("No reviewer", style: TextStyle(color: kTextSecondary, fontSize: 13))),
                ...globalReviewers.map((r) => DropdownMenuItem<String?>(value: r.id, child: Text(r.title, overflow: TextOverflow.ellipsis)))],
              onChanged: (v) => setS(() => selRevId = v))),
        ],
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: kTextSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kAccentGlow, shape: const StadiumBorder()),
          onPressed: () async {
            final name = ctrl.text.trim(); if (name.isEmpty) return;
            Navigator.pop(ctx); setState(() => _loading = true);
            try {
              final deckId = await _fs.createOrGetDeck(name);
              String? revText;
              if (selRevId != null) {
                final rev = globalReviewers.firstWhere((r) => r.id == selRevId);
                await _fs.saveReviewerText(deckId, rev.content); revText = rev.content;
              }
              final newDeck = Deck(id: deckId, name: name, cards: [], reviewerText: revText);
              final ex = globalDecks.indexWhere((d) => d.id == deckId);
              if (ex == -1) {
                setState(() { globalDecks.add(newDeck); _loading = false; });
              } else {
                setState(() => _loading = false);
              }
              if (mounted) {
                final idx = globalDecks.indexWhere((d) => d.id == deckId);
                if (idx != -1) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => DeckEditorScreen(deckIndex: idx)));
                  setState(() {});
                }
              }
            } catch (_) {
              if (mounted) setState(() => _loading = false);
            }
          },
          child: const Text("Create", style: TextStyle(color: Colors.white))),
      ])));
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("My Flashcard Sets"), bottomNav: buildBottomNav(context, 0),
    body: _loading ? const Center(child: CircularProgressIndicator(color: kAccentLight))
        : Stack(children: [
            globalDecks.isEmpty
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.layers_outlined, color: kTextSecondary, size: 56), SizedBox(height: 16),
                    Text("No decks yet", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6), Text("Tap below to create your first deck", style: TextStyle(color: kTextSecondary, fontSize: 13))]))
                : RefreshIndicator(onRefresh: _refresh, color: kAccentLight, backgroundColor: kCardBg,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 100), itemCount: globalDecks.length,
                      itemBuilder: (_, i) {
                        final deck = globalDecks[i];
                        return GestureDetector(
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => DeckEditorScreen(deckIndex: i)));
                            setState(() {});
                          },
                          child: Container(margin: const EdgeInsets.only(bottom: 14), decoration: kCardDecoration(),
                            child: Padding(padding: const EdgeInsets.all(18),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Container(width: 42, height: 42,
                                      decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(12)),
                                      child: const Icon(Icons.layers_rounded, color: Colors.white, size: 22)),
                                  const SizedBox(width: 14),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(deck.name, style: const TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                                    Text("${deck.cards.length} card${deck.cards.length == 1 ? '' : 's'}", style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                                  ])),
                                  const Icon(Icons.edit_rounded, color: kAccentLight, size: 18), const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                        backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        title: const Text("Delete Deck", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
                                        content: Text("Are you sure you want to delete \"${deck.name}\"? This cannot be undone.", style: const TextStyle(color: kTextSecondary, height: 1.5)),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel", style: TextStyle(color: kTextSecondary))),
                                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kError, shape: const StadiumBorder()),
                                              onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.white))),
                                        ]));
                                      if (ok == true && mounted) {
                                        setState(() => _loading = true);
                                        try {
                                          await _fs.deleteDeck(deck.id);
                                          setState(() { globalDecks.removeAt(i); _loading = false; });
                                        } catch (_) {
                                          if (mounted) setState(() => _loading = false);
                                        }
                                      }
                                    },
                                    child: Container(padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                                        child: const Icon(Icons.delete_outline_rounded, color: kError, size: 18))),
                                ]),
                                if (deck.cards.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 6, runSpacing: 6, children: deck.cards.take(3).map((c) =>
                                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: kAccentLight.withAlpha(30))),
                                        child: Text(c.question.length > 25 ? c.question.substring(0, 25) : c.question,
                                            style: const TextStyle(color: kTextSecondary, fontSize: 11)))).toList()),
                                ],
                              ]))));
                      })),
            Positioned(bottom: 20, left: 20, right: 20,
                child: glowButton(label: "New Deck", onTap: _newDeck, icon: Icons.add_rounded)),
          ]));
}

// ─── DECK EDITOR ──────────────────────────────────────────────────────────────
class _CardEntry {
  final TextEditingController qCtrl, aCtrl;
  String mode; String? existingId;
  _CardEntry({String q = '', String a = '', this.mode = 'Identification', this.existingId})
      : qCtrl = TextEditingController(text: q), aCtrl = TextEditingController(text: a);
  void dispose() { qCtrl.dispose(); aCtrl.dispose(); }
}

class DeckEditorScreen extends StatefulWidget {
  final int deckIndex;
  const DeckEditorScreen({super.key, required this.deckIndex});
  @override State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}
class _DeckEditorScreenState extends State<DeckEditorScreen> {
  final _fs = FirestoreService(), _nameCtrl = TextEditingController(), _scrollCtrl = ScrollController();
  final List<_CardEntry> _entries = [];
  bool _saving = false; late Deck _deck;

  static const _modes = [
    {"label": "Identification", "icon": Icons.text_fields_rounded,          "color": Color(0xFF00796B)},
    {"label": "Enumeration",    "icon": Icons.format_list_numbered_rounded,  "color": Color(0xFF6A1B9A)},
    {"label": "True or False",  "icon": Icons.toggle_on_rounded,             "color": Color(0xFFE65100)},
  ];

  @override
  void initState() {
    super.initState();
    _deck = globalDecks[widget.deckIndex]; _nameCtrl.text = _deck.name;
    for (final c in _deck.cards) _entries.add(_CardEntry(q: c.question, a: c.answer, mode: c.mode, existingId: c.id));
    if (_entries.isEmpty) _entries.add(_CardEntry());
  }
  @override void dispose() { _nameCtrl.dispose(); _scrollCtrl.dispose(); for (final e in _entries) e.dispose(); super.dispose(); }

  void _addCard() {
    setState(() => _entries.add(_CardEntry()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _saveDeck() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(_snack("Deck name cannot be empty.", kError)); return; }
    final valid = _entries.where((e) => e.qCtrl.text.trim().isNotEmpty && e.aCtrl.text.trim().isNotEmpty).toList();
    if (valid.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(_snack("Add at least one complete card.", kError)); return; }
    setState(() => _saving = true);
    try {
      if (name != _deck.name) { await _fs.updateDeckName(_deck.id, name); globalDecks[widget.deckIndex].name = name; }
      List<Flashcard> saved = [];
      for (final e in _entries) {
        final q = e.qCtrl.text.trim(), a = e.aCtrl.text.trim();
        if (q.isEmpty || a.isEmpty) continue;
        if (e.existingId != null) {
          await _fs.updateCard(_deck.id, e.existingId!, q, a, e.mode);
          saved.add(Flashcard(id: e.existingId!, question: q, answer: a, mode: e.mode));
        } else {
          final id = await _fs.addCard(_deck.id, q, a, e.mode);
          saved.add(Flashcard(id: id, question: q, answer: a, mode: e.mode));
        }
      }
      final savedIds = saved.map((c) => c.id).toSet();
      for (final old in _deck.cards) {
        if (!savedIds.contains(old.id)) await _fs.deleteCard(_deck.id, old.id);
      }
      globalDecks[widget.deckIndex].cards = saved;
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(_snack("Deck \"$name\" saved", kSuccess));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("$e");
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _inputField(TextEditingController ctrl, String label, {String? hint, int maxLines = 1}) => TextField(
    controller: ctrl, maxLines: maxLines, style: const TextStyle(color: kTextPrimary, fontSize: 15),
    decoration: InputDecoration(labelText: label, hintText: hint,
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 13), hintStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
        filled: true, fillColor: kCardBgLight, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kAccentLight, width: 1.5))));

  Widget _modeChip(int idx) {
    final e = _entries[idx];
    final md = _modes.firstWhere((m) => m["label"] == e.mode, orElse: () => _modes[0]);
    final color = md["color"] as Color;
    final icon = md["icon"] as IconData;
    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, backgroundColor: kCardBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Question Type", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ..._modes.map((m) {
              final ml = m["label"] as String;
              final mc = m["color"] as Color;
              final mi = m["icon"] as IconData;
              final sel = ml == e.mode;
              return GestureDetector(
                onTap: () { setState(() => _entries[idx].mode = ml); Navigator.pop(context); },
                child: Container(margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: sel ? mc.withAlpha(200) : kCardBgLight, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? mc : kAccentLight.withAlpha(20))),
                  child: Row(children: [
                    Icon(mi, color: sel ? Colors.white : kTextSecondary, size: 20), const SizedBox(width: 12),
                    Expanded(child: Text(ml, style: TextStyle(color: sel ? Colors.white : kTextPrimary, fontWeight: FontWeight.w600))),
                    if (sel) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  ])));
            }),
          ]))),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withAlpha(50), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withAlpha(120))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14), const SizedBox(width: 6),
          Text(e.mode, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4), Icon(Icons.arrow_drop_down_rounded, color: color, size: 16),
        ])));
  }

  Widget _tfPicker(_CardEntry e) => Row(children: ["True", "False"].map((val) {
    final sel = e.aCtrl.text == val; final color = val == "True" ? kSuccess : kError;
    return Expanded(child: Padding(padding: EdgeInsets.only(right: val == "True" ? 6 : 0, left: val == "False" ? 6 : 0),
      child: GestureDetector(onTap: () => setState(() => e.aCtrl.text = val),
        child: AnimatedContainer(duration: const Duration(milliseconds: 180), height: 48, alignment: Alignment.center,
          decoration: BoxDecoration(color: sel ? color.withAlpha(200) : kCardBgLight, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? color : kAccentLight.withAlpha(30), width: sel ? 2 : 1)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(val == "True" ? Icons.check_circle_rounded : Icons.cancel_rounded, color: sel ? Colors.white : kTextSecondary, size: 18),
            const SizedBox(width: 6), Text(val, style: TextStyle(color: sel ? Colors.white : kTextSecondary, fontWeight: FontWeight.w700, fontSize: 15)),
          ])))));
  }).toList());

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("Edit Deck", actions: [
      Padding(padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(onPressed: _saving ? null : _saveDeck,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: kAccentLight, strokeWidth: 2))
                : const Icon(Icons.cloud_upload_rounded, color: kAccentLight, size: 18),
            label: Text(_saving ? "Saving" : "Save", style: const TextStyle(color: kAccentLight, fontWeight: FontWeight.w700)))),
    ]),
    bottomNav: buildBottomNav(context, 0),
    body: Column(children: [
      Expanded(child: ListView.builder(
        controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(20, 80, 20, 12),
        itemCount: _entries.length + 2,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Container(margin: const EdgeInsets.only(bottom: 16), decoration: kCardDecoration(),
              child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("DECK NAME", style: TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(controller: _nameCtrl, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(filled: true, fillColor: kCardBgLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kAccentLight, width: 1.5)))),
              ])));
          }
          if (i == _entries.length + 1) {
            return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(onTap: _addCard,
                child: Container(height: 52, alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: kAccentLight.withAlpha(80), width: 1.5),
                      borderRadius: BorderRadius.circular(16), color: kAccentGlow.withAlpha(20)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline_rounded, color: kAccentLight, size: 20), SizedBox(width: 8),
                    Text("Add Card", style: TextStyle(color: kAccentLight, fontWeight: FontWeight.w700, fontSize: 15)),
                  ]))));
          }
          final ei = i - 1; final e = _entries[ei];
          return Container(margin: const EdgeInsets.only(bottom: 14), decoration: kCardDecoration(),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 28, height: 28, alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(8)),
                    child: Text("${ei + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                const SizedBox(width: 10), _modeChip(ei), const Spacer(),
                if (_entries.length > 1) GestureDetector(onTap: () => setState(() => _entries.removeAt(ei)),
                  child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.close_rounded, color: kError, size: 16))),
              ]),
              const SizedBox(height: 12),
              _inputField(e.qCtrl, "Question"),
              const SizedBox(height: 10),
              if (e.mode == "True or False") _tfPicker(e)
              else _inputField(e.aCtrl, "Answer",
                  hint: e.mode == "Enumeration" ? "e.g. item1, item2, item3" : null,
                  maxLines: e.mode == "Enumeration" ? 2 : 1),
            ])));
        })),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _saving ? const Center(child: CircularProgressIndicator(color: kAccentLight))
              : glowButton(label: "Save Deck", onTap: _saveDeck, icon: Icons.save_rounded)),
    ]));
}

// ─── STATS ────────────────────────────────────────────────────────────────────
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final qAvg = totalQuestionsAnswered == 0 ? 0.0 : totalCorrectAnswers / totalQuestionsAnswered * 100;
    final total = totalFlashcardsKnown + totalFlashcardsUnknown;
    final fMas  = total == 0 ? 0.0 : totalFlashcardsKnown / total * 100;
    return gradientScaffold(
      appBar: gradientAppBar("Stats Overview"), bottomNav: buildBottomNav(context, 1),
      body: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 80, 20, 20), child: Column(children: [
        Row(children: [
          _mini("Days\nStudied",  "${daysStudied.length}", Icons.calendar_today_rounded, const Color(0xFF7C3AED)),
          const SizedBox(width: 12),
          _mini("Cards\nStudied", "$totalCardsStudied",    Icons.style_rounded,          const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          _mini("Quizzes\nTaken", "$totalQuizzesTaken",   Icons.quiz_rounded,            const Color(0xFF00796B)),
        ]),
        const SizedBox(height: 20),
        _perfCard("Quiz Performance",      qAvg, kAccentLight, "Average Score",  "Total Questions", "$totalQuestionsAnswered", "Correct Answers", "$totalCorrectAnswers", kSuccess),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(24), decoration: kCardDecoration(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Flashcard Performance", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Mastery Rate", style: TextStyle(color: kTextSecondary, fontSize: 14)),
            Text("${fMas.toInt()}%", style: const TextStyle(color: kSuccess, fontSize: 28, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: fMas / 100, minHeight: 10,
              backgroundColor: kCardBgLight, valueColor: const AlwaysStoppedAnimation<Color>(kSuccess))),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _statBox("Sessions", "$totalFlashcardSessions", color: const Color(0xFF7C3AED))),
            const SizedBox(width: 12),
            Expanded(child: _statBox("Cards Known",    "$totalFlashcardsKnown",    color: kSuccess)),
            const SizedBox(width: 12),
            Expanded(child: _statBox("Still Learning", "$totalFlashcardsUnknown",  color: kError)),
          ]),
        ])),
      ])));
  }

  Widget _mini(String label, String val, IconData icon, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withAlpha(80))),
    child: Column(children: [Icon(icon, color: color, size: 26), const SizedBox(height: 8),
      Text(val, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4), Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11), textAlign: TextAlign.center)])));

  Widget _perfCard(String title, double pct, Color barColor, String pctLabel, String l1, String v1, String l2, String v2, Color v2Color) =>
      Container(padding: const EdgeInsets.all(24), decoration: kCardDecoration(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(pctLabel, style: const TextStyle(color: kTextSecondary, fontSize: 14)),
          Text("${pct.toInt()}%", style: TextStyle(color: barColor, fontSize: 28, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: pct / 100, minHeight: 10,
            backgroundColor: kCardBgLight, valueColor: AlwaysStoppedAnimation<Color>(barColor))),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _statBox(l1, v1)),
          const SizedBox(width: 12),
          Expanded(child: _statBox(l2, v2, color: v2Color)),
        ])]));

  Widget _statBox(String label, String val, {Color? color}) => Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(val, style: TextStyle(color: color ?? kTextPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4), Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11), textAlign: TextAlign.center)]));
}

// ─── TRASH ────────────────────────────────────────────────────────────────────
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override State<TrashScreen> createState() => _TrashScreenState();
}
class _TrashScreenState extends State<TrashScreen> {
  final _fs = FirestoreService(); bool _restoring = false;

  Future<void> _restore(int i) async {
    setState(() => _restoring = true);
    try {
      final deck = trashedDecks[i];
      final newId = await _fs.restoreDeck(deck);
      final cs = await FirebaseFirestore.instance.collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid).collection('decks').doc(newId).collection('cards').get();
      final cards = cs.docs.map((c) => Flashcard.fromMap(c.data(), c.id)).toList();
      setState(() {
        trashedDecks.removeAt(i);
        globalDecks.add(Deck(id: newId, name: deck.name, cards: cards, reviewerText: deck.reviewerText));
        _restoring = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(_snack("Deck restored to My Decks", kSuccess));
    } catch (e) {
      debugPrint("$e");
      setState(() => _restoring = false);
    }
  }

  void _deletePerma(int i) => showDialog(context: context, builder: (_) => AlertDialog(
    backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text("Delete Permanently?", style: TextStyle(color: kTextPrimary)),
    content: Text("\"${trashedDecks[i].name}\" will be deleted forever.", style: const TextStyle(color: kTextSecondary)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: kTextSecondary))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kError, shape: const StadiumBorder()),
          onPressed: () { setState(() => trashedDecks.removeAt(i)); Navigator.pop(context); },
          child: const Text("Delete Forever", style: TextStyle(color: Colors.white))),
    ]));

  void _emptyTrash() {
    if (trashedDecks.isEmpty) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Empty Trash?", style: TextStyle(color: kTextPrimary)),
      content: const Text("All decks in the trash will be permanently deleted.", style: TextStyle(color: kTextSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: kTextSecondary))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kError, shape: const StadiumBorder()),
            onPressed: () { setState(() => trashedDecks.clear()); Navigator.pop(context); },
            child: const Text("Empty Trash", style: TextStyle(color: Colors.white))),
      ]));
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text("Trash", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [if (trashedDecks.isNotEmpty) TextButton.icon(onPressed: _emptyTrash,
            icon: const Icon(Icons.delete_forever_rounded, color: kError, size: 18),
            label: const Text("Empty", style: TextStyle(color: kError, fontWeight: FontWeight.w700)))]),
    bottomNav: buildBottomNav(context, 2),
    body: _restoring
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: kAccentLight), SizedBox(height: 14), Text("Restoring deck", style: TextStyle(color: kTextSecondary))]))
        : trashedDecks.isEmpty
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.delete_rounded, size: 48, color: kTextSecondary), SizedBox(height: 20),
                Text("Trash is empty", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w700))]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 20), itemCount: trashedDecks.length,
                itemBuilder: (_, i) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: kError.withAlpha(50))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    leading: const Icon(Icons.folder_rounded, color: kError, size: 22),
                    title: Text(trashedDecks[i].name, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                    subtitle: Text("${trashedDecks[i].cards.length} cards", style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      GestureDetector(onTap: () => _restore(i),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: kSuccess.withAlpha(40), borderRadius: BorderRadius.circular(10), border: Border.all(color: kSuccess.withAlpha(80))),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.restore_rounded, color: kSuccess, size: 16), SizedBox(width: 4),
                              Text("Restore", style: TextStyle(color: kSuccess, fontSize: 12, fontWeight: FontWeight.w700))]))),
                      const SizedBox(width: 8),
                      GestureDetector(onTap: () => _deletePerma(i),
                          child: Container(padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(10), border: Border.all(color: kError.withAlpha(80))),
                            child: const Icon(Icons.delete_forever_rounded, color: kError, size: 18))),
                    ]),
                  ))));
}

// ─── DECK SELECT ──────────────────────────────────────────────────────────────
class DeckSelectScreen extends StatefulWidget {
  const DeckSelectScreen({super.key});
  @override
  State<DeckSelectScreen> createState() => _DeckSelectScreenState();
}

class _DeckSelectScreenState extends State<DeckSelectScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final d = await _fs.loadDecks();
      if (mounted) setState(() { globalDecks = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar("Choose a Deck"),
    bottomNav: buildBottomNav(context, 0),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: kAccentLight))
        : globalDecks.isEmpty
            ? const Center(child: Text("No decks yet! Create flashcards first.", style: TextStyle(color: kTextSecondary)))
            : RefreshIndicator(
                onRefresh: _refresh, color: kAccentLight, backgroundColor: kCardBg,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                  itemCount: globalDecks.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeckStudyOptionsScreen(deckIndex: i))),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: kCardDecoration(),
                      child: Row(children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.folder_rounded, color: Colors.white)),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(globalDecks[i].name, style: const TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                          Text("${globalDecks[i].cards.length} cards", style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                        ])),
                        const Icon(Icons.chevron_right_rounded, color: kTextSecondary),
                      ]),
                    ),
                  ),
                )),
  );
}

// ─── DECK STUDY OPTIONS ───────────────────────────────────────────────────────
class DeckStudyOptionsScreen extends StatefulWidget {
  final int deckIndex;
  const DeckStudyOptionsScreen({super.key, required this.deckIndex});
  @override
  State<DeckStudyOptionsScreen> createState() => _DeckStudyOptionsScreenState();
}

class _DeckStudyOptionsScreenState extends State<DeckStudyOptionsScreen> {
  void _go(Deck deck, bool flashcard) {
    if (deck.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No cards in this deck!")));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => flashcard
        ? FlashcardReviewScreen(cards: List<Flashcard>.from(deck.cards), deckName: deck.name)
        : ActualQuizScreen(cards: List<Flashcard>.from(deck.cards)..shuffle(), deckName: deck.name)));
  }

  void _showLinkSheet(BuildContext context, Deck deck) async {
    final messenger = ScaffoldMessenger.of(context);
    if (globalReviewers.isEmpty) {
      try { globalReviewers = await FirestoreService().loadReviewers(); } catch (_) {}
    }
    if (!mounted) return;
    if (globalReviewers.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text("No reviewers saved yet."), backgroundColor: kWarning, behavior: SnackBarBehavior.floating));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: this.context, backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kTextSecondary.withAlpha(80), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text("Link a Reviewer", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const Text("Choose a reviewer to attach to this deck", style: TextStyle(color: kTextSecondary, fontSize: 13)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true, itemCount: globalReviewers.length,
              itemBuilder: (_, i) {
                final r = globalReviewers[i];
                final isLinked = deck.reviewerText == r.content;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await FirestoreService().saveReviewerText(deck.id, r.content);
                    setState(() {
                      final idx = globalDecks.indexWhere((d) => d.id == deck.id);
                      if (idx != -1) globalDecks[idx].reviewerText = r.content;
                    });
                    if (mounted) {
                      messenger.showSnackBar(SnackBar(
                        content: Text("\"${r.title}\" linked"),
                        backgroundColor: kSuccess,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isLinked ? const Color(0xFF00796B).withAlpha(40) : kCardBgLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isLinked ? const Color(0xFF00796B).withAlpha(100) : kAccentLight.withAlpha(30)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.menu_book_rounded, color: Color(0xFF4DB6AC), size: 20), const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.title, style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                        Text("${r.content.split(' ').length} words", style: const TextStyle(color: kTextSecondary, fontSize: 11)),
                      ])),
                      if (isLinked) const Icon(Icons.check_circle_rounded, color: kSuccess, size: 18),
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

  Widget _optionCard({required String label, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) =>
      GestureDetector(onTap: onTap, child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withAlpha(100)),
          boxShadow: [BoxShadow(color: color.withAlpha(40), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: kTextSecondary),
        ]),
      ));

  @override
  Widget build(BuildContext context) {
    final deck = globalDecks[widget.deckIndex];
    final hasReviewer = deck.reviewerText != null && deck.reviewerText!.isNotEmpty;
    return gradientScaffold(
      appBar: gradientAppBar(deck.name),
      bottomNav: buildBottomNav(context, 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Reviewer", style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (hasReviewer) ...[
            _optionCard(label: "Read Reviewer", subtitle: "Study the attached material first", icon: Icons.menu_book_rounded, color: const Color(0xFF00796B),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewerReadScreen(deck: deck)))),
            const SizedBox(height: 8),
            GestureDetector(onTap: () => _showLinkSheet(context, deck), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: kAccentLight.withAlpha(30))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.swap_horiz_rounded, color: kAccentLight, size: 16), SizedBox(width: 6),
                Text("Change Linked Reviewer", style: TextStyle(color: kAccentLight, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            )),
          ] else GestureDetector(onTap: () => _showLinkSheet(context, deck), child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF00796B).withAlpha(20), border: Border.all(color: const Color(0xFF00796B).withAlpha(60)), borderRadius: BorderRadius.circular(16)),
            child: const Row(children: [
              Icon(Icons.link_rounded, color: Color(0xFF4DB6AC), size: 22), SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Link a Reviewer", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                Text("Attach your saved reviewer notes to this deck", style: TextStyle(color: kTextSecondary, fontSize: 12)),
              ])),
              Icon(Icons.chevron_right_rounded, color: kTextSecondary),
            ]),
          )),
          const SizedBox(height: 24),
          const Text("Study Mode", style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _optionCard(label: "Flashcard Mode", subtitle: "Swipe through cards, mark right or wrong", icon: Icons.style_rounded, color: kAccentGlow, onTap: () => _go(deck, true)),
          const SizedBox(height: 12),
          _optionCard(label: "Quiz Mode", subtitle: "Mixed quiz — all question types shuffled", icon: Icons.quiz_rounded, color: const Color(0xFFE53935), onTap: () => _go(deck, false)),
        ]),
      ),
    );
  }
}

// ─── ACTUAL QUIZ ──────────────────────────────────────────────────────────────
class ActualQuizScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String deckName;
  const ActualQuizScreen({super.key, required this.cards, required this.deckName});
  @override
  State<ActualQuizScreen> createState() => _ActualQuizScreenState();
}

class _ActualQuizScreenState extends State<ActualQuizScreen> {
  int _idx = 0;
  final _ansCtrl = TextEditingController();
  String? _choice;
  List<String> _enumItems = [];
  List<TextEditingController> _enumCtrls = [];
  List<int> _skipped = [];
  bool _reviewSkipped = false;
  List<int> _skippedQ = [];

  @override
  void initState() { super.initState(); _setup(); }

  void _setup() {
    final c = widget.cards[_idx];
    _choice = null; _ansCtrl.clear();
    if (c.mode == "Enumeration") {
      _enumItems = c.answer.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      for (var x in _enumCtrls) { x.dispose(); }
      _enumCtrls = List.generate(_enumItems.length, (_) => TextEditingController());
    }
  }

  void _skip() { if (!_skipped.contains(_idx)) _skipped.add(_idx); _goNext(); }

  void _goNext() {
    if (_reviewSkipped) {
      _skippedQ.removeAt(0);
      if (_skippedQ.isNotEmpty) {
        setState(() => _idx = _skippedQ.first);
        _setup();
      } else {
        _finish();
      }
      return;
    }
    if (_idx < widget.cards.length - 1) {
      setState(() => _idx++);
      _setup();
    } else {
      final u = _skipped.where((i) => widget.cards[i].userAnswer == null).toList();
      if (u.isNotEmpty) _showSkippedDialog(u); else _finish();
    }
  }

  void _showSkippedDialog(List<int> u) => showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
    backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text("Skipped Questions", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
    content: Text("You skipped ${u.length} question(s). Answer them now?", style: const TextStyle(color: kTextSecondary, height: 1.5)),
    actions: [
      TextButton(onPressed: () { Navigator.pop(context); _finish(); }, child: const Text("Finish Anyway", style: TextStyle(color: kTextSecondary))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kAccentGlow, shape: const StadiumBorder()),
          onPressed: () {
            Navigator.pop(context);
            setState(() { _reviewSkipped = true; _skippedQ = List.from(u); _idx = _skippedQ.first; });
            _setup();
          },
          child: const Text("Answer Skipped", style: TextStyle(color: Colors.white))),
    ],
  ));

  void _finish() {
    totalQuizzesTaken++;
    totalQuestionsAnswered += widget.cards.length;
    totalCorrectAnswers += _score();
    daysStudied.add(DateTime.now().toString().substring(0, 10));
    FirestoreService().saveStats();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuizResultScreen(cards: widget.cards, deckName: widget.deckName)));
  }

  void _next() {
    final c = widget.cards[_idx];
    if (c.mode == "True or False") c.userAnswer = _choice;
    else if (c.mode == "Enumeration") c.userAnswer = _enumCtrls.map((x) => x.text.trim()).join(", ");
    else c.userAnswer = _ansCtrl.text;
    _skipped.remove(_idx); _goNext();
  }

  int _score() {
    int s = 0;
    for (final c in widget.cards) {
      if (c.mode == "Enumeration") {
        final cor = c.answer.split(",").map((x) => x.trim().toLowerCase()).toList();
        final usr = (c.userAnswer ?? "").split(",").map((x) => x.trim().toLowerCase()).toList();
        if (cor.length == usr.length && cor.every(usr.contains)) s++;
      } else if (c.userAnswer?.trim().toLowerCase() == c.answer.trim().toLowerCase()) {
        s++;
      }
    }
    return s;
  }

  bool get _canProceed {
    final c = widget.cards[_idx];
    if (c.mode == "True or False") return _choice != null;
    if (c.mode == "Enumeration") return _enumCtrls.any((x) => x.text.isNotEmpty);
    return true;
  }

  Color _modeColor(String m) => m == "Identification" ? const Color(0xFF00796B) : m == "Enumeration" ? const Color(0xFF6A1B9A) : const Color(0xFFE65100);

  Widget _answerArea(Flashcard c) {
    if (c.mode == "True or False") {
      return Row(children: ["True", "False"].map((v) {
        final sel = _choice == v;
        final col = v == "True" ? kSuccess : kError;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: v == "True" ? 8 : 0, left: v == "False" ? 8 : 0),
          child: GestureDetector(onTap: () => setState(() => _choice = v), child: AnimatedContainer(
            duration: const Duration(milliseconds: 150), height: 90, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? col.withAlpha(200) : kCardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? col : kAccentLight.withAlpha(30), width: sel ? 2 : 1),
              boxShadow: sel ? [BoxShadow(color: col.withAlpha(80), blurRadius: 14)] : [],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(v == "True" ? Icons.check_circle_rounded : Icons.cancel_rounded, color: sel ? Colors.white : kTextSecondary, size: 32),
              const SizedBox(height: 6),
              Text(v, style: TextStyle(color: sel ? Colors.white : kTextSecondary, fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
          )),
        ));
      }).toList());
    }

    if (c.mode == "Enumeration") {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Fill in each blank:", style: TextStyle(color: kTextSecondary, fontSize: 13)),
        const SizedBox(height: 12),
        ...List.generate(_enumItems.length, (i) => Container(margin: const EdgeInsets.only(bottom: 10), child: Row(children: [
          Container(width: 28, height: 28, alignment: Alignment.center,
            decoration: BoxDecoration(gradient: kButtonGradient, borderRadius: BorderRadius.circular(8)),
            child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _enumCtrls[i], style: const TextStyle(color: kTextPrimary), onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Item ${i+1}", hintStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
              filled: true, fillColor: kCardBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
            ))),
        ]))),
      ]);
    }

    return TextField(
      controller: _ansCtrl,
      style: const TextStyle(color: kTextPrimary, fontSize: 16),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: "Type your answer", hintStyle: const TextStyle(color: kTextSecondary),
        filled: true, fillColor: kCardBg, contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kAccentLight, width: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cards[_idx];
    final mc = _modeColor(c.mode);
    return gradientScaffold(body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.close_rounded, color: kTextPrimary, size: 20))),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.deckName, style: const TextStyle(color: kTextSecondary, fontSize: 12))),
      ])),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Container(
        width: double.infinity, padding: const EdgeInsets.all(28), decoration: kCardDecoration(),
        child: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: mc.withAlpha(60), borderRadius: BorderRadius.circular(20)),
            child: Text(c.mode, style: TextStyle(color: mc, fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          Text(c.question, style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        ]),
      )),
      const SizedBox(height: 20),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20), child: _answerArea(c))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_reviewSkipped ? "Reviewing skipped (${_skippedQ.length} left)" : "Question ${_idx + 1} of ${widget.cards.length}",
          style: const TextStyle(color: kTextSecondary, fontSize: 12)),
        if (_skipped.isNotEmpty && !_reviewSkipped) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: kWarning.withAlpha(40), borderRadius: BorderRadius.circular(10), border: Border.all(color: kWarning.withAlpha(80))),
          child: Text("${_skipped.length} skipped", style: const TextStyle(color: kWarning, fontSize: 11, fontWeight: FontWeight.w700))),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), child: Column(children: [
        Row(children: [
          if (_idx > 0 && !_reviewSkipped) ...[
            Expanded(flex: 1, child: GestureDetector(
              onTap: () { setState(() => _idx--); _setup(); },
              child: Container(height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: kAccentLight.withAlpha(60)), borderRadius: BorderRadius.circular(16)),
                child: const Text("Back", style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600))))),
            const SizedBox(width: 12),
          ],
          Expanded(flex: 2, child: GestureDetector(
            onTap: _canProceed ? _next : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: _canProceed ? kButtonGradient : null,
                color: _canProceed ? null : kCardBgLight,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _canProceed ? [BoxShadow(color: kAccentGlow.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))] : [],
              ),
              child: Text(
                _reviewSkipped ? (_skippedQ.length > 1 ? "Next Skipped" : "Finish") : (_idx < widget.cards.length - 1 ? "Next" : "Finish"),
                style: TextStyle(color: _canProceed ? Colors.white : kTextSecondary, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          )),
        ]),
        if (!_reviewSkipped) ...[
          const SizedBox(height: 10),
          GestureDetector(onTap: _skip, child: Container(
            height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: kWarning.withAlpha(80), width: 1.5), borderRadius: BorderRadius.circular(14), color: kWarning.withAlpha(15)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.skip_next_rounded, color: kWarning, size: 18), SizedBox(width: 6),
              Text("Skip", style: TextStyle(color: kWarning, fontWeight: FontWeight.w600, fontSize: 13)),
            ]))),
        ],
      ])),
    ])));
  }
}

// ─── FLASHCARD REVIEW ─────────────────────────────────────────────────────────
class FlashcardReviewScreen extends StatefulWidget {
  final List<Flashcard> cards;
  final String deckName;
  const FlashcardReviewScreen({super.key, required this.cards, required this.deckName});
  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen> with TickerProviderStateMixin {
  late List<Flashcard> _deck;
  List<Flashcard> _skipped = [], _known = [], _unknown = [];
  int _idx = 0;
  bool _flipped = false, _shuffled = false, _swiping = false;
  late AnimationController _flipCtrl, _swipeCtrl;
  late Animation<double> _flipAnim;
  late Animation<Offset> _swipeAnim;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _deck = List<Flashcard>.from(widget.cards);
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));
    _swipeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _swipeAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_swipeCtrl);
  }

  @override
  void dispose() { _flipCtrl.dispose(); _swipeCtrl.dispose(); super.dispose(); }

  void _flip() { if (_swiping) return; _flipped ? _flipCtrl.reverse() : _flipCtrl.forward(); setState(() => _flipped = !_flipped); }
  void _resetFlip() { _flipCtrl.reset(); setState(() { _flipped = false; _drag = Offset.zero; _swiping = false; }); }

  void _onDragUpdate(DragUpdateDetails d) => setState(() { _drag += Offset(d.delta.dx, d.delta.dy * 0.3); _swiping = true; });
  void _onDragEnd(DragEndDetails _) {
    if (_drag.dx > 80) _animateSwipe(const Offset(2, 0), () => _mark('known'));
    else if (_drag.dx < -80) _animateSwipe(const Offset(-2, 0), () => _mark('unknown'));
    else setState(() { _drag = Offset.zero; _swiping = false; });
  }

  void _animateSwipe(Offset t, VoidCallback done) {
    final w = MediaQuery.of(context).size.width;
    _swipeAnim = Tween<Offset>(begin: _drag, end: Offset(t.dx * w, t.dy * 80)).animate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOut));
    _swipeCtrl.forward(from: 0).then((_) { done(); _swipeCtrl.reset(); });
  }

  void _mark(String r) {
    if (_idx >= _deck.length) return;
    final c = _deck[_idx];
    if (r == 'known') _known.add(c); else if (r == 'unknown') _unknown.add(c); else _skipped.add(c);
    _idx + 1 >= _deck.length
        ? (_skipped.isNotEmpty ? _showSkippedDialog() : _showResults())
        : setState(() { _idx++; _resetFlip(); });
  }

  void _showSkippedDialog() => showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
    backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text("Skipped Cards", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
    content: Text("You skipped ${_skipped.length} card(s). Review them now?", style: const TextStyle(color: kTextSecondary)),
    actions: [
      TextButton(onPressed: () { Navigator.pop(context); _showResults(); }, child: const Text("Skip and Finish", style: TextStyle(color: kTextSecondary))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kAccentGlow, shape: const StadiumBorder()),
          onPressed: () {
            Navigator.pop(context);
            setState(() { _deck = List.from(_skipped); _skipped = []; _idx = 0; });
            _resetFlip();
          },
          child: const Text("Review Skipped", style: TextStyle(color: Colors.white))),
    ],
  ));

  void _showResults() {
    totalFlashcardSessions++;
    totalFlashcardsKnown += _known.length;
    totalFlashcardsUnknown += _unknown.length;
    totalCardsStudied += _known.length + _unknown.length + _skipped.length;
    daysStudied.add(DateTime.now().toString().substring(0, 10));
    FirestoreService().saveStats();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FlashcardResultScreen(known: _known, unknown: _unknown, skipped: _skipped, deckName: widget.deckName)));
  }

Widget _face({required String label, required String content, required String hint, required bool flipped, Color? tint, String? mode}) {
  final cols = flipped ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)] : [kCardBg, kCardBgLight];

  // Mode badge config — only shown on the front (question) side
  Color _modeColor(String m) => m == "Identification"
      ? const Color(0xFF00796B)
      : m == "Enumeration"
          ? const Color(0xFF6A1B9A)
          : const Color(0xFFE65100);

  IconData _modeIcon(String m) => m == "Identification"
      ? Icons.text_fields_rounded
      : m == "Enumeration"
          ? Icons.format_list_numbered_rounded
          : Icons.toggle_on_rounded;

  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: tint?.withAlpha(160) ?? (flipped ? kSuccess.withAlpha(80) : kAccentLight.withAlpha(40)), width: tint != null ? 2 : 1),
      boxShadow: [BoxShadow(color: (tint ?? (flipped ? kSuccess : kAccentGlow)).withAlpha(60), blurRadius: 25, spreadRadius: 2)],
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      // QUESTION / ANSWER label chip
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: (tint ?? (flipped ? kSuccess : kAccentGlow)).withAlpha(60), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, color: tint ?? (flipped ? kSuccess : kAccentLight), fontWeight: FontWeight.w700, letterSpacing: 2)),
      ),
      // Mode badge — only on the front (question) side
      if (!flipped && mode != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _modeColor(mode).withAlpha(40),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _modeColor(mode).withAlpha(120)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_modeIcon(mode), color: _modeColor(mode), size: 13),
            const SizedBox(width: 5),
            Text(mode, style: TextStyle(color: _modeColor(mode), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(content, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kTextPrimary), textAlign: TextAlign.center)),
      const SizedBox(height: 24),
      Text(hint, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
    ]),
  );
}

  @override
  Widget build(BuildContext context) {
    if (_deck.isEmpty) {
      return gradientScaffold(appBar: gradientAppBar("Flashcard Review"),
        body: const Center(child: Text("No cards to review!", style: TextStyle(color: kTextSecondary))));
    }
    final c = _deck[_idx];
    final kHint = _drag.dx > 40, uHint = _drag.dx < -40;
    return gradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: Text(widget.deckName, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: "Shuffle",
            onPressed: () {
              setState(() { _deck.shuffle(); _idx = 0; _shuffled = !_shuffled; });
              _resetFlip();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_shuffled ? "Cards shuffled" : "Cards reset"),
                backgroundColor: kAccentGlow,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ));
            },
            icon: Icon(Icons.shuffle_rounded, color: _shuffled ? kAccentLight : kTextSecondary, size: 22),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNav: buildBottomNav(context, 0),
      body: Padding(padding: const EdgeInsets.fromLTRB(20, 80, 20, 12), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          AnimatedOpacity(opacity: uHint ? 1.0 : 0.0, duration: const Duration(milliseconds: 150),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(20), border: Border.all(color: kError.withAlpha(100))),
              child: const Row(children: [Icon(Icons.close_rounded, color: kError, size: 16), SizedBox(width: 4), Text("Wrong", style: TextStyle(color: kError, fontWeight: FontWeight.w700, fontSize: 12))]))),
          AnimatedOpacity(opacity: kHint ? 1.0 : 0.0, duration: const Duration(milliseconds: 150),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: kSuccess.withAlpha(40), borderRadius: BorderRadius.circular(20), border: Border.all(color: kSuccess.withAlpha(100))),
              child: const Row(children: [Text("Right", style: TextStyle(color: kSuccess, fontWeight: FontWeight.w700, fontSize: 12)), SizedBox(width: 4), Icon(Icons.check_rounded, color: kSuccess, size: 16)]))),
        ]),
        const SizedBox(height: 8),
        Expanded(child: GestureDetector(
          onTap: _flip, onHorizontalDragUpdate: _onDragUpdate, onHorizontalDragEnd: _onDragEnd,
          child: AnimatedBuilder(animation: Listenable.merge([_flipAnim, _swipeCtrl]), builder: (_, __) {
            final so = _swiping && _swipeCtrl.isAnimating ? _swipeAnim.value : _drag;
            final tilt = so.dx / 400, angle = _flipAnim.value * pi, front = angle < pi / 2;
            final tint = so.dx > 40 ? kSuccess : so.dx < -40 ? kError : null;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..setTranslationRaw(so.dx, so.dy, 0)..rotateZ(tilt)..setEntry(3, 2, 0.001)..rotateY(angle),
              child: front
                  ? _face(label: "QUESTION", content: c.question, hint: "Tap to reveal answer", flipped: false, tint: tint, mode: c.mode)
                  : Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(pi),
                      child: _face(label: "ANSWER", content: c.answer, hint: "Tap to flip back", flipped: true, tint: tint)),
            );
          }),
        )),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => _mark('unknown'), child: Column(children: [
            Container(height: 60,
              decoration: BoxDecoration(color: kError.withAlpha(40), borderRadius: BorderRadius.circular(18), border: Border.all(color: kError.withAlpha(100)), boxShadow: [BoxShadow(color: kError.withAlpha(40), blurRadius: 8, offset: const Offset(0, 3))]),
              child: const Center(child: Icon(Icons.close_rounded, color: kError, size: 30))),
            const SizedBox(height: 6), const Text("Wrong", style: TextStyle(color: kError, fontSize: 12, fontWeight: FontWeight.w700)),
          ]))),
          const SizedBox(width: 8),
          Column(children: [
            GestureDetector(onTap: () => _mark('skip'), child: Container(width: 60, height: 60,
              decoration: BoxDecoration(color: kWarning.withAlpha(30), borderRadius: BorderRadius.circular(18), border: Border.all(color: kWarning.withAlpha(100))),
              child: const Center(child: Icon(Icons.skip_next_rounded, color: kWarning, size: 28)))),
            const SizedBox(height: 6), const Text("Skip", style: TextStyle(color: kWarning, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(onTap: () => _mark('known'), child: Column(children: [
            Container(height: 60,
              decoration: BoxDecoration(color: kSuccess.withAlpha(40), borderRadius: BorderRadius.circular(18), border: Border.all(color: kSuccess.withAlpha(100)), boxShadow: [BoxShadow(color: kSuccess.withAlpha(40), blurRadius: 8, offset: const Offset(0, 3))]),
              child: const Center(child: Icon(Icons.check_rounded, color: kSuccess, size: 30))),
            const SizedBox(height: 6), const Text("Right", style: TextStyle(color: kSuccess, fontSize: 12, fontWeight: FontWeight.w700)),
          ]))),
        ]),
        const SizedBox(height: 16),
      ])),
    );
  }
}

// ─── FLASHCARD RESULT ─────────────────────────────────────────────────────────
class FlashcardResultScreen extends StatelessWidget {
  final List<Flashcard> known, unknown, skipped;
  final String deckName;
  const FlashcardResultScreen({super.key, required this.known, required this.unknown, required this.skipped, required this.deckName});

  @override
  Widget build(BuildContext context) {
    final total = known.length + unknown.length + skipped.length;
    final pct = total == 0 ? 0 : (known.length / total * 100).toInt();
    final sc = pct >= 80 ? kSuccess : pct >= 50 ? kWarning : kError;

    Widget chip(String l, int n, Color c, IconData icon) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withAlpha(80))),
      child: Column(children: [
        Icon(icon, color: c, size: 20), const SizedBox(height: 4),
        Text("$n", style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(l, style: const TextStyle(color: kTextSecondary, fontSize: 10), textAlign: TextAlign.center),
      ])));

    Widget row(Flashcard c, Color col) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withAlpha(60))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.question, style: const TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(c.answer, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
      ]));

    return gradientScaffold(body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [sc.withAlpha(60), sc.withAlpha(20)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: sc.withAlpha(100)),
          ),
          child: Column(children: [
            Text("$pct%", style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: sc)),
            Text("$total cards reviewed", style: const TextStyle(color: kTextSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            Text(pct >= 80 ? "Excellent!" : pct >= 50 ? "Good effort!" : "Keep studying!", style: TextStyle(color: sc, fontWeight: FontWeight.w700, fontSize: 16)),
          ])),
        const SizedBox(height: 20),
        Row(children: [
          chip("Right", known.length, kSuccess, Icons.check_circle_rounded),
          const SizedBox(width: 10),
          chip("Wrong", unknown.length, kError, Icons.cancel_rounded),
          const SizedBox(width: 10),
          chip("Skipped", skipped.length, kWarning, Icons.skip_next_rounded),
        ]),
        if (known.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text("Right (${known.length})", style: const TextStyle(color: kSuccess, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...known.map((c) => row(c, kSuccess)),
        ],
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text("Wrong (${unknown.length})", style: const TextStyle(color: kError, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...unknown.map((c) => row(c, kError)),
        ],
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text("Skipped (${skipped.length})", style: const TextStyle(color: kWarning, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...skipped.map((c) => row(c, kWarning)),
        ],
        const SizedBox(height: 16),
        glowButton(
          label: "Retry",
          onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
              FlashcardReviewScreen(cards: List<Flashcard>.from([...known, ...unknown, ...skipped])..shuffle(), deckName: deckName))),
          icon: Icons.refresh_rounded, color: kAccentGlow, height: 52),
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: 12),
          glowButton(
            label: "Retry Wrong Cards",
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
                FlashcardReviewScreen(cards: List<Flashcard>.from(unknown), deckName: deckName))),
            icon: Icons.close_rounded, color: kError, height: 52),
        ],
        const SizedBox(height: 12),
        glowButton(label: "Back to Home", onTap: () => Navigator.of(context).popUntil((r) => r.isFirst), icon: Icons.home_rounded, color: const Color(0xFF1565C0), height: 52),
        const SizedBox(height: 20),
      ]),
    )));
  }
}

// ─── QUIZ RESULT ──────────────────────────────────────────────────────────────
class QuizResultScreen extends StatelessWidget {
  final List<Flashcard> cards;
  final String deckName;
  const QuizResultScreen({super.key, required this.cards, required this.deckName});

  bool _ok(Flashcard c) {
    if (c.mode == "Enumeration") {
      final cor = c.answer.split(",").map((s) => s.trim().toLowerCase()).toList();
      final usr = (c.userAnswer ?? "").split(",").map((s) => s.trim().toLowerCase()).toList();
      return cor.length == usr.length && cor.every(usr.contains);
    }
    return c.userAnswer?.trim().toLowerCase() == c.answer.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final score = cards.where(_ok).length;
    final pct = score / cards.length * 100;
    final sc = pct >= 80 ? kSuccess : pct >= 50 ? kWarning : kError;
    return gradientScaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
      const SizedBox(height: 10),
      Container(width: double.infinity, padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [sc.withAlpha(60), sc.withAlpha(20)]),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: sc.withAlpha(100)),
        ),
        child: Column(children: [
          Text("${pct.toInt()}%", style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: sc)),
          Text("$score out of ${cards.length} correct", style: const TextStyle(color: kTextSecondary, fontSize: 15)),
          const SizedBox(height: 8),
          Text(pct >= 80 ? "Excellent!" : pct >= 50 ? "Good effort!" : "Keep studying!", style: TextStyle(color: sc, fontWeight: FontWeight.w700, fontSize: 16)),
        ])),
      const SizedBox(height: 24),
      const Align(alignment: Alignment.centerLeft,
        child: Text("Review Answers", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800))),
      const SizedBox(height: 12),
      ...cards.map((c) {
        final ok = _ok(c);
        return Container(
          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kCardBg, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ok ? kSuccess.withAlpha(100) : kError.withAlpha(100))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(8)),
                child: Text(c.mode, style: const TextStyle(color: kTextSecondary, fontSize: 11))),
              const Spacer(),
              Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? kSuccess : kError, size: 20),
            ]),
            const SizedBox(height: 8),
            Text(c.question, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text("Your answer: ${c.userAnswer ?? 'No answer'}", style: TextStyle(color: ok ? kSuccess : kError, fontSize: 13)),
            if (!ok) ...[
              const SizedBox(height: 2),
              Text("Correct: ${c.answer}", style: const TextStyle(color: kSuccess, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ]));
      }),
      const SizedBox(height: 24),
      glowButton(
        label: "Retry Quiz",
        onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
            ActualQuizScreen(cards: List<Flashcard>.from(cards)..forEach((c) => c.userAnswer = null)..shuffle(), deckName: deckName))),
        icon: Icons.refresh_rounded, color: kAccentGlow, height: 52),
      const SizedBox(height: 12),
      glowButton(label: "Back to Home", onTap: () => Navigator.of(context).popUntil((r) => r.isFirst), icon: Icons.home_rounded, height: 52),
      const SizedBox(height: 20),
    ]))));
  }
}

// ─── REVIEWER LIST ────────────────────────────────────────────────────────────
class ReviewerListScreen extends StatefulWidget {
  const ReviewerListScreen({super.key});
  @override
  State<ReviewerListScreen> createState() => _ReviewerListScreenState();
}

class _ReviewerListScreenState extends State<ReviewerListScreen> {
  final _fs = FirestoreService();
  bool _loading = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final r = await _fs.loadReviewers();
      if (mounted) setState(() { globalReviewers = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Reviewer r) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Delete Reviewer?", style: TextStyle(color: kTextPrimary)),
      content: Text("\"${r.title}\" will be permanently deleted.", style: const TextStyle(color: kTextSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: kTextSecondary))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kError, shape: const StadiumBorder()),
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Delete", style: TextStyle(color: Colors.white))),
      ],
    ));
    if (ok != true) return;
    await _fs.deleteReviewer(r.id);
    setState(() => globalReviewers.removeWhere((x) => x.id == r.id));
  }

  String _ago(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0) return "${d.inDays}d ago";
    if (d.inHours > 0) return "${d.inHours}h ago";
    if (d.inMinutes > 0) return "${d.inMinutes}m ago";
    return "Just now";
  }

  @override
  Widget build(BuildContext context) {
    final colors = [const Color(0xFF7C3AED), const Color(0xFF1565C0), const Color(0xFF00796B), const Color(0xFFE65100), const Color(0xFFAD1457)];
    return gradientScaffold(
      appBar: gradientAppBar("My Reviewers"), bottomNav: buildBottomNav(context, 0),
      body: _loading ? const Center(child: CircularProgressIndicator(color: kAccentLight))
          : Stack(children: [
        globalReviewers.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: kCardBg, shape: BoxShape.circle, border: Border.all(color: kAccentLight.withAlpha(40))),
                  child: const Icon(Icons.menu_book_rounded, color: kAccentLight, size: 48)),
                const SizedBox(height: 16),
                const Text("No reviewers yet", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text("Tap below to add your first reviewer", style: TextStyle(color: kTextSecondary, fontSize: 13)),
              ]))
            : RefreshIndicator(onRefresh: _refresh, color: kAccentLight, backgroundColor: kCardBg,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 100),
                  itemCount: globalReviewers.length,
                  itemBuilder: (_, i) {
                    final r = globalReviewers[i];
                    final col = colors[i % colors.length];
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => ViewReviewerScreen(reviewer: r)));
                        setState(() {});
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kCardBg, kCardBgLight]),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: col.withAlpha(60)),
                          boxShadow: [BoxShadow(color: col.withAlpha(30), blurRadius: 16, offset: const Offset(0, 4))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 4, decoration: BoxDecoration(color: col, borderRadius: const BorderRadius.vertical(top: Radius.circular(20)))),
                          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 12, 14), child: Row(children: [
                            Container(width: 44, height: 44,
                              decoration: BoxDecoration(color: col.withAlpha(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withAlpha(80))),
                              child: Icon(Icons.article_rounded, color: col, size: 22)),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.title, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.schedule_rounded, color: kTextSecondary, size: 12),
                                const SizedBox(width: 4),
                                Text(_ago(r.createdAt), style: const TextStyle(color: kTextSecondary, fontSize: 11)),
                                if (r.linkedDeckId != null) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.link_rounded, color: kAccentLight, size: 12),
                                  const SizedBox(width: 4),
                                  const Text("Linked", style: TextStyle(color: kAccentLight, fontSize: 11)),
                                ],
                              ]),
                            ])),
                            PopupMenuButton<String>(
                              color: kCardBg,
                              icon: const Icon(Icons.more_vert_rounded, color: kTextSecondary),
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => AddReviewerScreen(existing: r)));
                                  _refresh();
                                } else if (v == 'delete') {
                                  await _delete(r);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, color: kAccentLight, size: 16), SizedBox(width: 10), Text("Edit", style: TextStyle(color: kTextPrimary))])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, color: kError, size: 16), SizedBox(width: 10), Text("Delete", style: TextStyle(color: kError))])),
                              ],
                            ),
                          ])),
                          if (r.content.isNotEmpty) Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                            child: Text(
                              r.content.length > 100 ? r.content.substring(0, 100) : r.content,
                              style: const TextStyle(color: kTextSecondary, fontSize: 13, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            )),
                        ]),
                      ),
                    );
                  },
                )),
        Positioned(bottom: 20, left: 20, right: 20,
          child: glowButton(
            label: "Add Reviewer",
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddReviewerScreen()));
              _refresh();
            },
            icon: Icons.add_rounded,
            color: const Color(0xFF00796B),
          )),
      ]),
    );
  }
}

// ─── ADD / EDIT REVIEWER ──────────────────────────────────────────────────────
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
  String? _deckId;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _titleCtrl.text = widget.existing!.title;
      _contentCtrl.text = widget.existing!.content;
      _deckId = widget.existing!.linkedDeckId;
    }
  }

  @override
  void dispose() { _titleCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final t = _titleCtrl.text.trim(), c = _contentCtrl.text.trim();
    if (t.isEmpty || c.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill in title and content."), backgroundColor: kError));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _fs.updateReviewer(widget.existing!.id, t, c, linkedDeckId: _deckId);
        final i = globalReviewers.indexWhere((r) => r.id == widget.existing!.id);
        if (i != -1) globalReviewers[i] = Reviewer(id: widget.existing!.id, title: t, content: c, linkedDeckId: _deckId, createdAt: widget.existing!.createdAt);
        if (_deckId != null) {
          await _fs.saveReviewerText(_deckId!, c);
          final di = globalDecks.indexWhere((d) => d.id == _deckId);
          if (di != -1) globalDecks[di].reviewerText = c;
        }
      } else {
        final id = await _fs.addReviewer(t, c, linkedDeckId: _deckId);
        globalReviewers.insert(0, Reviewer(id: id, title: t, content: c, linkedDeckId: _deckId, createdAt: DateTime.now()));
        if (_deckId != null) {
          await _fs.saveReviewerText(_deckId!, c);
          final di = globalDecks.indexWhere((d) => d.id == _deckId);
          if (di != -1) globalDecks[di].reviewerText = c;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? "Reviewer updated" : "Reviewer saved"),
          backgroundColor: kSuccess, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: kError, behavior: SnackBarBehavior.floating));
      }
    }
  }

  InputDecoration _dec(String hint, IconData? icon) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: kTextSecondary),
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    prefixIcon: icon != null ? Icon(icon, color: kAccentLight, size: 20) : null,
  );

  @override
  Widget build(BuildContext context) => gradientScaffold(
    appBar: gradientAppBar(_isEdit ? "Edit Reviewer" : "New Reviewer"),
    body: Column(children: [
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 90, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF00796B).withAlpha(30), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF00796B).withAlpha(80))),
          child: const Row(children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFF4DB6AC), size: 18), SizedBox(width: 10),
            Expanded(child: Text("Add your study notes or reviewer material. You can read it before taking a quiz.", style: TextStyle(color: kTextSecondary, fontSize: 13, height: 1.4))),
          ])),
        const SizedBox(height: 22),
        const Text("Title", style: TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: kAccentLight.withAlpha(30))),
          child: TextField(controller: _titleCtrl, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700), decoration: _dec("e.g. Chapter 5 Photosynthesis", Icons.title_rounded))),
        const SizedBox(height: 20),
        const Text("Link to Flashcard Deck (optional)", style: TextStyle(color: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: kAccentLight.withAlpha(30))),
          child: DropdownButton<String?>(
            value: _deckId, isExpanded: true, dropdownColor: kCardBg, underline: const SizedBox(),
            style: const TextStyle(color: kTextPrimary, fontSize: 14),
            hint: const Text("No deck linked", style: TextStyle(color: kTextSecondary, fontSize: 13)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text("No deck linked", style: TextStyle(color: kTextSecondary, fontSize: 13))),
              ...globalDecks.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setState(() => _deckId = v),
          )),
        const SizedBox(height: 20),
        const Text("Content", style: TextStyle(col
        or: kTextSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(decoration: BoxDecoration(color: kCardBgLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: kAccentLight.withAlpha(30))),
          child: TextField(
            controller: _contentCtrl, maxLines: 16,
            style: const TextStyle(color: kTextPrimary, fontSize: 14, height: 1.7),
            decoration: const InputDecoration(
              hintText: "Type or paste your reviewer notes here",
              hintStyle: TextStyle(color: kTextSecondary, fontSize: 13, height: 1.6),
              border: InputBorder.none, contentPadding: EdgeInsets.all(16),
            ))),
      ]))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: _saving
            ? const Center(child: CircularProgressIndicator(color: kAccentLight))
            : glowButton(
                label: _isEdit ? "Update Reviewer" : "Save Reviewer",
                onTap: _save,
                icon: _isEdit ? Icons.save_rounded : Icons.cloud_upload_rounded,
                color: const Color(0xFF00796B),
              )),
    ]),
  );
}

// ─── VIEW REVIEWER ────────────────────────────────────────────────────────────
class ViewReviewerScreen extends StatelessWidget {
  final Reviewer reviewer;
  const ViewReviewerScreen({super.key, required this.reviewer});
  @override
  Widget build(BuildContext context) => _readScreen(context, reviewer.title, reviewer.content);
}

// ─── REVIEWER READ ────────────────────────────────────────────────────────────
class ReviewerReadScreen extends StatelessWidget {
  final Deck deck;
  const ReviewerReadScreen({super.key, required this.deck});
  @override
  Widget build(BuildContext context) => _readScreen(context, deck.name, deck.reviewerText ?? '');
}

Widget _readScreen(BuildContext context, String title, String content) => gradientScaffold(
  appBar: AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    iconTheme: const IconThemeData(color: kTextPrimary),
    title: const Text("Reviewer", style: TextStyle(color: kTextSecondary, fontSize: 14)),
    actions: [
      Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: kSuccess.withAlpha(40), borderRadius: BorderRadius.circular(12)),
        child: const Text("READ MODE", style: TextStyle(color: kSuccess, fontSize: 11, fontWeight: FontWeight.w700))))),
    ]),
  body: Column(children: [
    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 80, 24, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
      const SizedBox(height: 16),
      Divider(color: kAccentLight.withAlpha(30), height: 1),
      const SizedBox(height: 16),
      SelectableText(content, style: const TextStyle(color: kTextPrimary, fontSize: 16, height: 1.85)),
      const SizedBox(height: 40),
    ]))),
    Padding(padding: const EdgeInsets.all(20),
      child: glowButton(label: "Done Reading", onTap: () => Navigator.pop(context), icon: null, color: kSuccess)),
  ]),
);