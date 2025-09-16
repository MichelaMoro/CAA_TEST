import 'package:cloud_firestore/cloud_firestore.dart';
class Message {
  final String senderId;
  final String senderEmail;
  final String receiverId;
  final Timestamp timestamp;
  final String message;
  final bool isSticker;

  Message({
    required this.senderId,
    required this.senderEmail,
    required this.receiverId,
    required this.timestamp,
    required this.message,
    this.isSticker = false, // Campo opzionale
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderEmail': senderEmail,
      'receiverId': receiverId,
      'timestamp': timestamp,
      'message': message,
      'isSticker': isSticker, // Aggiungi il campo isSticker
    };
  }


}