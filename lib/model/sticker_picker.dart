import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:path/path.dart' as path; // Alias per evitare conflitti con Flutter's 'Context'

import 'package:permission_handler/permission_handler.dart';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:path_provider/path_provider.dart'; // Import per getExternalStorageDirectory





import 'sticker_folder_view.dart';



class StickerPicker extends StatefulWidget {

  final Function(String stickerUrl, String stickerName) onStickerSelected;



  const StickerPicker({Key? key, required this.onStickerSelected}) : super(key: key);



  @override

  _StickerPickerState createState() => _StickerPickerState();

}



class _StickerPickerState extends State<StickerPicker> {

// Mappa per le cartelle locali: String (nome cartella) -> Map (icona, lista immagini)

// Utilizziamo un oggetto per tenere insieme URL/Path dell'icona e lista di sticker

  final Map<String, FolderContent> localFolders = {};

// Oggetto per la cartella sticker personali di Firebase

  FolderContent? firebaseUserFolder;



  final ScrollController _scrollController = ScrollController();

  final ImagePicker _picker = ImagePicker();

  final FirebaseAuth _auth = FirebaseAuth.instance;



// Inizializza con un valore di fallback, verrà sovrascritto dopo il caricamento asincrono

  Directory baseStickersDirectory = Directory('/storage/emulated/0/Download/Stickers');

  bool isLoading = true;



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



// 3. Carica le cartelle (locali e Firebase)

    await _loadFolders();



// 4. Aggiorna lo stato di caricamento

    setState(() => isLoading = false);

  }



  Future<void> _getAndSetBaseDirectory() async {

// Usiamo getExternalStorageDirectory per un percorso compatibile con Scoped Storage

// e per evitare problemi con l'accesso diretto a /storage/emulated/0/Download

    final Directory? appSpecificExternalDir = await getExternalStorageDirectory();

    if (appSpecificExternalDir != null) {

      baseStickersDirectory = Directory('${appSpecificExternalDir.path}/Download/Stickers');

    } else {

// Fallback o gestione errore se non è possibile ottenere la directory esterna

// Per esempio, potresti voler mostrare un messaggio all'utente o usare una directory temporanea.

      baseStickersDirectory = Directory('/storage/emulated/0/Download/Stickers'); // Fallback, meno affidabile su Android recenti

      print('WARNING: Could not get external storage directory, falling back to direct path. Permissions might be an issue.');

    }

  }



  Future<void> _requestPermissions() async {

    if (Platform.isAndroid) {

      final sdk = await DeviceInfoPlugin().androidInfo.then((info) => info.version.sdkInt);



      if (sdk >= 33) {

// Android 13 (API 33) e superiori usano permessi granulari per i media

        await Permission.photos.request();

        await Permission.videos.request(); // Aggiungi se scarichi anche video

      } else {

// Versioni precedenti usano il permesso di storage generale

        await Permission.storage.request();

      }

    }

// Per iOS, i permessi photo_library_add e photo_library sono gestiti automaticamente da image_picker e cached_network_image

  }



// Nuova funzione per caricare le cartelle e le loro icone/contenuti

  Future<void> _loadFolders() async {

    localFolders.clear();

    firebaseUserFolder = null; // Reset per ricaricare gli sticker Firebase



    if (!await baseStickersDirectory.exists()) {

      await baseStickersDirectory.create(recursive: true);

    }



    final subDirs = baseStickersDirectory.listSync().whereType<Directory>();

    final prefs = await SharedPreferences.getInstance();



    final String excludedFolderName = 'Stickers personali'; // Nome della cartella personale locale da escludere



    for (final dir in subDirs) {

      final String currentFolderName = path.basename(dir.path); // Usa path.basename



      if (currentFolderName == excludedFolderName) {

        continue; // Salta la cartella locale "Stickers personali"

      }



      final isVisible = prefs.getBool('visible_${dir.path}') ?? true;

      if (!isVisible) continue;



      final images = dir

          .listSync()

          .whereType<File>()

          .where((file) => file.path.endsWith('.png') || file.path.endsWith('.jpg') || file.path.endsWith('.jpeg') || file.path.endsWith('.webp'))

          .map((file) => file.path)

          .toList();



      String? iconPath;

// Cerca un'icona con il nome della cartella in minuscolo (es. "animals.png")

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

// Fallback se non si trova un'icona specifica: usa la prima immagine della cartella

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



// Carica la cartella degli sticker personali da Firebase

    await _loadFirebaseUserFolder();

  }



  Future<void> _loadFirebaseUserFolder() async {

    try {

      final user = _auth.currentUser;

      if (user == null) {

        firebaseUserFolder = null; // Nessun utente, nessuna cartella Firebase

        return;

      }



      final userStickersRef = FirebaseStorage.instance.ref('stickers/${user.uid}');

      final result = await userStickersRef.listAll();



      final urls = await Future.wait(result.items.map((item) => item.getDownloadURL()));



      String? iconUrl;

// Cerca un'icona specifica nella cartella Firebase (es. 'icon.png' o 'stickers_personali.png')

// Potresti definire una convenzione per l'icona della cartella Firebase

      try {

        final iconRef = userStickersRef.child('icon.png'); // Esempio di nome icona

        iconUrl = await iconRef.getDownloadURL();

      } catch (_) {

// Ignora l'errore se l'icona non esiste

// Se non trova 'icon.png', usa la prima immagine come fallback

        if (urls.isNotEmpty) {

          iconUrl = urls.first;

        }

      }



      if (urls.isNotEmpty) {

        firebaseUserFolder = FolderContent(

          name: 'I tuoi Sticker Personali',

          iconPath: iconUrl, // Sarà un URL per Firebase

          items: urls,

          isLocal: false,

        );

      } else {

        firebaseUserFolder = null; // Nessun sticker Firebase

      }



    } catch (e) {

      print('Errore nel caricamento degli sticker personali da Firebase: $e');

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(content: Text("Errore nel caricamento degli sticker personali.")),

        );

      }

      firebaseUserFolder = null; // Assicurati che sia null in caso di errore

    }

  }



  Future<void> _pickAndUploadSticker() async {

    final picked = await _picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;



    final fileName = path.basename(picked.path); // Usa path.basename

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

      final firebaseRef = FirebaseStorage.instance.ref('stickers/${user.uid}/$fileName');

      await firebaseRef.putFile(File(picked.path));



      await _loadFirebaseUserFolder(); // Ricarica solo la cartella Firebase dopo il caricamento



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

          Expanded( // Usa Expanded per far sì che la GridView riempia lo spazio rimanente

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

                        childAspectRatio: 0.8, // Regola per adattare icona e testo

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

// Qui la modifica: Rimuoviamo Expanded e usiamo SizedBox per dare un'altezza definita all'immagine

            SizedBox(

              height: 80, // Puoi regolare questa altezza a tuo piacimento

              width: 80, // E questa larghezza se vuoi che l'icona sia quadrata

              child: Padding(

                padding: const EdgeInsets.all(8.0),

                child: ClipRRect(

                  borderRadius: BorderRadius.circular(10),

                  child: folder.iconPath != null

                      ? folder.isLocal

                      ? Image.file(

                    File(folder.iconPath!),

                    fit: BoxFit.contain, // O BoxFit.cover, a seconda del tuo design

                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.folder, size: 50, color: Colors.grey),

                  )

                      : CachedNetworkImage(

                    imageUrl: folder.iconPath!,

                    fit: BoxFit.contain, // O BoxFit.cover

                    placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),

                    errorWidget: (context, url, error) => const Icon(Icons.folder_off, size: 50, color: Colors.red),

                  )

                      : const Icon(Icons.folder_open, size: 60, color: Colors.blue), // Icona di fallback se non c'è immagine

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