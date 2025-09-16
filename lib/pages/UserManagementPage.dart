import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserChatManagementPage extends StatefulWidget {
  final String receiverUserId; // UID dell'utente con BCC
  final String tutorUserId; // UID del tutor

  const UserChatManagementPage({
    super.key,
    required this.receiverUserId,
    required this.tutorUserId,
  });

  @override
  _UserChatManagementPageState createState() =>
      _UserChatManagementPageState();
}

class _UserChatManagementPageState extends State<UserChatManagementPage> {
  Map<String, bool> _userSelection = {}; // Stato della selezione (UID -> bool)
  Map<String, String> _userDisplayNames = {}; // Mappa UID -> Nome visualizzato (Nome Cognome o email)
  List<String> _tutorFriends = []; // Lista degli amici del tutor
  List<String> _tutorBccUsers = []; // Lista degli utenti BCC del tutor

  @override
  void initState() {
    super.initState();
    _fetchTutorFriendsAndBccUsersAndContacts();
  }

  Future<void> _fetchTutorFriendsAndBccUsersAndContacts() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Recupera il documento del tutor
      final tutorDoc = await firestore.collection('users').doc(widget.tutorUserId).get();

      // Recupera la lista degli amici del tutor
      _tutorFriends = List<String>.from(tutorDoc.data()?['friends'] ?? []);

      // Recupera la lista degli utenti BCC del tutor
      _tutorBccUsers = List<String>.from(tutorDoc.data()?['bccUsers'] ?? []);

      // Recupera gli allowedContacts esistenti per l'utente con BCC
      final userDoc = await firestore.collection('users').doc(widget.receiverUserId).get();
      final allowedContacts = List<String>.from(userDoc.data()?['allowedContacts'] ?? []);

      // Unisci le liste di amici e BCC utenti del tutor ed escludi l'utente BCC
      final allPotentialContacts = [..._tutorFriends, ..._tutorBccUsers].toSet().toList();
      final contactsToFetch = allPotentialContacts.where((uid) => uid != widget.receiverUserId).toList();

      if (contactsToFetch.isNotEmpty) {
        final usersSnapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: contactsToFetch)
            .get();

        setState(() {
          for (var doc in usersSnapshot.docs) {
            String uid = doc.id;
            Map<String, dynamic>? data = doc.data();
            String nome = data?['nome'] ?? '';
            String cognome = data?['cognome'] ?? '';
            String email = data?['email'] ?? 'No email';
            String displayName = (cognome.isNotEmpty && nome.isNotEmpty) ? '$cognome $nome' : email;

            _userDisplayNames[uid] = displayName;
            _userSelection[uid] = allowedContacts.contains(uid);
          }
        });
      }
    } catch (e) {
      print('Errore durante il caricamento dei contatti: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              _saveChatPermissions();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: _userSelection.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: _userSelection.entries.map((entry) {
          String uid = entry.key;
          String displayName = _userDisplayNames[uid] ?? uid;

          return ListTile(
            title: Text(displayName), // Mostra "Nome Cognome" o email
            trailing: Checkbox(
              value: entry.value,
              onChanged: (value) {
                setState(() {
                  _userSelection[uid] = value ?? false;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _saveChatPermissions() async {
    final allowedContacts = _userSelection.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    // Aggiungi automaticamente il tutor alla lista degli allowedContacts
    if (!allowedContacts.contains(widget.tutorUserId)) {
      allowedContacts.add(widget.tutorUserId);
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.receiverUserId)
        .update({
      'allowedContacts': allowedContacts, // Salva solo gli UID
    });
  }
}