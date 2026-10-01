import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';

class DefectFormScreen extends StatefulWidget {
  final int auditId;
  final String suggestedPosition;
  final Defect? defect;
  final List<AuditPhoto> initialPhotos;

  const DefectFormScreen({
    super.key,
    required this.auditId,
    required this.suggestedPosition,
    this.defect,
    this.initialPhotos = const [],
  });

  @override
  State<DefectFormScreen> createState() => _DefectFormScreenState();
}

class _DefectFormScreenState extends State<DefectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _position;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _recommendation;
  late String _priority;
  late List<String> _existingPhotoPaths;
  final List<XFile> _newPhotos = [];
  bool _saving = false;

  static const priorities = ['Niski', 'Średni', 'Wysoki', 'Krytyczny'];

  @override
  void initState() {
    super.initState();
    _position = TextEditingController(text: widget.defect?.positionNo ?? widget.suggestedPosition);
    _location = TextEditingController(text: widget.defect?.location ?? '');
    _description = TextEditingController(text: widget.defect?.description ?? '');
    _recommendation = TextEditingController(text: widget.defect?.recommendation ?? '');
    _priority = widget.defect?.priority ?? 'Średni';
    _existingPhotoPaths = widget.initialPhotos.map((e) => e.path).toList();
  }

  @override
  void dispose() {
    _position.dispose();
    _location.dispose();
    _description.dispose();
    _recommendation.dispose();
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
                title: const Text('Zrób zdjęcie'),
                onTap: () {
                  Navigator.pop(context);
                  _camera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Dodaj z galerii'),
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
    if (_existingPhotoPaths.isEmpty && _newPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Każda usterka musi mieć co najmniej jedno zdjęcie.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final defect = Defect(
        id: widget.defect?.id,
        auditId: widget.auditId,
        positionNo: _position.text.trim(),
        location: _location.text.trim(),
        description: _description.text.trim(),
        priority: _priority,
        recommendation: _recommendation.text.trim(),
        createdAt: widget.defect?.createdAt ?? DateTime.now(),
        sourceDefectId: widget.defect?.sourceDefectId,
        isResolved: widget.defect?.isResolved ?? false,
        resolvedAt: widget.defect?.resolvedAt,
        resolutionNote: widget.defect?.resolutionNote ?? '',
      );

      late final int defectId;
      if (widget.defect == null) {
        defectId = await DatabaseService.instance.insertDefect(defect);
      } else {
        defectId = widget.defect!.id!;
        await DatabaseService.instance.updateDefect(defect);
      }

      final persisted = <String>[..._existingPhotoPaths];
      for (final file in _newPhotos) {
        persisted.add(await PhotoService.persistPickedFile(file));
      }

      if (widget.defect != null) {
        final original = widget.initialPhotos.map((e) => e.path).toSet();
        final kept = _existingPhotoPaths.toSet();
        for (final removed in original.difference(kept)) {
          await PhotoService.deleteIfExists(removed);
        }
      }

      await DatabaseService.instance.replacePhotos(defectId, persisted);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się zapisać usterki: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = _existingPhotoPaths.length + _newPhotos.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.defect == null ? 'Nowa usterka' : 'Edytuj usterkę')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _position,
                    decoration: const InputDecoration(labelText: 'Nr pozycji *', prefixIcon: Icon(Icons.tag)),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Podaj nr pozycji' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priorytet'),
                    items: priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (value) => setState(() => _priority = value ?? 'Średni'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Lokalizacja', prefixIcon: Icon(Icons.place_outlined)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Opis usterki *', alignLabelWithHint: true, prefixIcon: Icon(Icons.report_problem_outlined)),
              minLines: 4,
              maxLines: 8,
              validator: (v) => v == null || v.trim().isEmpty ? 'Dodaj opis usterki' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _recommendation,
              decoration: const InputDecoration(labelText: 'Zalecenie / sposób naprawy', alignLabelWithHint: true, prefixIcon: Icon(Icons.build_outlined)),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text('Zdjęcia *  ($photoCount)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showPhotoSource,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Dodaj'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Wymagane jest minimum jedno zdjęcie dla każdej usterki.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (photoCount == 0)
              Container(
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE3E8EE)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _showPhotoSource,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 42),
                      SizedBox(height: 8),
                      Text('Dodaj pierwsze zdjęcie'),
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
                            style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
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
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(widget.defect == null ? 'Zapisz usterkę' : 'Zapisz zmiany'),
            ),
          ],
        ),
      ),
    );
  }
}
