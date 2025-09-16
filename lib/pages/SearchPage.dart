import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'register_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String _searchQuery = ''; // Testo della ricerca
  List<String> _friendIds = []; // Lista degli UID degli amici dell'utente attuale
  Set<String> _sentFriendRequests = <String>{}; // Set per tenere traccia delle richieste inviate

  @override
  void initState() {
    super.initState();
    _fetchFriends();
    _listenToFriendRequests(); // Inizia ad ascoltare le richieste di amicizia
  }

  // Funzione per ottenere la lista degli amici
  Future<void> _fetchFriends() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final userData = userDoc.data();

    if (userData != null && userData.containsKey('friends')) {
      setState(() {
        _friendIds = List<String>.from(userData['friends']); // Salva la lista degli amici
      });
    }
  }

  // Funzione per ascoltare le richieste di amicizia in uscita
  void _listenToFriendRequests() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    FirebaseFirestore.instance
        .collection('friendRequests')
        .where('requests', arrayContains: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      Set<String> sentRequests = {};
      for (final doc in snapshot.docs) {
        sentRequests.add(doc.id); // L'ID del documento è l'UID del tutor a cui è stata inviata la richiesta
      }
      setState(() {
        _sentFriendRequests = sentRequests;
      });
    });
  }

  // Funzione per mostrare la popup dei dettagli del tutor
  void _showTutorDetails(DocumentSnapshot tutorDoc) async {
    final data = tutorDoc.data() as Map<String, dynamic>;
    final cognome = data['cognome'] ?? 'N/A';
    final nome = data['nome'] ?? 'N/A';
    final displayName = "$cognome $nome";
    final tutorUid = tutorDoc.id;
    final profileImageUrl = data['profileImageUrl'];
    List<DocumentSnapshot> bccUsers = [];

    // Recupera la lista degli utenti BCC gestiti dal tutor
    if (data.containsKey('bccUsers')) {
      List<String> bccUids = List<String>.from(data['bccUsers'] ?? []);
      if (bccUids.isNotEmpty) {
        final bccSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('uid', whereIn: bccUids)
            .get();
        bccUsers = bccSnapshot.docs;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.teal[300],
                          backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                              ? NetworkImage(profileImageUrl) as ImageProvider<Object>?
                              : null,
                          child: profileImageUrl == null || profileImageUrl.isEmpty
                              ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 20, color: Colors.white),
                          )
                              : null,
                        ),
                      ),
                      Positioned(
                        left: 70,
                        top: 5,
                        child: Text(
                          displayName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Positioned(
                        left: 70,
                        top: 25,
                        child: Text(
                          '#${tutorUid.substring(0, 5)}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.grey),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Utenti BCC Gestiti:',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (bccUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Nessun utente BCC gestito.'),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: bccUsers.length,
                      itemBuilder: (context, index) {
                        final bccData = bccUsers[index].data() as Map<String, dynamic>;
                        final bccNome = bccData['nome'] ?? 'N/A';
                        final bccCognome = bccData['cognome'] ?? 'N/A';
                        final bccDisplayName = "$bccCognome $bccNome";
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue[200],
                            child: Text(
                              bccDisplayName.isNotEmpty ? bccDisplayName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(bccDisplayName),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Utente non autenticato')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Aggiungi Amici',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Cerca per cognome o nome',
                prefixIcon: const Icon(Icons.search, color: Colors.teal),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                  borderSide: const BorderSide(color: Colors.teal),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                  borderSide: const BorderSide(color: Colors.teal),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value; // Aggiorna la query di ricerca
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('Tutore', isEqualTo: true) // Filtra solo i tutor
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Errore durante il caricamento'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final tutorResults = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final cognome = (data['cognome'] ?? '').toLowerCase();
                  final nome = (data['nome'] ?? '').toLowerCase();
                  final uid = doc.id;
                  return (cognome.startsWith(_searchQuery.toLowerCase()) ||
                      nome.startsWith(_searchQuery.toLowerCase())) &&
                      uid != currentUser.uid &&
                      !_friendIds.contains(uid);
                }).toList();

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('Tutore', isEqualTo: false) // Filtra chi non è tutor
                      .where('BCC', isEqualTo: false) // Filtra chi non è BCC
                      .snapshots(),
                  builder: (context, nonTutorSnapshot) {
                    if (nonTutorSnapshot.hasError) {
                      return const Center(child: Text('Errore durante il caricamento'));
                    }
                    if (nonTutorSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final nonTutorResults = nonTutorSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final cognome = (data['cognome'] ?? '').toLowerCase();
                      final nome = (data['nome'] ?? '').toLowerCase();
                      final uid = doc.id;
                      return (cognome.startsWith(_searchQuery.toLowerCase()) ||
                          nome.startsWith(_searchQuery.toLowerCase())) &&
                          uid != currentUser.uid &&
                          !_friendIds.contains(uid);
                    }).toList();

                    final combinedResults = [...tutorResults, ...nonTutorResults];

                    if (combinedResults.isEmpty) {
                      return const Center(child: Text('Nessun utente disponibile da aggiungere.'));
                    }

                    return ListView(
                      children: combinedResults.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final cognome = data['cognome'] ?? 'N/A';
                        final nome = data['nome'] ?? 'N/A';
                        final uid = doc.id;
                        final displayName = "$cognome $nome";
                        final String? profileImageUrl = data['profileImageUrl'];
                        final bool requestSent = _sentFriendRequests.contains(uid);
                        final bool isTutorUser = data['Tutore'] == true;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 25,
                              backgroundColor: isTutorUser ? Colors.teal : Colors.blue,
                              backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                                  ? NetworkImage(profileImageUrl) as ImageProvider<Object>?
                                  : null,
                              child: profileImageUrl == null || profileImageUrl.isEmpty
                                  ? Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white),
                              )
                                  : null,
                            ),
                            title: Text(displayName),
                            onTap: isTutorUser ? () => _showTutorDetails(doc) : null,
                            trailing: ElevatedButton(
                              onPressed: requestSent
                                  ? null
                                  : () async {
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('friendRequests')
                                      .doc(uid)
                                      .set({
                                    'requests': FieldValue.arrayUnion([currentUser.uid]),
                                  }, SetOptions(merge: true));

                                  await _incrementFriendRequestCount(uid);

                                  // Aggiorna lo stato immediatamente
                                  setState(() {
                                    _sentFriendRequests.add(uid);
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Richiesta di amicizia inviata!')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Errore durante l\'invio della richiesta')),
                                  );
                                  print('Errore: $e');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: requestSent ? Colors.grey : (isTutorUser ? Colors.teal : Colors.blue),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(requestSent ? 'Inviata' : 'Aggiungi Amico'),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Funzione per incrementare il contatore delle richieste
  Future<void> _incrementFriendRequestCount(String userId) async {
    try {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userId);
      await userDocRef.update({
        'friendRequestCount': FieldValue.increment(1),
      });
    } catch (e) {
      print('Errore nell\'incrementare il contatore delle richieste: $e');
    }
  }
}