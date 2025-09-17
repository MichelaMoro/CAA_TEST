import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as path; // Alias per evitare conflitti con Flutter's 'Context'
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart'; // Import per getExternalStorageDirectory
import 'package:cloud_firestore/cloud_firestore.dart';

import 'sticker_folder_view.dart';

class StickerPicker extends StatefulWidget {
  final Function(String stickerUrl, String stickerName) onStickerSelected;

  const StickerPicker({Key? key, required this.onStickerSelected}) : super(key: key);

  @override
  _StickerPickerState createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  // Mappa per le cartelle locali: String (nome cartella) -> FolderContent
  final Map<String, FolderContent> localFolders = {};
  // Oggetto per la cartella sticker personali di Firebase
  FolderContent? firebaseUserFolder;

  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Inizializza con un valore di fallback, verrà sovrascritto dopo il caricamento asincrono
  Directory baseStickersDirectory = Directory('/storage/emulated/0/Download/Stickers');
  bool isLoading = true;

  // Ruolo / permessi
  bool _isTutor = false;
  bool _isBccUser = false;
  String? _tutoreId; // se non tutor, contiene l'UID del tutor di riferimento

  @override
  void initState() {
    super.initState();
    _initializeData(); // Chiamata unificata per l'inizializzazione
  }

  Future<void> _initializeData() async {
    // 1. Ottieni e imposta la directory base
    await _getAndSetBaseDirectory();

    // 2. Richiedi i permessi
    await _requestPermissions();

    // 3. Carica ruolo utente (da Firestore) e cartelle
    await _loadUserRoleAndFolders();

    // 4. Aggiorna lo stato di caricamento
    setState(() => isLoading = false);
  }

  Future<void> _getAndSetBaseDirectory() async {
    final Directory? appSpecificExternalDir = await getExternalStorageDirectory();
    if (appSpecificExternalDir != null) {
      baseStickersDirectory = Directory('${appSpecificExternalDir.path}/Download/Stickers');
    } else {
      baseStickersDirectory = Directory('/storage/emulated/0/Download/Stickers');
      print('WARNING: Could not get external storage directory, falling back to direct path. Permissions might be an issue.');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final sdk = await DeviceInfoPlugin().androidInfo.then((info) => info.version.sdkInt);

      if (sdk >= 33) {
        await Permission.photos.request();
        await Permission.videos.request();
      } else {
        await Permission.storage.request();
      }
    }
  }

  /// Carica info ruolo (tutor / bcc) e poi le cartelle locali + firebase in base ai permessi/ruoli
  Future<void> _loadUserRoleAndFolders() async {
    // Carica ruolo utente da Firestore
    final user = _auth.currentUser;
    if (user == null) {
      // utente non loggato: carica folders locali come fallback
      await _loadFolders(); // carica ma senza filtrare (fallback)
      await _loadFirebaseUserFolder();
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final data = userDoc.data() ?? {};

      // Interpretazioni compatibili con il tuo schema:
      // - data['Tutore'] === true  -> è tutor
      // - data['Tutore'] === "<uid>" -> campo Tutore contiene uid del proprio tutor
      // - inoltre campo BCC / bcc potrebbe indicare che è un bccUser
      dynamic tutField = data['Tutore'] ?? data['tutoreId'] ?? data['tutorId'];
      bool isTutorFlag = false;
      String? tutorIdFromField;

      if (tutField is bool) {
        isTutorFlag = tutField == true;
      } else if (tutField is String) {
        tutorIdFromField = tutField;
      }

      final bool isBcc = (data['BCC'] == true) || (data['bcc'] == true) || (data['Bcc'] == true);

      setState(() {
        _isTutor = isTutorFlag;
        _isBccUser = isBcc;
        _tutoreId = tutorIdFromField;
      });
    } catch (e) {
      print('Errore nel caricamento del ruolo utente: $e');
      // fallback: mantieni default (non tutor) e carica le cartelle locali
    }

    // Ora carica cartelle secondo ruolo
    await _loadFolders();
    await _loadFirebaseUserFolder();
  }

  // ----------------- LOAD FOLDERS (Locale) -----------------
  Future<void> _loadFolders() async {
    localFolders.clear();
    firebaseUserFolder = null; // reset

    if (!await baseStickersDirectory.exists()) {
      await baseStickersDirectory.create(recursive: true);
    }

    final subDirs = baseStickersDirectory.listSync().whereType<Directory>().toList();
    final prefs = await SharedPreferences.getInstance();

    // Nome della cartella personale locale da escludere
    final String excludedFolderName = 'Stickers personali';

    // Prepara la mappa allowedFolders (se applicabile)
    Map<String, bool> allowedFoldersForMe = {};

    final currentUser = _auth.currentUser;

    // Caso: utente è TUTORE -> vedrà tutte le cartelle locali (per poterle gestire)
    if (_isTutor) {
      allowedFoldersForMe = {}; // vuota indica "mostra tutte" (salvo prefs)
    } else if (_isBccUser && (_tutoreId != null && _tutoreId!.isNotEmpty) && currentUser != null) {
      // Caso: utente BCC -> prendi la mappa dal documento del suo tutore
      try {
        final tutorDoc = await _firestore.collection('users').doc(_tutoreId).get();
        final tutorData = tutorDoc.data() ?? {};

        // Preferiamo la struttura per-utente 'visibleFoldersByUser'
        dynamic rawByUser = tutorData['visibleFoldersByUser'] ?? tutorData['visibleFoldersByUserMap'] ?? tutorData['visibleFolders'];
        if (rawByUser != null) {
          try {
            final Map<String, dynamic> byUser = Map<String, dynamic>.from(rawByUser);
            final Map<String, dynamic> myMap = Map<String, dynamic>.from(byUser[currentUser.uid] ?? {});
            myMap.forEach((k, v) {
              allowedFoldersForMe[k] = (v == true);
            });
          } catch (e) {
            // se la struttura non è mappa di mappe, proviamo fallback a visibleFolders (global)
            try {
              final Map<String, dynamic> globalMap = Map<String, dynamic>.from(rawByUser);
              globalMap.forEach((k, v) {
                allowedFoldersForMe[k] = (v == true);
              });
            } catch (_) {
              allowedFoldersForMe = {};
            }
          }
        }
      } catch (e) {
        print('Errore durante il caricamento delle cartelle per il BCC user dal tutor: $e');
        allowedFoldersForMe = {};
      }
    } else {
      // Non tutor e non-BCC: usa preferenze locali come fallback
      // lasciamo allowedFoldersForMe vuota e useremo prefs per decidere
      allowedFoldersForMe = {};
    }

    // Ora itera sulle sottocartelle e applica il filtro
    for (final dir in subDirs) {
      final String currentFolderName = path.basename(dir.path);

      if (currentFolderName == excludedFolderName) {
        continue; // Salta la cartella locale "Stickers personali"
      }

      // Se sono BCC user e tutor ha definito esplicitamente le cartelle per me:
      if (!_isTutor && _isBccUser && allowedFoldersForMe.isNotEmpty) {
        // se tutor non ha abilitato questa cartella per me -> salto
        if (allowedFoldersForMe[currentFolderName] != true) continue;
      }

      // Altrimenti (tutor o fallback) rispetta le preferenze locali (prefs)
      final isVisiblePref = prefs.getBool('visible_${dir.path}') ?? true;
      if (!_isTutor && !_isBccUser) {
        // utente normale senza tutor: mostra solo se pref true
        if (!isVisiblePref) continue;
      } else if (_isTutor) {
        // tutor: mostra indipendentemente dalla pref per permettere gestione (ma puoi cambiare)
        // se preferisci rispettare le pref anche per i tutor, abilita il controllo qui
      } else if (_isBccUser && allowedFoldersForMe.isEmpty) {
        // BCC user ma tutor non ha impostazioni: fallback alle prefs
        if (!isVisiblePref) continue;
      }

      final images = dir
          .listSync()
          .whereType<File>()
          .where((file) =>
      file.path.toLowerCase().endsWith('.png') ||
          file.path.toLowerCase().endsWith('.jpg') ||
          file.path.toLowerCase().endsWith('.jpeg') ||
          file.path.toLowerCase().endsWith('.webp'))
          .map((file) => file.path)
          .toList();

      String? iconPath;
      final String lowerCaseFolderName = currentFolderName.toLowerCase();
      final potentialIconPathPng = '${dir.path}/$lowerCaseFolderName.png';
      final potentialIconPathJpg = '${dir.path}/$lowerCaseFolderName.jpg';
      final potentialIconPathJpeg = '${dir.path}/$lowerCaseFolderName.jpeg';
      final potentialIconPathWebp = '${dir.path}/$lowerCaseFolderName.webp';

      if (File(potentialIconPathPng).existsSync()) {
        iconPath = potentialIconPathPng;
      } else if (File(potentialIconPathJpg).existsSync()) {
        iconPath = potentialIconPathJpg;
      } else if (File(potentialIconPathJpeg).existsSync()) {
        iconPath = potentialIconPathJpeg;
      } else if (File(potentialIconPathWebp).existsSync()) {
        iconPath = potentialIconPathWebp;
      } else {
        if (images.isNotEmpty) {
          iconPath = images.first;
        }
      }

      if (images.isNotEmpty) {
        localFolders[currentFolderName] = FolderContent(
          name: currentFolderName,
          iconPath: iconPath,
          items: images,
          isLocal: true,
        );
      }
    }
  }

  // ----------------- LOAD FOLDERS (Firebase user personal) -----------------
  Future<void> _loadFirebaseUserFolder() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        firebaseUserFolder = null;
        return;
      }

      final userStickersRef = firebase_storage.FirebaseStorage.instance.ref('stickers/${user.uid}');
      final result = await userStickersRef.listAll();

      final urls = await Future.wait(result.items.map((item) => item.getDownloadURL()));

      String? iconUrl;
      try {
        final iconRef = userStickersRef.child('icon.png');
        iconUrl = await iconRef.getDownloadURL();
      } catch (_) {
        if (urls.isNotEmpty) iconUrl = urls.first;
      }

      if (urls.isNotEmpty) {
        firebaseUserFolder = FolderContent(
          name: 'I tuoi Sticker Personali',
          iconPath: iconUrl,
          items: urls,
          isLocal: false,
        );
      } else {
        firebaseUserFolder = null;
      }
    } catch (e) {
      print('Errore nel caricamento degli sticker personali da Firebase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Errore nel caricamento degli sticker personali.")),
        );
      }
      firebaseUserFolder = null;
    }
  }

  Future<void> _pickAndUploadSticker() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final fileName = path.basename(picked.path);
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Devi essere loggato per caricare sticker.")),
        );
      }
      return;
    }

    try {
      final firebaseRef = firebase_storage.FirebaseStorage.instance.ref('stickers/${user.uid}/$fileName');
      await firebaseRef.putFile(File(picked.path));
      await _loadFirebaseUserFolder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sticker caricato!")),
        );
      }
    } catch (e) {
      print('Errore nel caricamento dello sticker: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Errore nel caricamento dello sticker.")),
        );
      }
    }
  }

  // Funzione per navigare alla vista della cartella
  void _openFolderView(FolderContent folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StickerFolderView(
          folder: folder,
          onStickerSelected: widget.onStickerSelected,
        ),
      ),
    ).then((_) {
      // Ricarica le cartelle quando torni indietro dalla vista della cartella
      _loadFolders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleziona Sticker'),
        backgroundColor: Colors.blueAccent,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _pickAndUploadSticker,
              icon: const Icon(Icons.upload),
              label: const Text('Carica Sticker Personale'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  // Sezione per le cartelle locali
                  if (localFolders.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Sticker Locali',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, // Mostra 3 colonne di cartelle
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: localFolders.length,
                      itemBuilder: (context, index) {
                        final folderName = localFolders.keys.elementAt(index);
                        final folderContent = localFolders[folderName]!;
                        return _buildFolderTile(folderContent);
                      },
                    ),
                  ],

                  // Sezione per gli sticker personali su Firebase
                  if (firebaseUserFolder != null && firebaseUserFolder!.items.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'I tuoi Sticker Personali (Firebase)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                    ),
                    _buildFolderTile(firebaseUserFolder!),
                  ],

                  // Messaggio se non ci sono cartelle da mostrare
                  if (localFolders.isEmpty && (firebaseUserFolder == null || firebaseUserFolder!.items.isEmpty))
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text(
                        'Nessun sticker o cartella trovata. Carica il tuo primo sticker personale!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(FolderContent folder) {
    return GestureDetector(
      onTap: () => _openFolderView(folder),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: folder.iconPath != null
                      ? folder.isLocal
                      ? Image.file(
                    File(folder.iconPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder, size: 50, color: Colors.grey),
                  )
                      : CachedNetworkImage(
                    imageUrl: folder.iconPath!,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (context, url, error) => const Icon(Icons.folder_off, size: 50, color: Colors.red),
                  )
                      : const Icon(Icons.folder_open, size: 60, color: Colors.blue),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                folder.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}

// Classe di supporto per organizzare il contenuto delle cartelle
class FolderContent {
  final String name;
  final String? iconPath; // Può essere un percorso locale o un URL di Firebase
  final List<String> items; // Lista di percorsi locali o URL di Firebase
  final bool isLocal; // true se la cartella è locale, false se da Firebase

  FolderContent({
    required this.name,
    this.iconPath,
    required this.items,
    required this.isLocal,
  });
}
