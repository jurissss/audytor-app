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

  late List<String> _issueExisting;
  late List<String> _plateExisting;
  final List<XFile> _issueNew = [];
  final List<XFile> _plateNew = [];
  bool _noNameplate = false;
  bool _saving = false;

  static const priorities = ['Niski', 'Średni', 'Wysoki', 'Krytyczny'];

  @override
  void initState() {
    super.initState();
    _position = TextEditingController(
        text: widget.defect?.positionNo ?? widget.suggestedPosition);
    _location = TextEditingController(text: widget.defect?.location ?? '');
    _description =
        TextEditingController(text: widget.defect?.description ?? '');
    _recommendation =
        TextEditingController(text: widget.defect?.recommendation ?? '');
    _priority = widget.defect?.priority ?? 'Średni';
    _issueExisting = widget.initialPhotos
        .where((x) => x.kind == 'issue')
        .map((x) => x.path)
        .toList();
    _plateExisting = widget.initialPhotos
        .where((x) => x.kind == 'nameplate')
        .map((x) => x.path)
        .toList();

    // Dla starych usterek bez osobnej tabliczki nie blokujemy edycji.
    _noNameplate = widget.defect != null && _plateExisting.isEmpty;
  }

  @override
  void dispose() {
    _position.dispose();
    _location.dispose();
    _description.dispose();
    _recommendation.dispose();
    super.dispose();
  }

  Future<void> _pick(bool plate, ImageSource source) async {
    if (source == ImageSource.camera) {
      final file = await PhotoService.takePhoto();
      if (file != null && mounted) {
        setState(() {
          (plate ? _plateNew : _issueNew).add(file);
          if (plate) _noNameplate = false;
        });
      }
    } else {
      final files = await PhotoService.pickFromGallery();
      if (files.isNotEmpty && mounted) {
        setState(() {
          (plate ? _plateNew : _issueNew).addAll(files);
          if (plate) _noNameplate = false;
        });
      }
    }
  }

  Future<void> _source(bool plate) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(plate
                  ? 'Zrób zdjęcie tabliczki znamionowej'
                  : 'Zrób zdjęcie usterki'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(plate, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Dodaj z galerii'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(plate, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _persist(
      List<String> existing, List<XFile> fresh) async {
    final result = <String>[...existing];
    for (final file in fresh) {
      result.add(await PhotoService.persistPickedFile(file));
    }
    return result;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_issueExisting.isEmpty && _issueNew.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Każda usterka musi mieć co najmniej jedno zdjęcie.')));
      return;
    }

    if (!_noNameplate && _plateExisting.isEmpty && _plateNew.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Dodaj zdjęcie tabliczki znamionowej albo zaznacz „Brak tabliczki znamionowej”.'),
      ));
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

      final issues = await _persist(_issueExisting, _issueNew);
      final plates =
          _noNameplate ? <String>[] : await _persist(_plateExisting, _plateNew);

      if (widget.defect != null) {
        final kept = {...issues, ...plates};
        for (final old in widget.initialPhotos
            .where((x) => x.kind == 'issue' || x.kind == 'nameplate')) {
          if (!kept.contains(old.path)) {
            await PhotoService.deleteIfExists(old.path);
          }
        }
      }

      await DatabaseService.instance
          .replacePhotos(defectId, issues, kind: 'issue');
      await DatabaseService.instance
          .replacePhotos(defectId, plates, kind: 'nameplate');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nie udało się zapisać usterki: $e')));
    }
  }

  Widget _photos(
      String title, List<String> existing, List<XFile> fresh, bool plate) {
    final count = existing.length + fresh.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: Text('$title  ($count)',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          FilledButton.tonalIcon(
              onPressed: () => _source(plate),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Dodaj')),
        ]),
        const SizedBox(height: 10),
        if (count > 0)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10),
            itemCount: count,
            itemBuilder: (context, index) {
              final isExisting = index < existing.length;
              final path = isExisting
                  ? existing[index]
                  : fresh[index - existing.length].path;
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(fit: StackFit.expand, children: [
                  Container(
                    color: const Color(0xFFECEFF2),
                    child: Image.file(File(path), fit: BoxFit.contain),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white),
                      onPressed: () => setState(() {
                        if (isExisting) {
                          existing.removeAt(index);
                        } else {
                          fresh.removeAt(index - existing.length);
                        }
                      }),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  )
                ]),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.defect == null ? 'Nowa usterka' : 'Edytuj usterkę')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _position,
                  decoration: const InputDecoration(
                      labelText: 'Nr pozycji *',
                      prefixIcon: Icon(Icons.tag)),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Podaj nr pozycji'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priorytet'),
                  items: priorities
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (x) =>
                      setState(() => _priority = x ?? 'Średni'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                  labelText: 'Lokalizacja',
                  prefixIcon: Icon(Icons.place_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                  labelText: 'Opis usterki *',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.report_problem_outlined)),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Dodaj opis usterki'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _recommendation,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                  labelText: 'Zalecenie / sposób naprawy',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.build_outlined)),
            ),
            const SizedBox(height: 22),
            _photos('Zdjęcia usterki *', _issueExisting, _issueNew, false),
            const SizedBox(height: 26),
            const Divider(),
            const SizedBox(height: 16),
            _photos('Tabliczka znamionowa *',
                _plateExisting, _plateNew, true),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _noNameplate,
              title: const Text('Brak tabliczki znamionowej'),
              subtitle: const Text(
                  'Zaznacz, jeżeli urządzenie nie ma dostępnej tabliczki znamionowej.'),
              onChanged: (value) => setState(() {
                _noNameplate = value ?? false;
              }),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(widget.defect == null
                  ? 'Zapisz usterkę'
                  : 'Zapisz zmiany'),
            ),
          ],
        ),
      ),
    );
  }
}
