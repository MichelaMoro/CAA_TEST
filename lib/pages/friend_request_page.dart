import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendRequestsPage extends StatelessWidget {
  const FriendRequestsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(child: Text('Utente non autenticato'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Richieste di Amicizia'),
        backgroundColor: Colors.teal,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('friendRequests')
            .doc(currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Errore durante il caricamento'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = (snapshot.data?.data() as Map<String, dynamic>? ?? {})['requests'] as List<dynamic>?;

          if (requests == null || requests.isEmpty) {
            return const Center(child: Text('Nessuna richiesta ricevuta.'));
          }

          return ListView(
            children: requests.map((uid) {
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('Caricamento...'));
                  }

                  final user = userSnapshot.data?.data() as Map<String, dynamic>?;
                  final nome = user?['nome'] ?? 'N/A';
                  final cognome = user?['cognome'] ?? 'N/A';
                  final displayName = '$cognome $nome';

                  return Card(
                    child: ListTile(
                      title: Text(displayName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              await _acceptRequest(currentUser.uid, uid);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Richiesta accettata!')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () async {
                              await _rejectRequest(currentUser.uid, uid);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Richiesta rifiutata!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _acceptRequest(String currentUserId, String senderId) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Riferimenti ai documenti di utente e mittente
      final userDocRef = firestore.collection('users').doc(currentUserId);
      final senderDocRef = firestore.collection('users').doc(senderId);

      // Ottieni i dati di entrambi gli utenti
      final userDoc = await userDocRef.get();
      final senderDoc = await senderDocRef.get();

      final userData = userDoc.data() as Map<String, dynamic>;
      final senderData = senderDoc.data() as Map<String, dynamic>;

      // Aggiorna la lista degli amici del destinatario (utente corrente)
      await userDocRef.update({
        'friends': FieldValue.arrayUnion([senderId]),
      });

      // Aggiorna la lista degli amici del mittente
      await senderDocRef.update({
        'friends': FieldValue.arrayUnion([currentUserId]),
      });

      // Aggiungi gli utenti BCC del mittente agli amici dell'utente corrente
      final senderBccUsers = senderData['bccUsers'] as List<dynamic>? ?? [];
      await userDocRef.update({
        'friends': FieldValue.arrayUnion(senderBccUsers),
      });

      // Aggiungi gli utenti BCC del destinatario agli amici del mittente
      final userBccUsers = userData['bccUsers'] as List<dynamic>? ?? [];
      await senderDocRef.update({
        'friends': FieldValue.arrayUnion(userBccUsers),
      });

      // Rimuove la richiesta dalla lista delle richieste pendenti
      await firestore.collection('friendRequests').doc(currentUserId).update({
        'requests': FieldValue.arrayRemove([senderId]),
      });

      // Decrementa il contatore delle richieste di amicizia per l'utente destinatario
      await _decrementFriendRequestCount(currentUserId);

      print('Richiesta accettata con successo. Amicizia aggiornata.');
    } catch (e) {
      print('Errore nell\'accettazione della richiesta: $e');
      throw 'Impossibile accettare la richiesta.';
    }
  }

  Future<void> _rejectRequest(String currentUserId, String senderId) async {
    try {
      // Rimuove la richiesta dalla lista delle richieste pendenti
      await FirebaseFirestore.instance.collection('friendRequests').doc(currentUserId).update({
        'requests': FieldValue.arrayRemove([senderId]),
      });

      // Decrementa il contatore delle richieste di amicizia per l'utente destinatario
      await _decrementFriendRequestCount(currentUserId);

      print('Richiesta rifiutata.');
    } catch (e) {
      print('Errore nel rifiutare la richiesta: $e');
      throw 'Impossibile rifiutare la richiesta.';
    }
  }

  // Funzione per decrementare il contatore delle richieste
  Future<void> _decrementFriendRequestCount(String userId) async {
    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userId);
      await userDocRef.update({
        'friendRequestCount': FieldValue.increment(-1), // Decrementa il contatore
      });
    } catch (e) {
      print('Errore nel decrementare il contatore delle richieste: $e');
    }
  }
}
