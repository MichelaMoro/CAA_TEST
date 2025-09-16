import 'package:caa_test/pages/UserManagementPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caa_test/components/chat_bubble.dart';
import 'package:caa_test/components/my_text_field.dart';
import 'package:caa_test/pages/chat/chat_service.dart';
import 'package:caa_test/model/sticker_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ChatPage extends StatefulWidget {
  final String receiverUserEmail;
  final String receiverUserId;

  const ChatPage({
    super.key,
    required this.receiverUserEmail,
    required this.receiverUserId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  List<String> selectedStickers = [];
  double stickerSize = 80.0; // Grandezza predefinita degli sticker
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final CollectionReference _userStickersCollection;
  final FirebaseStorage _firebaseStorage = FirebaseStorage.instance;
  bool _isTutor = false;
  bool _isBccChat= false;
  String _receiverFullName = '';

  @override
  void initState() {
    super.initState();
    _userStickersCollection = _firestore
        .collection('users')
        .doc(_firebaseAuth.currentUser!.uid)
        .collection('stickers');
    _fetchReceiverFullName();
    _checkUserConditions();
  }

  Future<void> _fetchReceiverFullName() async {
    try {
      final receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverUserId)
          .get();

      if (receiverDoc.exists) {
        setState(() {
          _receiverFullName = '${receiverDoc.data()?['cognome'] ?? ''} ${receiverDoc.data()?['nome'] ?? ''}';
        });
      }
    } catch (e) {
      print('Errore durante il recupero del nome completo: $e');
    }
  }

  Future<void>_checkUserConditions() async {
    final currentUser = _firebaseAuth.currentUser;
    if(currentUser != null)
    {
      final tutorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverUserId)
          .get();

      if (tutorDoc.exists && receiverDoc.exists)
      {
        bool isTutor = tutorDoc.data()?['Tutore'] == true;
        bool isBccChat = receiverDoc.data()?['BCC'] == true &&
            receiverDoc.data()?['Tutore'] == currentUser.uid;

        setState((){
          _isTutor = isTutor;
          _isBccChat = isBccChat;
        });
      }
    }
  }

  void toggleStickerSelection(String stickerUrl) {
    setState(() {
      if (selectedStickers.contains(stickerUrl)) {
        selectedStickers.remove(stickerUrl);
      } else {
        selectedStickers.add(stickerUrl);
      }
    });
  }

  Future<void> uploadUserSticker(String stickerUrl) async {
    await _userStickersCollection.add({
      'stickerUrl': stickerUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadFileToFirebase(String localPath) async {
    final file = File(localPath);
    final fileName = file.uri.pathSegments.last;
    final ref = _firebaseStorage.ref().child('stickers/$fileName');

    try {
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Errore durante il caricamento del file: $e');
      return '';
    }
  }

  void sendSelectedStickers() async {
    if (selectedStickers.isNotEmpty) {
      List<String> stickerUrls = [];

      for (String stickerPath in selectedStickers) {
        if (stickerPath.startsWith('http')) {
          stickerUrls.add(stickerPath);
        } else {
          String url = await uploadFileToFirebase(stickerPath);
          if (url.isNotEmpty) {
            stickerUrls.add(url);
          }
        }
      }

      await _chatService.sendMessage(
        widget.receiverUserId,
        stickerUrls.join(','),
        senderId: _firebaseAuth.currentUser!.uid,
        isSticker: true,
      );

      setState(() {
        selectedStickers.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverUserEmail, style: TextStyle(fontSize: 22)),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, size: 30),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: Icon(Icons.insert_emoticon, size: 30),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => StickerPicker(
                  onStickerSelected: (stickerUrl, stickerName) {
                    toggleStickerSelection(stickerUrl);
                    uploadUserSticker(stickerUrl);
                  },
                ),
              ));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildStickerPreview(),
          _buildMessageInput(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStickerPreview() {
    return selectedStickers.isNotEmpty
        ? Container(
      height: stickerSize + 20,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: selectedStickers.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: GestureDetector(
              onTap: () => toggleStickerSelection(selectedStickers[index]),
              child: selectedStickers[index].startsWith('http')
                  ? Image.network(
                selectedStickers[index],
                width: stickerSize,
                height: stickerSize,
                fit: BoxFit.cover,
              )
                  : Image.file(
                File(selectedStickers[index]),
                width: stickerSize,
                height: stickerSize,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    )
        : Container();
  }

  Widget _buildMessageList() {
    return StreamBuilder(
      stream: _chatService.getMessages(
        widget.receiverUserId,
        _firebaseAuth.currentUser!.uid,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Errore: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Nessun messaggio'));
        }
        return ListView(
          controller: _scrollController,
          reverse: true,
          children: snapshot.data!.docs
              .map((document) => _buildMessageItem(document))
              .toList(),
        );
      },
    );
  }

  Widget _buildMessageItem(DocumentSnapshot document) {
    Map<String, dynamic>? data = document.data() as Map<String, dynamic>?;

    if (data == null) {
      return Container();
    }

    var senderId = data['senderId'] ?? '';
    var senderEmail = data['senderEmail'] ?? '';
    var message = data['message'] ?? '';
    var isSticker = data['isSticker'] ?? false;

    var alignment = (senderId == _firebaseAuth.currentUser!.uid)
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Container(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: (senderId == _firebaseAuth.currentUser!.uid)
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(senderEmail, style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            isSticker
                ? Wrap(
              spacing: 4.0,
              children: (message as String)
                  .split(',')
                  .map<Widget>(
                    (stickerUrl) => stickerUrl.startsWith('http')
                    ? Image.network(
                  stickerUrl,
                  width: stickerSize,
                  height: stickerSize,
                  fit: BoxFit.cover,
                )
                    : Image.file(
                  File(stickerUrl),
                  width: stickerSize,
                  height: stickerSize,
                  fit: BoxFit.cover,
                ),
              )
                  .toList(),
            )
                : ChatBubble(message: message),
          ],
        ),
      ),
    );
  }

  void _sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      await _chatService.sendMessage(
        widget.receiverUserId,
        _messageController.text,
        senderId: _firebaseAuth.currentUser!.uid,
        isSticker: false,
      );
      _messageController.clear();

      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: Row(
        children: [
          Expanded(
            child: MyTextField(
              controller: _messageController,
              hintText: 'Inserisci un messaggio',
              obscureText: false,
            ),
          ),
          IconButton(
            onPressed: _sendMessage,


            icon: const Icon(
              Icons.arrow_upward,
              size: 40,
            ),
          ),
          IconButton(
            onPressed: sendSelectedStickers,
            icon: const Icon(
              Icons.send,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Impostazioni'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Categoria Dimensione Stickers
              ListTile(
                title: Text('Dimensione Stickers'),
                onTap: () {
                  Navigator.of(context).pop(); // Chiude il dialogo iniziale
                  _showStickerSizeDialog(); // Mostra il dialogo per la dimensione degli sticker
                },
              ),
              // Mostra la categoria "Gestione Contatti" solo se le condizioni sono vere
              if (_isTutor && _isBccChat)
                ListTile(
                  title: Text('Gestione Contatti'),
                  onTap: () {
                    // Chiude il dialogo delle impostazioni
                    Navigator.of(context).pop();
                    // Naviga alla pagina di gestione chat
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => UserChatManagementPage(
                          receiverUserId: widget.receiverUserId, tutorUserId: _firebaseAuth.currentUser!.uid,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Annulla'),
              onPressed: () {
                Navigator.of(context).pop(); // Chiude il dialogo senza fare nulla
              },
            ),
          ],
        );
      },
    );
  }


  // Funzione per visualizzare il dialogo per impostare la grandezza degli sticker
  void _showStickerSizeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Imposta la grandezza degli sticker'),
          content: Slider(
            value: stickerSize,
            min: 50.0,
            max: 150.0,
            divisions: 10,
            label: '${stickerSize.toInt()} px',
            onChanged: (newValue) {
              setState(() {
                stickerSize = newValue;
              });
            },
          ),
          actions: [
            TextButton(
              child: Text('Annulla'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Conferma'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}