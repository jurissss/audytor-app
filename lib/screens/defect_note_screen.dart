import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/defect.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';

class DefectNoteScreen extends StatefulWidget {
  final Defect defect;
  const DefectNoteScreen({super.key, required this.defect});

  @override
  State<DefectNoteScreen> createState() => _DefectNoteScreenState();
}

class _DefectNoteScreenState extends State<DefectNoteScreen> {
  final _note = TextEditingController();
  final List<XFile> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _camera() async {
    final file = await PhotoService.takePhoto();
    if (file != null && mounted) setState(() => _photos.add(file));
  }

  Future<void> _gallery() async {
    final files = await PhotoService.pickFromGallery();
    if (files.isNotEmpty && mounted) setState(() => _photos.addAll(files));
  }

  Future<void> _showSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Zrób zdjęcie'),
              onTap: () { Navigator.pop(sheetContext); _camera(); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Dodaj z galerii'),
              onTap: () { Navigator.pop(sheetContext); _gallery(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_note.text.trim().isEmpty && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dodaj uwagę lub co najmniej jedno zdjęcie.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final paths = <String>[];
      for (final photo in _photos) {
        paths.add(await PhotoService.persistPickedFile(photo));
      }
      await DatabaseService.instance.addDefectNote(
        defectId: widget.defect.id!,
        text: _note.text.trim(),
        photoPaths: paths,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się dodać uwagi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dodaj uwagę • ${widget.defect.positionNo}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Usterka nie została jeszcze usunięta', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Dodaj zdjęcie aktualnego stanu i/lub komentarz. Data zostanie zapisana automatycznie.'),
          const SizedBox(height: 18),
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Uwagi', alignLabelWithHint: true),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Zdjęcia (${_photos.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              FilledButton.tonalIcon(onPressed: _showSource, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Dodaj')),
            ],
          ),
          const SizedBox(height: 10),
          if (_photos.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: _photos.length,
              itemBuilder: (_, index) => ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_photos[index].path), fit: BoxFit.contain),
                    Positioned(
                      right: 6, top: 6,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                        onPressed: () => setState(() => _photos.removeAt(index)),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.note_add_outlined),
            label: const Text('Zapisz uwagę'),
          ),
        ],
      ),
    );
  }
}
