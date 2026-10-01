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

  const DefectResolutionScreen({
    super.key,
    required this.defect,
    this.initialPhotos = const [],
  });

  @override
  State<DefectResolutionScreen> createState() => _DefectResolutionScreenState();
}

class _DefectResolutionScreenState extends State<DefectResolutionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _note;
  late List<String> _existingPhotoPaths;
  final List<XFile> _newPhotos = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.defect.resolutionNote);
    _existingPhotoPaths = widget.initialPhotos.map((e) => e.path).toList();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _camera() async {
    final file = await PhotoService.takePhoto();
    if (file != null && mounted) setState(() => _newPhotos.add(file));
  }

  Future<void> _gallery() async {
    final files = await PhotoService.pickFromGallery();
    if (files.isNotEmpty && mounted) setState(() => _newPhotos.addAll(files));
  }

  Future<void> _showPhotoSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Zrób zdjęcie po usunięciu'),
                onTap: () {
                  Navigator.pop(context);
                  _camera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Dodaj zdjęcie po usunięciu z galerii'),
                onTap: () {
                  Navigator.pop(context);
                  _gallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final persisted = <String>[..._existingPhotoPaths];
      for (final file in _newPhotos) {
        persisted.add(await PhotoService.persistPickedFile(file));
      }

      final original = widget.initialPhotos.map((e) => e.path).toSet();
      final kept = _existingPhotoPaths.toSet();
      for (final removed in original.difference(kept)) {
        await PhotoService.deleteIfExists(removed);
      }

      await DatabaseService.instance.confirmDefectResolution(
        widget.defect.id!,
        _note.text,
      );
      await DatabaseService.instance.replacePhotos(
        widget.defect.id!,
        persisted,
        kind: 'resolution',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się zapisać potwierdzenia: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = _existingPhotoPaths.length + _newPhotos.length;
    return Scaffold(
      appBar: AppBar(title: Text('Potwierdzenie usunięcia • pozycja ${widget.defect.positionNo}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usterka z audytu',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.defect.description),
                    if (widget.defect.location.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Lokalizacja: ${widget.defect.location}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Komentarz po usunięciu usterki *',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.task_alt_outlined),
                helperText: 'Np. wymieniono element, poprawiono mocowanie, usterka została usunięta.',
              ),
              minLines: 4,
              maxLines: 8,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Komentarz jest wymagany do potwierdzenia usunięcia usterki'
                  : null,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Zdjęcia po usunięciu ($photoCount)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showPhotoSource,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Dodaj'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Zdjęcie jest opcjonalne. Możesz dodać jedno lub kilka zdjęć potwierdzających usunięcie usterki.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (photoCount == 0)
              Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _showPhotoSource,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 38),
                      SizedBox(height: 8),
                      Text('Dodaj zdjęcie po usunięciu'),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: photoCount,
                itemBuilder: (context, index) {
                  final isExisting = index < _existingPhotoPaths.length;
                  final path = isExisting
                      ? _existingPhotoPaths[index]
                      : _newPhotos[index - _existingPhotoPaths.length].path;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(path), fit: BoxFit.cover),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              setState(() {
                                if (isExisting) {
                                  _existingPhotoPaths.removeAt(index);
                                } else {
                                  _newPhotos.removeAt(index - _existingPhotoPaths.length);
                                }
                              });
                            },
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(widget.defect.isResolved ? 'Zapisz zmianę potwierdzenia' : 'Potwierdź usunięcie usterki'),
            ),
          ],
        ),
      ),
    );
  }
}
