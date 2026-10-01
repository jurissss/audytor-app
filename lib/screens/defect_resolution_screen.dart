import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';

class DefectResolutionScreen extends StatefulWidget {
  final Defect defect;
  final List<AuditPhoto> initialPhotos;
  const DefectResolutionScreen({super.key, required this.defect, this.initialPhotos = const []});

  @override
  State<DefectResolutionScreen> createState() => _DefectResolutionScreenState();
}

class _DefectResolutionScreenState extends State<DefectResolutionScreen> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _note;
  late List<String> _existing;
  final List<XFile> _newPhotos = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.defect.resolutionNote);
    _existing = widget.initialPhotos.where((x) => x.isResolution).map((x) => x.path).toList();
  }

  @override
  void dispose() { _note.dispose(); super.dispose(); }

  Future<void> _camera() async {
    final file = await PhotoService.takePhoto();
    if (file != null && mounted) setState(() => _newPhotos.add(file));
  }

  Future<void> _gallery() async {
    final files = await PhotoService.pickFromGallery();
    if (files.isNotEmpty && mounted) setState(() => _newPhotos.addAll(files));
  }

  Future<void> _showSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Zrób zdjęcie po naprawie'),
              onTap: () { Navigator.pop(ctx); _camera(); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Dodaj z galerii'),
              onTap: () { Navigator.pop(ctx); _gallery(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final persisted = <String>[..._existing];
      for (final file in _newPhotos) {
        persisted.add(await PhotoService.persistPickedFile(file));
      }
      final kept = _existing.toSet();
      for (final old in widget.initialPhotos.where((x) => x.isResolution)) {
        if (!kept.contains(old.path)) await PhotoService.deleteIfExists(old.path);
      }
      await DatabaseService.instance.replacePhotos(widget.defect.id!, persisted, kind: 'resolution');
      await DatabaseService.instance.confirmDefectResolution(widget.defect.id!, _note.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się zapisać potwierdzenia: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _existing.length + _newPhotos.length;
    return Scaffold(
      appBar: AppBar(title: Text('Usunięcie usterki ${widget.defect.positionNo}')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Potwierdzenie usunięcia usterki', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Komentarz jest obowiązkowy. Zdjęcia po naprawie są opcjonalne.'),
            const SizedBox(height: 18),
            TextFormField(
              controller: _note,
              minLines: 4, maxLines: 8,
              decoration: const InputDecoration(labelText: 'Komentarz po usunięciu *', alignLabelWithHint: true),
              validator: (value) => value == null || value.trim().isEmpty ? 'Dodaj komentarz potwierdzający usunięcie' : null,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('Zdjęcia po naprawie ($count)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                FilledButton.tonalIcon(onPressed: _showSource, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Dodaj')),
              ],
            ),
            const SizedBox(height: 10),
            if (count > 0)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: count,
                itemBuilder: (_, index) {
                  final isExisting = index < _existing.length;
                  final path = isExisting ? _existing[index] : _newPhotos[index - _existing.length].path;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: const Color(0xFFECEFF2), child: Image.file(File(path), fit: BoxFit.contain)),
                        Positioned(
                          right: 6, top: 6,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                            onPressed: () => setState(() {
                              if (isExisting) {
                                _existing.removeAt(index);
                              } else {
                                _newPhotos.removeAt(index - _existing.length);
                              }
                            }),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
              label: const Text('Potwierdź usunięcie usterki'),
            ),
          ],
        ),
      ),
    );
  }
}
