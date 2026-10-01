import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/defect_note.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';
import '../services/report_service.dart';
import 'defect_form_screen.dart';
import 'defect_note_screen.dart';
import 'defect_resolution_screen.dart';
import 'photo_viewer_screen.dart';

class AuditScreen extends StatefulWidget {
  final Audit audit;

  const AuditScreen({
    super.key,
    required this.audit,
  });

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late Audit _audit;
  bool _loading = true;
  bool _generating = false;
  bool _exporting = false;
  List<Defect> _defects = [];
  final Map<int, List<AuditPhoto>> _photos = {};
  final Map<int, List<DefectNote>> _notes = {};

  @override
  void initState() {
    super.initState();
    _audit = widget.audit;
    _load();
  }

  Future<void> _load() async {
    final freshAudit = await DatabaseService.instance.getAuditById(_audit.id!);
    final defects = await DatabaseService.instance.getDefectsForAudit(_audit.id!);
    final photos = await DatabaseService.instance.getPhotosForDefects(defects);
    final notes = await DatabaseService.instance.getNotesForDefects(defects);

    if (!mounted) return;
    setState(() {
      if (freshAudit != null) _audit = freshAudit;
      _defects = defects;
      _photos
        ..clear()
        ..addAll(photos);
      _notes
        ..clear()
        ..addAll(notes);
      _loading = false;
    });
  }

  Future<void> _addDefect() async {
    final next = await DatabaseService.instance.getNextPositionNo(_audit.id!);
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectFormScreen(
          auditId: _audit.id!,
          suggestedPosition: next,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editDefect(Defect defect) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectFormScreen(
          auditId: _audit.id!,
          suggestedPosition: defect.positionNo,
          defect: defect,
          initialPhotos: _photos[defect.id] ?? const <AuditPhoto>[],
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _addNote(Defect defect) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DefectNoteScreen(defect: defect)),
    );
    if (changed == true) await _load();
  }

  Future<void> _confirmResolution(Defect defect) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectResolutionScreen(
          defect: defect,
          initialPhotos: _photos[defect.id] ?? const <AuditPhoto>[],
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _clearResolution(Defect defect) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cofnąć potwierdzenie usunięcia?'),
        content: const Text(
          'Data, komentarz i zdjęcia po naprawie zostaną usunięte. Historia uwag pozostanie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cofnij'),
          ),
        ],
      ),
    );

    if (yes != true) return;

    final resolutionPhotos = (_photos[defect.id] ?? const <AuditPhoto>[])
        .where((x) => x.isResolution)
        .toList();

    for (final photo in resolutionPhotos) {
      await PhotoService.deleteIfExists(photo.path);
    }

    await DatabaseService.instance.replacePhotos(
      defect.id!,
      const [],
      kind: 'resolution',
    );
    await DatabaseService.instance.clearDefectResolution(defect.id!);
    await _load();
  }

  Future<void> _deleteDefect(Defect defect) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Usunąć pozycję ${defect.positionNo}?'),
        content: const Text(
          'Usterka, historia uwag i cała dokumentacja zdjęciowa zostaną trwale usunięte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    for (final photo in _photos[defect.id] ?? const <AuditPhoto>[]) {
      await PhotoService.deleteIfExists(photo.path);
    }
    for (final note in _notes[defect.id] ?? const <DefectNote>[]) {
      for (final path in note.photoPaths) {
        await PhotoService.deleteIfExists(path);
      }
    }

    await DatabaseService.instance.deleteDefect(defect.id!);
    await _load();
  }

  Future<void> _complete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Zakończyć audyt?'),
        content: Text(
          'Audyt zawiera ${_defects.length} usterek. Po zakończeniu można potwierdzać usunięcie oraz dodawać uwagi do nieusuniętych usterek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zakończ'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    await DatabaseService.instance.updateAudit(
      _audit.copyWith(
        status: 'completed',
        completedAt: DateTime.now(),
      ),
    );
    await _load();
  }

  Future<void> _deleteAudit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usunąć audyt?'),
        content: const Text(
          'Audyt, wszystkie usterki, uwagi i zdjęcia zostaną trwale usunięte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    final paths = await DatabaseService.instance.getPhotoPathsForAudit(_audit.id!);
    for (final path in paths) {
      await PhotoService.deleteIfExists(path);
    }
    await DatabaseService.instance.deleteAudit(_audit.id!);

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _generateReport() async {
    if (_generating) return;
    setState(() => _generating = true);

    try {
      final reportBatch = await ReportService.generate(
        audit: _audit,
        defects: _defects,
        photos: _photos,
        notes: _notes,
      );

      if (!mounted) return;
      setState(() => _generating = false);

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  reportBatch.isSplit
                      ? 'Raport podzielony na ${reportBatch.parts.length} części'
                      : 'Aktualny raport PDF gotowy',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  reportBatch.parts
                      .map(
                        (part) =>
                            '${part.filename} • ${(part.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
                      )
                      .join('\n'),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    await Share.shareXFiles(
                      reportBatch.parts.map((part) => XFile(part.path)).toList(),
                      subject: 'Raport audytu ${_audit.client} ${_audit.storeNumber}',
                    );
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    reportBatch.isSplit
                        ? 'Udostępnij wszystkie części'
                        : 'Udostępnij PDF',
                  ),
                ),
                const SizedBox(height: 8),
                if (reportBatch.parts.length == 1)
                  OutlinedButton.icon(
                    onPressed: () => ReportService.printReport(reportBatch.parts.first),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Drukuj / zapisz jako PDF'),
                  )
                else
                  ...reportBatch.parts.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton.icon(
                        onPressed: () => ReportService.printReport(entry.value),
                        icon: const Icon(Icons.print_outlined),
                        label: Text('Drukuj część ${entry.key + 1}'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się wygenerować raportu: $e')),
      );
    }
  }

  Future<void> _exportPackage() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final result = await AuditPackageService.exportForEmail(
        audit: _audit,
        defects: _defects,
        photos: _photos,
        notes: _notes,
      );

      if (!mounted) return;
      setState(() => _exporting = false);

      await Share.shareXFiles(
        [XFile(result.path)],
        subject: 'Audyt ${_audit.client} ${_audit.storeNumber}',
        text: 'Paczka audytu do importu w aplikacji Audytor.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się przygotować paczki: $e')),
      );
    }
  }

  void _openPhotos(List<AuditPhoto> photos, int index) {
    if (photos.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          photos: photos,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final resolved = _defects.where((x) => x.isResolved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyt'),
        actions: [
          IconButton(
            tooltip: 'Generuj PDF',
            onPressed: _generating ? null : _generateReport,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Eksportuj audyt',
            onPressed: _exporting ? null : _exportPackage,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.outbox_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteAudit();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Usuń audyt'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: !_audit.isCompleted
          ? FloatingActionButton.extended(
              onPressed: _addDefect,
              icon: const Icon(Icons.add),
              label: const Text('Dodaj usterkę'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _audit.client,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text('Numer sklepu: ${_audit.storeNumber}'),
                          Text('Adres: ${_audit.address}'),
                          Text('Audytor: ${_audit.auditor}'),
                          Text('Data: ${dateFormat.format(_audit.startedAt)}'),
                          const SizedBox(height: 8),
                          Text(
                            '${_defects.length} usterek • $resolved usuniętych',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (!_audit.isCompleted) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _complete,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Zakończ audyt'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_defects.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Brak usterek. Dodaj pierwszą pozycję.'),
                      ),
                    ),
                  ..._defects.map((defect) {
                    final defectPhotos =
                        _photos[defect.id] ?? const <AuditPhoto>[];
                    final defectNotes =
                        _notes[defect.id] ?? const <DefectNote>[];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${defect.positionNo} • ${defect.location.isEmpty ? 'Usterka' : defect.location}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (defect.isResolved)
                                    const Chip(label: Text('Usunięta')),
                                  if (!_audit.isCompleted)
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _editDefect(defect);
                                        if (value == 'delete') _deleteDefect(defect);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edytuj'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Usuń'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(defect.description),
                              if (defect.recommendation.trim().isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text('Zalecenie: ${defect.recommendation}'),
                              ],
                              if (defect.isResolved) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Usunięto: ${defect.resolvedAt == null ? '' : dateFormat.format(defect.resolvedAt!)}\n${defect.resolutionNote}',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (defectPhotos.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 82,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: defectPhotos.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (_, index) => GestureDetector(
                                      onTap: () => _openPhotos(defectPhotos, index),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.file(
                                          File(defectPhotos[index].path),
                                          width: 100,
                                          height: 82,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (defectNotes.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                const Divider(),
                                Text(
                                  'Historia uwag (${defectNotes.length})',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                ...defectNotes.reversed.map((note) {
                                  final notePhotos = note.photoPaths
                                      .map(
                                        (path) => AuditPhoto(
                                          defectId: defect.id!,
                                          path: path,
                                          createdAt: note.createdAt,
                                          kind: 'note',
                                        ),
                                      )
                                      .toList();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F7F9),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            dateFormat.format(note.createdAt),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (note.text.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(note.text),
                                          ],
                                          if (notePhotos.isNotEmpty) ...[
                                            const SizedBox(height: 7),
                                            Wrap(
                                              spacing: 7,
                                              runSpacing: 7,
                                              children: notePhotos.asMap().entries.map((entry) {
                                                return GestureDetector(
                                                  onTap: () => _openPhotos(
                                                    notePhotos,
                                                    entry.key,
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.file(
                                                      File(entry.value.path),
                                                      width: 72,
                                                      height: 58,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                              if (_audit.isCompleted) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!defect.isResolved)
                                      FilledButton.tonalIcon(
                                        onPressed: () => _confirmResolution(defect),
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('Potwierdź usunięcie'),
                                      )
                                    else
                                      FilledButton.tonalIcon(
                                        onPressed: () => _confirmResolution(defect),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Edytuj potwierdzenie'),
                                      ),
                                    if (!defect.isResolved)
                                      OutlinedButton.icon(
                                        onPressed: () => _addNote(defect),
                                        icon: const Icon(Icons.note_add_outlined),
                                        label: const Text('Dodaj uwagę'),
                                      ),
                                    if (defect.isResolved)
                                      TextButton(
                                        onPressed: () => _clearResolution(defect),
                                        child: const Text('Cofnij usunięcie'),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
