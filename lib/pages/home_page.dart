import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caa_test/Services/auth/auth_service.dart';
import 'package:caa_test/pages/chat_page.dart';
import 'package:caa_test/pages/register_page.dart';
import 'package:caa_test/pages/setting_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:caa_test/pages/SearchPage.dart';
import 'package:caa_test/pages/friend_request_page.dart';

import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool isBccUser = false;
  bool isLoading = true;
  bool isTutor = false; // Indica se l'utente è un Tutor
  List<String> allowedContacts = []; // Contatti consentiti
  List<String> friends = []; // Lista degli amici del tutor
  int friendRequestCount = 0; // Contatore richieste amicizia
  int _currentIndex = 1; // Indice iniziale barra di navigazione

  @override
  void initState() {
    super.initState();
    _checkUserBccStatus();
    _updateFriendRequestCount(); // Chiamata iniziale per aggiornare il contatore
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Aggiorna la lista delle chat ogni volta che si torna su questa pagina
    _updateChatList();
  }

  Future<void> _updateChatList() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data();

      if (data != null) {
        setState(() {
          friends = List<String>.from(data['friends'] ?? []);
          allowedContacts = List<String>.from(data['allowedContacts'] ?? []);

          // Nuovo: Recupero BCC se il tutor ha una lista "bccUsers"
          if (data != null && data.containsKey('bccUsers')) {
            List<String> bccUserIds = List<String>.from(data['bccUsers'] as List? ?? []);
            allowedContacts.addAll(bccUserIds);
          }
        });
      }
    } catch (e) {
      print('Errore nell\'aggiornamento della lista delle chat: $e');
    }
  }


  Future<void> _updateFriendRequestCount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Ottieni il documento dell'utente corrente
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = userDoc.data();

      if (data != null) {
        setState(() {
          friendRequestCount = data['friendRequestCount'] ?? 0;
        });
      }
    } catch (e) {
      print('Errore nel recupero del contatore richieste: $e');
    }
  }

  Future<void> _checkUserBccStatus() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = userDoc.data();
        if (data != null) {
          setState(() {
            isBccUser = data['BCC'] == true;
            isTutor = data['Tutore'] == true;
          });
        }
      }
    } catch (e) {
      print('Errore nel recupero dello stato BCC: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _navigateToFriendRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FriendRequestsPage()),
    ).then((_) {
      // Dopo aver aperto la pagina delle richieste, aggiorna il contatore e la lista delle chat
      _updateFriendRequestCount(); // Aggiorna il contatore dopo che si ritorna dalla pagina
      _updateChatList(); // Aggiorna la lista delle chat
    });
  }

  void navigateToSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsPage()),
    );
  }

  void navigateToSearchPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SearchPage()),
    );
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void navigateToRegistrationPage() {
    setState(() {
      _currentIndex = 2; // Imposta l'indice su "Aggiungi"
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WillPopScope(
          onWillPop: () async {
            setState(() {
              _currentIndex = 1; // Torna su "Home"
            });
            return true;
          },
          child: RegisterPage(
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _currentIndex = 1;
              });
            },
            isCalledFromLogin: false,
            currentUserUid: FirebaseAuth.instance.currentUser?.uid,
          ),
        ),
      ),
    ).then((_) {
      setState(() {
        _currentIndex = 1; // Reimposta l'indice su "Home"
      });
    });
  }

  void signOut() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      print("Logout effettuato con successo!");

      // Forza la navigazione alla pagina di login
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginPage(onTap: () {},)),
            (Route<dynamic> route) => false, // Rimuove tutte le pagine dallo stack
      );
    } catch (e) {
      print("Errore durante il logout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 1 // Mostra AppBar solo nella Home
          ? AppBar(
        title: const Text(
          'Home Page',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        actions: [
          if (!isBccUser)
            Stack(
              children: [
                IconButton(
                  onPressed: () => _navigateToFriendRequests(),
                  icon: const Icon(Icons.mail),
                ),
                if (friendRequestCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: () => navigateToSettingsPage(),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            onPressed: signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      )
          : null, // Nasconde AppBar nelle altre pagine

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
        index: _currentIndex,
        children: [
          SearchPage(),
          _buildUserList(),
          RegisterPage(
            onTap: () {
              setState(() {
                _currentIndex = 1;
              });
            },
            isCalledFromLogin: false,
            currentUserUid: FirebaseAuth.instance.currentUser?.uid,
          ),
        ],
      ),

      bottomNavigationBar: (!isBccUser && isTutor) || (!isBccUser && !isTutor)
          ? BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTap,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Cerca'),
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          if (isTutor) // Mostra "Aggiungi" solo se l'utente è un tutor
            const BottomNavigationBarItem(
                icon: Icon(Icons.person_add), label: 'Aggiungi'),
        ],
      )
          : null,
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Errore');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Widget> userList = [];
        List<DocumentSnapshot> docs = snapshot.data!.docs;
        List<DocumentSnapshot> tutors = [];
        Map<String, List<DocumentSnapshot>> tutorBccMap = {};
        List<DocumentSnapshot> nonTutorNonBcc = [];

        if (isTutor) {
          print("L'utente loggato è un tutor. UID: ${_auth.currentUser?.uid}");

          DocumentSnapshot<Object?>? loggedTutor = docs
              .where((doc) => doc.id == _auth.currentUser?.uid)
              .isNotEmpty
              ? docs.firstWhere((doc) => doc.id == _auth.currentUser?.uid)
              : null;

          if (loggedTutor != null) {
            print("Documento del tutor trovato: ${loggedTutor.id}");

            //Verifica se 'bccUsers' esiste
            List<String> bccUserIds = [];
            final tutorData = loggedTutor.data() as Map<String, dynamic>?;
            if (tutorData != null && tutorData.containsKey('bccUsers')) {
              bccUserIds = List<String>.from(tutorData['bccUsers'] as List? ?? []);
            }

            for (var bccId in bccUserIds) {
              DocumentSnapshot<Object?>? bccUser;
              try {
                bccUser = docs.firstWhere(
                      (d) => d.id == bccId,
                );
              } catch (e) {
                bccUser = null;
              }

              if (bccUser != null) {
                print("Aggiunto alla lista (BCC del tutor): ${bccUser.id}");
                userList.add(_buildUserListItem(bccUser, false));
              } else {
                print("L'utente BCC con ID $bccId non è stato trovato.");
              }
            }
          }
        } else if (isBccUser) {
          // Troviamo il tutor dal campo 'Tutor'
          DocumentSnapshot<Object?>? userDoc;
          try {
            userDoc = docs.firstWhere(
                  (doc) => doc.id == _auth.currentUser?.uid,
            );
          } catch (e) {
            userDoc = null;
          }

          if (userDoc != null) {
            String? tutorId = userDoc['Tutore'];
            if (tutorId != null && tutorId.isNotEmpty) {
              DocumentSnapshot<Object?>? tutorDoc;
              try {
                tutorDoc = docs.firstWhere(
                      (doc) => doc.id == tutorId,
                );
              } catch (e) {
                tutorDoc = null;
              }
              if (tutorDoc != null) {
                userList.add(_buildUserListItem(tutorDoc, true));
              }
            }
          }

          // ORDINIAMO GLI ALLOWED CONTACTS ALFABETICAMENTE
          List<DocumentSnapshot> allowedUsers = docs.where((doc) {
            return allowedContacts.contains(doc.id) && doc.id != userDoc?['Tutore'];
          }).toList();

          allowedUsers.sort((a, b) => (a['cognome'] ?? '').compareTo(b['cognome'] ?? ''));

          for (var user in allowedUsers) {
            final isAllowedTutor = user['Tutore'] == true;
            userList.add(_buildUserListItem(user, isAllowedTutor));
          }
        }

        // TROVIAMO GLI ALTRI TUTOR E I LORO BCC (solo se non sei un BCC user)
        if (!isBccUser) {
          for (var doc in docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            if (data['Tutore'] == true && friends.contains(doc.id)) {
              tutors.add(doc);
              List<String> bccUserIds = List<String>.from(data['bccUsers'] ?? []);
              tutorBccMap[doc.id] =
                  docs.where((d) => bccUserIds.contains(d.id)).toList();
            }
          }

          // ORDINAMENTO ALFABETICO PER COGNOME
          tutors.sort((a, b) => a['cognome'].compareTo(b['cognome']));
          tutorBccMap.forEach((key, value) =>
              value.sort((a, b) => a['cognome'].compareTo(b['cognome'])));

          for (var tutor in tutors) {
            userList.add(_buildUserListItem(tutor, true));
            for (var bcc in tutorBccMap[tutor.id] ?? []) {
              userList.add(_buildUserListItem(bcc, false));
            }
          }

          // TROVA E AGGIUNGI GLI UTENTI NON TUTOR E NON BCC (solo se non sei un BCC user)
          List<DocumentSnapshot> otherUsers = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['Tutore'] == false && data['BCC'] == false && doc.id != _auth.currentUser?.uid && !friends.contains(doc.id);
          }).toList();

          otherUsers.sort((a, b) => (a['cognome'] ?? '').compareTo(b['cognome'] ?? ''));
          for (var user in otherUsers) {
            userList.add(_buildUserListItem(user, false, isNonTutorNonBcc: true));
          }
        }

        return ListView(children: userList);
      },
    );
  }


  Widget _buildUserListItem(DocumentSnapshot document, bool isTutor, {bool isNonTutorNonBcc = false}) {
    Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
    String uid = document.id;
    String nome = data['nome'] ?? 'No Nome';
    String cognome = data['cognome'] ?? 'No Cognome';
    String displayName = "$cognome $nome";
    String? profileImageUrl = data['profileImageUrl']; // URL immagine
    Color backgroundColor = isTutor ? Colors.teal : (isNonTutorNonBcc ? Colors.blue : Colors.white);
    Color textColor = isTutor ? Colors.white : Colors.black;
    Color iconColor = isTutor ? Colors.white : Colors.teal;
    Color avatarTextColor = isTutor ? Colors.teal : Colors.white;
    Color avatarBackgroundColor = isTutor ? Colors.white : Colors.teal;

    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      elevation: 4,
      child: ListTile(
        leading: CircleAvatar(
          radius: 25, // Dimensione avatar
          backgroundColor: avatarBackgroundColor,
          backgroundImage: (profileImageUrl != null && profileImageUrl.isNotEmpty)
              ? NetworkImage(profileImageUrl) as ImageProvider
              : null, // Mostra immagine solo se presente
          child: (profileImageUrl == null || profileImageUrl.isEmpty)
              ? Text(
            cognome.isNotEmpty ? cognome[0].toUpperCase() : '?',
            style: TextStyle(
              color: avatarTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          )
              : null, // Se c'è la foto, non mostra la lettera
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        trailing: Icon(
          Icons.chat,
          color: iconColor,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(receiverUserEmail: data['email'], receiverUserId: uid),
            ),
          );
        },
      ),
    );
  }
}