import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Metodo per inviare un messaggio
  Future<void> sendMessage(
      String receiverId,
      String message, {
        required String senderId,
        required bool isSticker,
      }) async {
    try {
      await _firestore.collection('messages').add({
        'senderId': senderId,
        'receiverId': receiverId, // Cambiato da receiverUserId a receiverId
        'message': message,
        'isSticker': isSticker,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('Messaggio inviato: $message');
      print('Mittente: $senderId, Destinatario: $receiverId');
    } catch (e) {
      print('Errore nell\'invio del messaggio: $e');
    }
  }

  // Metodo per recuperare i messaggi
  Stream<QuerySnapshot> getMessages(String receiverId, String senderId) {
    return _firestore
        .collection('messages')
        .where('receiverId', whereIn: [receiverId, senderId]) // Modificato
        .where('senderId', whereIn: [receiverId, senderId]) // Modificato
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}