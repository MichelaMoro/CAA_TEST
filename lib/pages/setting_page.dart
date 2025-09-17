import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final firebase_storage.FirebaseStorage _storage = firebase_storage.FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // -- UI / user info --
  String _userName = "Utente";
  String _userSurname = "";
  String _userId = "";
  String _profileImageUrl = "";
  double _stickerSize = 80.0;
  String _statusMessage = "Nessun download in corso";
  Map<String, bool> _folderVisibility = {};
  bool isLoading = true;

  // -- ruolo / relazioni --
  bool _isTutore = false;       // se true => è tutor
  bool _isBccUser = false;      // se true => utente flagged BCC
  String? _tutoreId;            // se non tutor, uid del tutor di riferimento

  // -- per i tutor: lista utenti bcc che gestisce e selezione corrente --
  List<Map<String, String>> _bccUsers = []; // [{ 'uid': uid, 'display': 'Nome Cognome' }, ...]
  String? _selectedManagedUserId; // uid dell'utente che il tutor sta gestendo ora

  @override
  void initState() {
    super.initState();
    _initializeSettingsData();
  }

  Future<void> _initializeSettingsData() async {
    setState(() => isLoading = true);
    await _loadUserData();
    if (_isTutore) {
      await _loadManagedUsers(); // carica bccUsers e imposta _selectedManagedUserId
    }
    await _loadStickerSize();
    await _loadStickerFolders();
    setState(() => isLoading = false);
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDocSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = userDocSnap.data();

    if (data != null) {
      // Interpretazioni compatibili:
      // - data['Tutore'] === true  -> è tutor
      // - data['Tutore'] === "<uid>" -> campo Tutore contiene uid del tutor di riferimento
      // - data['tutoreId'] fallback
      // - BCC flag: data['BCC'] || data['bcc']
      dynamic tutField = data['Tutore'] ?? data['tutoreId'] ?? data['tutorId'];

      bool isTutorFlag = false;
      String? tutorIdFromField;

      if (tutField is bool) {
        isTutorFlag = tutField == true;
      } else if (tutField is String) {
        // campo contiene l'uid del proprio tutor
        tutorIdFromField = tutField;
      }

      final bool isBcc = (data['BCC'] == true) || (data['bcc'] == true);

      setState(() {
        _userName = data['nome'] ?? "Utente";
        _userSurname = data['cognome'] ?? "";
        _userId = user.uid.substring(0, 5);
        _profileImageUrl = data['profileImageUrl'] ?? "";
        _isTutore = isTutorFlag;
        _isBccUser = isBcc;
        _tutoreId = tutorIdFromField;
      });
    }
  }

  Future<void> _loadManagedUsers() async {
    // Se sono tutor, carico bccUsers dal mio documento e ottengo display name per ciascuno.
    _bccUsers = [];
    final user = _auth.currentUser;
    if (user == null) return;

    final tutorDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final tutorData = tutorDoc.data() ?? {};
    final dynamic bccListDyn = tutorData['bccUsers'] ?? tutorData['BCCusers'] ?? tutorData['bcc'];

    if (bccListDyn == null) return;
    final List<dynamic> bccList = List<dynamic>.from(bccListDyn);

    for (var uidDyn in bccList) {
      try {
        final uid = uidDyn.toString();
        final uDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final uData = uDoc.data();
        String display = uid;
        if (uData != null) {
          final nome = (uData['nome'] ?? '').toString();
          final cognome = (uData['cognome'] ?? '').toString();
          final combined = ('$nome $cognome').trim();
          if (combined.isNotEmpty) display = combined;
        }
        _bccUsers.add({'uid': uid, 'display': display});
      } catch (e) {
        // ignora eventuali singoli errori
      }
    }

    if (_bccUsers.isNotEmpty && _selectedManagedUserId == null) {
      _selectedManagedUserId = _bccUsers.first['uid'];
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

  Future<List<Directory>> _listLocalStickerSubdirs() async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) return [];
    final baseDir = Directory('${directory.path}/Download/Stickers');
    if (!await baseDir.exists()) return [];
    final subDirs = baseDir.listSync().whereType<Directory>().toList();
    return subDirs;
  }

  Future<void> _loadStickerFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final subDirs = await _listLocalStickerSubdirs();

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      setState(() => _folderVisibility = {});
      return;
    }

    // Se utente è TUTORE -> carica le impostazioni per l'utente selezionato (_selectedManagedUserId)
    if (_isTutore) {
      if (_selectedManagedUserId == null) {
        // Nessun bccUser selezionato: fallback a preferenze locali (false di default)
        setState(() {
          _folderVisibility = {
            for (final dir in subDirs) p.basename(dir.path): prefs.getBool('visible_${dir.path}') ?? false
          };
        });
        return;
      }

      // Carico visibleFoldersByUser dal documento del tutor (me stesso)
      final tutorDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final tutorData = tutorDoc.data() ?? {};
      final rawByUser = tutorData['visibleFoldersByUser'];
      Map<String, dynamic> byUser = {};
      try {
        if (rawByUser != null) byUser = Map<String, dynamic>.from(rawByUser);
      } catch (e) {
        byUser = {};
      }

      final Map<String, dynamic> userMap =
      Map<String, dynamic>.from(byUser[_selectedManagedUserId] ?? {});

      setState(() {
        _folderVisibility = {
          for (final dir in subDirs) p.basename(dir.path): userMap[p.basename(dir.path)] == true
        };
      });
      return;
    }

    // Se utente NON è tutore:
    // se è marcato BCC e ha un campo Tutore (uid) -> carica dal documento del tutor solo la mappa per il mio uid
    if (_isBccUser && (_tutoreId != null && _tutoreId!.isNotEmpty)) {
      final tutorDoc = await FirebaseFirestore.instance.collection('users').doc(_tutoreId).get();
      final tutorData = tutorDoc.data() ?? {};
      final rawByUser = tutorData['visibleFoldersByUser'];
      Map<String, dynamic> byUser = {};
      try {
        if (rawByUser != null) byUser = Map<String, dynamic>.from(rawByUser);
      } catch (e) {
        byUser = {};
      }

      final Map<String, dynamic> myMap = Map<String, dynamic>.from(byUser[currentUser.uid] ?? {});

      setState(() {
        _folderVisibility = {
          for (final dir in subDirs) p.basename(dir.path): myMap[p.basename(dir.path)] == true
        };
      });
      return;
    }

    // Fallback: utente non-tutor e non-BCC o senza tutor => usa preferenze locali
    setState(() {
      _folderVisibility = {
        for (final dir in subDirs) p.basename(dir.path): prefs.getBool('visible_${dir.path}') ?? true
      };
    });
  }

  Future<void> _updateFolderVisibility(String folderName, bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    final directory = await getExternalStorageDirectory();
    if (directory == null) return;
    final folderPath = '${directory.path}/Download/Stickers/$folderName';

    // Salvo locale sempre (utile come fallback)
    await prefs.setBool('visible_$folderPath', isVisible);

    setState(() => _folderVisibility[folderName] = isVisible);

    // SOLO i tutor possono salvare SU FIRESTORE le impostazioni PER OGNI singolo bccUser
    if (!_isTutore) {
      // Non tutor non può cambiare le impostazioni remote (vengono scelte dal tutor)
      _showSnackBar('Solo il tuo tutore può modificare le cartelle visibili per il tuo account.');
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (_selectedManagedUserId == null) {
      _showSnackBar('Seleziona un utente (bccUser) da gestire prima di modificare.');
      return;
    }

    final tutorDocRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
    final tutorDoc = await tutorDocRef.get();
    final tutorData = tutorDoc.data() ?? {};

    Map<String, dynamic> byUser = {};
    try {
      if (tutorData['visibleFoldersByUser'] != null) {
        byUser = Map<String, dynamic>.from(tutorData['visibleFoldersByUser']);
      }
    } catch (e) {
      byUser = {};
    }

    Map<String, dynamic> userMap = {};
    try {
      if (byUser[_selectedManagedUserId] != null) {
        userMap = Map<String, dynamic>.from(byUser[_selectedManagedUserId]);
      }
    } catch (e) {
      userMap = {};
    }

    userMap[folderName] = isVisible;
    byUser[_selectedManagedUserId!] = userMap;

    await tutorDocRef.update({'visibleFoldersByUser': byUser});
    _showSnackBar('Visibilità aggiornata per l\'utente selezionato.');
  }

  Future<void> _downloadFolder(firebase_storage.Reference folderRef, String localPath) async {
    try {
      final result = await folderRef.listAll();
      final localDir = Directory(localPath);
      if (!localDir.existsSync()) {
        localDir.createSync(recursive: true);
      }

      for (var item in result.items) {
        final filePath = '$localPath/${item.name}';
        final file = File(filePath);
        if (!file.existsSync()) {
          setState(() => _statusMessage = 'Scaricando: ${item.name}');
          await item.writeToFile(file);
        }
      }

      for (var prefix in result.prefixes) {
        if (!RegExp(r'^[a-zA-Z0-9]{28}$').hasMatch(prefix.name)) {
          final subFolderPath = '$localPath/${prefix.name}';
          await _downloadFolder(prefix, subFolderPath);
        }
      }

      setState(() => _statusMessage = 'Download completato con successo!');
      await _loadStickerFolders();
    } catch (e) {
      setState(() => _statusMessage = 'Errore durante il download: $e');
    }
  }

  Future<void> _startDownload() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar('Errore: Devi essere loggato per scaricare gli sticker.');
      return;
    }

    setState(() => _statusMessage = 'Verifica permessi...');

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      PermissionStatus status;
      if (sdkInt >= 33) {
        status = await Permission.photos.status;
        if (!status.isGranted) status = await Permission.photos.request();
      } else {
        status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
      }

      if (!status.isGranted) {
        setState(() => _statusMessage = 'Permesso di archiviazione negato.');
        _showSnackBar('Permesso di archiviazione negato.');
        openAppSettings();
        return;
      }
    } catch (e) {
      setState(() => _statusMessage = 'Errore permessi: $e');
      _showSnackBar('Errore nella richiesta permessi.');
      return;
    }

    setState(() => _statusMessage = 'Avvio download...');

    try {
      final rootRef = _storage.ref().child('stickers');
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        setState(() => _statusMessage = 'Impossibile accedere alla directory di archiviazione esterna.');
        return;
      }

      final localPath = '${directory.path}/Download/Stickers';
      await _downloadFolder(rootRef, localPath);

      setState(() => _statusMessage = 'Download completato!');
      _showSnackBar('Download completato!');
    } catch (e) {
      setState(() => _statusMessage = 'Errore critico: $e');
      _showSnackBar('Errore durante il download.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTutorManagementArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seleziona l\'utente (bccUsers) da gestire:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_bccUsers.isEmpty)
          const Text('Nessun utente collegato (bccUsers) trovato.', style: TextStyle(color: Colors.grey))
        else
          DropdownButton<String>(
            value: _selectedManagedUserId,
            items: _bccUsers
                .map((m) => DropdownMenuItem<String>(
              value: m['uid'],
              child: Text(m['display'] ?? m['uid'] ?? ''),
            ))
                .toList(),
            onChanged: (val) async {
              setState(() {
                _selectedManagedUserId = val;
                isLoading = true;
              });
              await _loadStickerFolders();
              setState(() {
                isLoading = false;
              });
            },
            isExpanded: true,
            hint: const Text('Seleziona utente...'),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        backgroundColor: Colors.teal,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: _profileImageUrl.isNotEmpty ? NetworkImage(_profileImageUrl) : null,
                    child: _profileImageUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white) : null,
                  ),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("$_userSurname $_userName", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text("#$_userId", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                ]),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(thickness: 1),
            const SizedBox(height: 20),
            const Text('Seleziona la dimensione degli sticker:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Slider(
              value: _stickerSize,
              min: 40.0,
              max: 120.0,
              divisions: 8,
              label: '${_stickerSize.round()} px',
              onChanged: (value) => _saveStickerSize(value),
            ),
            Text('Dimensione attuale: ${_stickerSize.round()} px'),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download),
              label: const Text('Scarica/Aggiorna Sticker'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
            const SizedBox(height: 20),
            Text(_statusMessage, style: const TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 30),

            const Text('Cartelle visibili nella scelta sticker:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 10),

            // Tutor area: dropdown + possibilità di selezionare cartelle PER UTENTE
            if (_isTutore) ...[
              _buildTutorManagementArea(),
              if (_folderVisibility.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Nessuna cartella sticker locale trovata o nessuna impostazione per l\'utente selezionato.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                ),
              ..._folderVisibility.entries.map((entry) {
                return CheckboxListTile(
                  title: Text(entry.key),
                  value: entry.value,
                  onChanged: (value) {
                    if (value != null) _updateFolderVisibility(entry.key, value);
                  },
                );
              }).toList(),
            ] else ...[
              // Non tutor: visualizzo SOLO le cartelle abilitate dal tutor (se l'utente è BCC e ha un Tutore)
              if (_isBccUser && (_tutoreId != null && _tutoreId!.isNotEmpty)) ...[
                if (_folderVisibility.entries.where((e) => e.value == true).isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Il tuo tutore non ha reso visibili cartelle per il tuo account.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                  ),
                ..._folderVisibility.entries
                    .where((entry) => entry.value == true)
                    .map((entry) => ListTile(title: Text(entry.key)))
                    .toList()
              ] else ...[
                // fallback per utenti non BCC / senza tutore: preferenze locali
                if (_folderVisibility.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Nessuna cartella sticker locale trovata.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                  ),
                ..._folderVisibility.entries.map((entry) {
                  return CheckboxListTile(
                    title: Text(entry.key),
                    value: entry.value,
                    onChanged: (value) {
                      if (value != null) _updateFolderVisibility(entry.key, value); // salverà solo in prefs (non su firestore) se non tutor
                    },
                  );
                }).toList(),
              ]
            ]
          ]),
        ),
      ),
    );
  }
}
