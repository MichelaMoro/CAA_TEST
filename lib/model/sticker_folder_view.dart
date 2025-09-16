import 'dart:io';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:path/path.dart' as path; // Alias per evitare conflitti, anche se qui meno probabile

import 'sticker_picker.dart';



class StickerFolderView extends StatelessWidget {

  final FolderContent folder;

  final Function(String stickerUrl, String stickerName) onStickerSelected;



  const StickerFolderView({

    Key? key,

    required this.folder,

    required this.onStickerSelected,

  }) : super(key: key);



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: Text(folder.name),

        backgroundColor: Colors.blueAccent,

      ),

      body: folder.items.isEmpty

          ? const Center(

        child: Text(

          'Nessuno sticker in questa cartella.',

          style: TextStyle(fontSize: 16, color: Colors.grey),

        ),

      )

          : GridView.builder(

        padding: const EdgeInsets.all(10),

        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(

          crossAxisCount: 3, // Numero di colonne per gli sticker

          mainAxisSpacing: 10,

          crossAxisSpacing: 10,

          childAspectRatio: 1,

        ),

        itemCount: folder.items.length,

        itemBuilder: (context, index) {

          final pathOrUrl = folder.items[index];

          final name = folder.isLocal ? path.basename(pathOrUrl) : 'Firebase_${index + 1}'; // Usa path.basename



          return GestureDetector(

            onTap: () {

              onStickerSelected(pathOrUrl, name);

              Navigator.pop(context); // Torna alla pagina precedente (StickerPicker)

              Navigator.pop(context); // E poi esce anche da StickerPicker

            },

            child: Card(

              elevation: 3,

              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

              child: ClipRRect(

                borderRadius: BorderRadius.circular(12),

                child: folder.isLocal

                    ? Image.file(File(pathOrUrl), fit: BoxFit.cover)

                    : CachedNetworkImage(

                  imageUrl: pathOrUrl,

                  fit: BoxFit.cover,

                  placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),

                  errorWidget: (context, url, error) => const Icon(Icons.error_outline, color: Colors.red),

                ),

              ),

            ),

          );

        },

      ),

    );

  }

}