import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p; // Alias per evitare conflitti con Flutter's 'Context'
import 'package:permission_handler/permission_handler.dart'; // Import per la gestione dei permessi
import 'package:path_provider/path_provider.dart'; // Import per i percorsi di archiviazione
import 'package:device_info_plus/device_info_plus.dart'; // Import per ottenere la versione SDK di Android

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final firebase_storage.FirebaseStorage _storage = firebase_storage.FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  String _userName = "Utente";
  String _userSurname = "";
  String _userId = "";
  String _profileImageUrl = "";
  double _stickerSize = 80.0;
  String _statusMessage = "Nessun download in corso";
  Map<String, bool> _folderVisibility = {};
  bool isLoading = true; // *** NUOVA VARIABILE AGGIUNTA QUI ***

  @override
  void initState() {
    super.initState();
    _initializeSettingsData(); // Nuovo metodo per gestire tutte le inizializzazioni
  }

  Future<void> _initializeSettingsData() async {
    setState(() {
      isLoading = true; // Imposta a true all'inizio dell'inizializzazione
    });
    await _loadUserData();
    await _loadStickerFolders();
    await _loadStickerSize();
    setState(() {
      isLoading = false; // Imposta a false quando tutti i dati sono stati caricati
    });
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = userDoc.data();

    if (data != null) {
      setState(() {
        _userName = data['nome'] ?? "Utente";
        _userSurname = data['cognome'] ?? "";
        _userId = user.uid.substring(0, 5);
        _profileImageUrl = data['profileImageUrl'] ?? "";
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar("Devi essere loggato per caricare la foto.");
      return;
    }

    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    File imageFile = File(pickedFile.path);
    String filePath = "profile_pictures/${user.uid}.jpg";

    try {
      firebase_storage.UploadTask uploadTask = _storage.ref(filePath).putFile(imageFile);
      firebase_storage.TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'profileImageUrl': downloadUrl,
      });

      setState(() {
        _profileImageUrl = downloadUrl;
      });

      _showSnackBar("Foto profilo aggiornata!");
    } catch (e) {
      print('Errore nel caricamento immagine profilo: $e');
      _showSnackBar("Errore nel caricamento dell'immagine.");
    }
  }

  Future<void> _loadStickerSize() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _stickerSize = prefs.getDouble('sticker_size') ?? 80.0;
    });
  }

  void _saveStickerSize(double newSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sticker_size', newSize);
    setState(() {
      _stickerSize = newSize;
    });
  }

  Future<void> _loadStickerFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final directory = await getExternalStorageDirectory();
    if (directory == null) return;

    final baseDir = Directory('${directory.path}/Download/Stickers');

    if (!await baseDir.exists()) {
      setState(() => _folderVisibility = {});
      return;
    }

    final subDirs = baseDir.listSync().whereType<Directory>();

    setState(() {
      _folderVisibility = {
        for (final dir in subDirs)
          p.basename(dir.path): prefs.getBool('visible_${dir.path}') ?? true,
      };
    });
  }

  Future<void> _updateFolderVisibility(String folderName, bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    final directory = await getExternalStorageDirectory();
    if (directory == null) return;
    final folderPath = '${directory.path}/Download/Stickers/$folderName';

    await prefs.setBool('visible_$folderPath', isVisible);
    setState(() {
      _folderVisibility[folderName] = isVisible;
    });
  }

  Future<void> _downloadFolder(firebase_storage.Reference folderRef, String localPath) async {
    try {
      final result = await folderRef.listAll();
      final localDir = Directory(localPath);
      if (!localDir.existsSync()) {
        localDir.createSync(recursive: true);
        print('DEBUG: Creata directory locale: $localPath');
      }

      for (var item in result.items) {
        final filePath = '$localPath/${item.name}';
        final file = File(filePath);

        if (file.existsSync()) {
          print('DEBUG: File già esistente, saltato: ${item.name}');
          continue;
        }

        setState(() {
          _statusMessage = 'Scaricando: ${item.name}';
        });
        print('DEBUG: Scaricando file: ${item.fullPath} a $filePath');
        await item.writeToFile(file);
      }

      for (var prefix in result.prefixes) {
        if (RegExp(r'^[a-zA-Z0-9]{28}$').hasMatch(prefix.name)) {
          print('DEBUG: Saltando la cartella utente (UID) ${prefix.name} durante il download.');
          continue;
        }

        final subFolderPath = '$localPath/${prefix.name}';
        print('DEBUG: Entrando nella sottocartella: ${prefix.fullPath}');
        await _downloadFolder(prefix, subFolderPath);
      }

      setState(() {
        _statusMessage = 'Download completato con successo!';
      });

      await _loadStickerFolders();
      print('DEBUG: _downloadFolder completato per ${folderRef.fullPath}');
    } catch (e) {
      setState(() {
        _statusMessage = 'Errore durante il download: $e';
      });
      print('DEBUG: Errore in _downloadFolder per ${folderRef.fullPath}: $e');
    }
  }

  Future<void> _startDownload() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar('Errore: Devi essere loggato per scaricare gli sticker.');
      print('DEBUG: Tentativo di download senza utente autenticato. Funzione interrotta.');
      return;
    }
    print('DEBUG: Utente autenticato (UID): ${user.uid}');

    setState(() {
      _statusMessage = 'Verifica permessi...';
    });

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      PermissionStatus status;
      if (sdkInt >= 33) {
        status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
      } else {
        status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      }

      if (!status.isGranted) {
        setState(() {
          _statusMessage = 'Permesso di archiviazione negato. Abilita i permessi nelle impostazioni.';
        });
        print('DEBUG: Permesso di archiviazione negato. Funzione interrotta.');
        _showSnackBar('Permesso di archiviazione negato. Abilita i permessi nelle impostazioni dell\'app.');
        openAppSettings();
        return;
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Errore durante la richiesta permessi: $e';
      });
      print('DEBUG: Errore nella richiesta permessi: $e');
      _showSnackBar('Errore nella richiesta permessi.');
      return;
    }

    setState(() {
      _statusMessage = 'Avvio download...';
    });

    try {
      final rootRef = _storage.ref().child('stickers');

      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        setState(() {
          _statusMessage = 'Impossibile accedere alla directory di archiviazione esterna.';
        });
        print('DEBUG: getExternalStorageDirectory ha restituito null.');
        _showSnackBar('Errore: Impossibile trovare una directory di archiviazione.');
        return;
      }

      final localPath = '${directory.path}/Download/Stickers';

      print('DEBUG: Avvio download da Firebase Storage nella cartella locale: $localPath');
      await _downloadFolder(rootRef, localPath);
      print('DEBUG: _downloadFolder completato.');

      setState(() {
        _statusMessage = 'Download completato con successo!';
      });
      _showSnackBar('Download di tutti gli sticker completato!');

    } catch (e) {
      setState(() {
        _statusMessage = 'Errore critico durante il download: $e';
      });
      print('DEBUG: Errore in _startDownload(): $e');
      _showSnackBar('Errore durante il download: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        backgroundColor: Colors.teal,
      ),
      body: isLoading // Mostra CircularProgressIndicator se isLoading è true
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickAndUploadImage,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: _profileImageUrl.isNotEmpty
                          ? NetworkImage(_profileImageUrl)
                          : null,
                      child: _profileImageUrl.isEmpty
                          ? const Icon(Icons.person, size: 50, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$_userSurname $_userName",
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "#$_userId",
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(thickness: 1),
              const SizedBox(height: 20),
              const Text(
                'Seleziona la dimensione degli sticker:',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              Slider(
                value: _stickerSize,
                min: 40.0,
                max: 120.0,
                divisions: 8,
                label: '${_stickerSize.round()} px',
                onChanged: (value) {
                  _saveStickerSize(value);
                },
              ),
              Text('Dimensione attuale: ${_stickerSize.round()} px'),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _startDownload,
                icon: const Icon(Icons.download),
                label: const Text('Scarica/Aggiorna Sticker'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 30),
              const Text(
                'Cartelle visibili nella scelta sticker:',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              if (_folderVisibility.isEmpty && !isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Nessuna cartella sticker locale trovata.',
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                ),
              ..._folderVisibility.entries.map((entry) {
                return CheckboxListTile(
                  title: Text(entry.key),
                  value: entry.value,
                  onChanged: (value) {
                    if (value != null) {
                      _updateFolderVisibility(entry.key, value);
                    }
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}