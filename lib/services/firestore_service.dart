import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> createDeck(String userId, String deckName) async {
    final ref = await _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .add({
      'name': deckName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<QuerySnapshot> getDecks(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> deleteDeck(String userId, String deckId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckId)
        .delete();
  }

  Future<void> addCard(String userId, String deckId,
      String question, String answer) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckId)
        .collection('cards')
        .add({
      'question': question,
      'answer': answer,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getCards(String userId, String deckId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckId)
        .collection('cards')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> updateCard(String userId, String deckId, String cardId,
      String question, String answer) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckId)
        .collection('cards')
        .doc(cardId)
        .update({'question': question, 'answer': answer});
  }

  Future<void> deleteCard(
      String userId, String deckId, String cardId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('decks')
        .doc(deckId)
        .collection('cards')
        .doc(cardId)
        .delete();
  }
}