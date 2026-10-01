import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/site.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';
import '../services/report_service.dart';
import '../widgets/empty_state.dart';
import 'defect_detail_screen.dart';
import 'defect_form_screen.dart';
import 'defect_resolution_screen.dart';

class AuditScreen extends StatefulWidget {
  final Site site;
  final Audit audit;

  const AuditScreen({
    super.key,
    required this.site,
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
  final Map<int, List<AuditPhoto>> _issuePhotos = {};
  final Map<int, List<AuditPhoto>> _resolutionPhotos = {};

  @override
  void initState() {
    super.initState();
    _audit = widget.audit;
    _load();
  }

  Future<void> _load() async {
    final freshAudit = await DatabaseService.instance.getAuditById(_audit.id!);
    final defects = await DatabaseService.instance.getDefectsForAudit(_audit.id!);
    final issuePhotos = await DatabaseService.instance.getPhotosForDefects(defects, kind: 'issue');
    final resolutionPhotos = await DatabaseService.instance.getPhotosForDefects(defects, kind: 'resolution');
    if (!mounted) return;
    setState(() {
      if (freshAudit != null) _audit = freshAudit;
      _defects = defects;
      _issuePhotos
        ..clear()
        ..addAll(issuePhotos);
      _resolutionPhotos
        ..clear()
        ..addAll(resolutionPhotos);
      _loading = false;
    });
  }

  Future<void> _addDefect() async {
    final next = await DatabaseService.instance.getNextPositionNo(_audit.id!);
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectFormScreen(auditId: _audit.id!, suggestedPosition: next),
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
          initialPhotos: _issuePhotos[defect.id] ?? const [],
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteDefect(Defect defect) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Usunąć pozycję ${defect.positionNo}?'),
        content: const Text('Usterka i cała jej dokumentacja zdjęciowa zostaną trwale usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (yes != true) return;
    for (final photo in [
      ...?_issuePhotos[defect.id],
      ...?_resolutionPhotos[defect.id],
    ]) {
      await PhotoService.deleteIfExists(photo.path);
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
          'Audyt zawiera ${_defects.length} usterek. Po zakończeniu będzie można potwierdzać usunięcie każdej usterki osobno.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zakończ')),
        ],
      ),
    );
    if (yes != true) return;

    final completed = _audit.copyWith(status: 'completed', completedAt: DateTime.now());
    await DatabaseService.instance.updateAudit(completed);
    await _load();
  }

  Future<void> _confirmResolution(Defect defect) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectResolutionScreen(
          defect: defect,
          initialPhotos: _resolutionPhotos[defect.id] ?? const [],
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
        content: const Text('Data, komentarz i zdjęcia potwierdzające usunięcie usterki zostaną usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cofnij')),
        ],
      ),
    );
    if (yes != true) return;
    for (final photo in _resolutionPhotos[defect.id] ?? const <AuditPhoto>[]) {
      await PhotoService.deleteIfExists(photo.path);
    }
    await DatabaseService.instance.replacePhotos(defect.id!, const [], kind: 'resolution');
    await DatabaseService.instance.clearDefectResolution(defect.id!);
    await _load();
  }

  Future<void> _deleteAudit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usunąć audyt?'),
        content: const Text('Audyt, wszystkie usterki, potwierdzenia ich usunięcia i zdjęcia zostaną trwale usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (yes != true) return;
    final paths = await DatabaseService.instance.getPhotoPathsForAudit(_audit.id!);
    for (final path in paths) {
      await PhotoService.deleteIfExists(path);
    }
    await DatabaseService.instance.deleteAudit(_audit.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _exportPackage() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final allPhotos = <int, List<AuditPhoto>>{};
      for (final defect in _defects) {
        final id = defect.id!;
        allPhotos[id] = [
          ...?_issuePhotos[id],
          ...?_resolutionPhotos[id],
        ];
      }

      final result = await AuditPackageService.exportForEmail(
        site: widget.site,
        audit: _audit,
        defects: _defects,
        photos: allPhotos,
      );
      if (!mounted) return;
      setState(() => _exporting = false);

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paczka audytu gotowa',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('${result.photosCount} zdjęć • ${result.sizeMb.toStringAsFixed(1)} MB'),
                const SizedBox(height: 6),
                const Text(
                  'Zdjęcia zostały skompresowane specjalnie do wysyłki. Odbiorca może zaimportować paczkę i potwierdzać usunięcie usterek.',
                ),
                if (result.sizeMb > 20) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Uwaga: paczka przekracza 20 MB. Niektóre skrzynki pocztowe mogą mieć niższy limit załącznika.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    await Share.shareXFiles(
                      [XFile(result.path)],
                      subject: 'Audyt ${widget.site.name}',
                      text: 'Paczka audytu do importu w aplikacji Audytor.',
                    );
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Wyślij / udostępnij paczkę'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się przygotować paczki: $e')),
      );
    }
  }

  Future<void> _generateReport() async {
    setState(() => _generating = true);
    try {
      final allPhotos = <int, List<AuditPhoto>>{};
      for (final defect in _defects) {
        final id = defect.id!;
        allPhotos[id] = [
          ...?_issuePhotos[id],
          ...?_resolutionPhotos[id],
        ];
      }
      final report = await ReportService.generate(
        site: widget.site,
        audit: _audit,
        defects: _defects,
        photos: allPhotos,
      );
      if (!mounted) return;
      setState(() => _generating = false);
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Aktualny raport PDF gotowy', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Raport został utworzony na podstawie bieżącego stanu audytu. Zdjęcia w PDF są pomniejszone i skompresowane, dzięki czemu plik zajmuje mniej miejsca.'),
                const SizedBox(height: 8),
                Text(report.filename),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => ReportService.share(report),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Udostępnij PDF'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => ReportService.printReport(report),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Drukuj / zapisz jako PDF'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie udało się wygenerować raportu: $e')));
    }
  }

  Color _priorityColor(String priority, ColorScheme scheme) {
    return switch (priority) {
      'Krytyczny' => scheme.error,
      'Wysoki' => Colors.orange.shade800,
      'Niski' => Colors.green.shade700,
      _ => scheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedCount = _defects.where((d) => d.isResolved).length;
    final openCount = _defects.length - resolvedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyt'),
        actions: [
          IconButton(
            tooltip: _audit.isCompleted ? 'Wygeneruj ponownie aktualny PDF' : 'Generuj PDF',
            onPressed: _generating ? null : _generateReport,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Eksportuj audyt do wysłania',
            onPressed: _exporting ? null : _exportPackage,
            icon: const Icon(Icons.outbox_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteAudit();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Usuń audyt')),
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
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.site.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(_audit.auditType),
                                  ],
                                ),
                              ),
                              Chip(
                                avatar: Icon(_audit.isCompleted ? Icons.check_circle : Icons.edit_note, size: 18),
                                label: Text(_audit.isCompleted ? 'Zakończony' : 'Roboczy'),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          _InfoRow(icon: Icons.person_outline, text: _audit.auditor),
                          const SizedBox(height: 8),
                          _InfoRow(icon: Icons.schedule, text: DateFormat('dd.MM.yyyy HH:mm').format(_audit.startedAt)),
                          if (_audit.notes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(_audit.notes),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _SummaryBox(label: 'Usunięte', value: '$resolvedCount', icon: Icons.task_alt)),
                              const SizedBox(width: 10),
                              Expanded(child: _SummaryBox(label: 'Do usunięcia', value: '$openCount', icon: Icons.pending_actions)),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _generating ? null : _generateReport,
                                icon: _generating
                                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.picture_as_pdf_outlined),
                                label: Text(
                                  _generating
                                      ? 'Tworzenie PDF…'
                                      : _audit.isCompleted
                                          ? 'Generuj aktualny PDF'
                                          : 'Raport PDF',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exporting ? null : _exportPackage,
                                icon: _exporting
                                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.outbox_outlined),
                                label: Text(_exporting ? 'Kompresowanie paczki…' : 'Eksportuj audyt'),
                              ),
                              if (!_audit.isCompleted)
                                OutlinedButton.icon(
                                  onPressed: _complete,
                                  icon: const Icon(Icons.task_alt),
                                  label: const Text('Zakończ audyt'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: Text('Usterki', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      Text('${_defects.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_defects.isEmpty)
                    SizedBox(
                      height: 380,
                      child: EmptyState(
                        icon: Icons.report_gmailerrorred_outlined,
                        title: 'Brak usterek',
                        subtitle: _audit.isCompleted
                            ? 'W tym audycie nie dodano usterek.'
                            : 'Dodaj usterkę wraz z opisem i co najmniej jednym zdjęciem.',
                        buttonLabel: _audit.isCompleted ? null : 'Dodaj usterkę',
                        onPressed: _audit.isCompleted ? null : _addDefect,
                      ),
                    )
                  else
                    ..._defects.map((defect) {
                      final issue = _issuePhotos[defect.id] ?? const <AuditPhoto>[];
                      final after = _resolutionPhotos[defect.id] ?? const <AuditPhoto>[];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DefectDetailScreen(
                                          defect: defect,
                                          photos: issue,
                                          resolutionPhotos: after,
                                        ),
                                      ),
                                    );
                                    await _load();
                                  },
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: issue.isNotEmpty && File(issue.first.path).existsSync()
                                            ? Image.file(File(issue.first.path), width: 86, height: 86, fit: BoxFit.cover)
                                            : Container(
                                                width: 86,
                                                height: 86,
                                                color: scheme.surfaceContainerHighest,
                                                child: const Icon(Icons.image_not_supported_outlined),
                                              ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(child: Text('Pozycja ${defect.positionNo}', style: const TextStyle(fontWeight: FontWeight.w800))),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _priorityColor(defect.priority, scheme).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(999),
                                                  ),
                                                  child: Text(defect.priority, style: TextStyle(color: _priorityColor(defect.priority, scheme), fontSize: 12, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                            ),
                                            if (defect.location.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(defect.location, style: Theme.of(context).textTheme.bodySmall),
                                            ],
                                            const SizedBox(height: 5),
                                            Text(defect.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 7),
                                            Text(
                                              after.isEmpty
                                                  ? '${issue.length} zdjęć z audytu'
                                                  : '${issue.length} zdjęć z audytu • ${after.length} zdjęć po usunięciu',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!_audit.isCompleted)
                                        PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') _editDefect(defect);
                                            if (value == 'delete') _deleteDefect(defect);
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'edit', child: Text('Edytuj')),
                                            PopupMenuItem(value: 'delete', child: Text('Usuń')),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                if (_audit.isCompleted) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(
                                        defect.isResolved ? Icons.check_circle : Icons.pending_actions,
                                        color: defect.isResolved ? Colors.green.shade700 : scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          defect.isResolved ? 'Usterka usunięta' : 'Usterka nieusunięta',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (defect.isResolved && defect.resolvedAt != null) ...[
                                    const SizedBox(height: 6),
                                    Text('Data usunięcia: ${DateFormat('dd.MM.yyyy HH:mm').format(defect.resolvedAt!)}'),
                                  ],
                                  if (defect.resolutionNote.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Komentarz: ${defect.resolutionNote}'),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: () => _confirmResolution(defect),
                                        icon: Icon(defect.isResolved ? Icons.edit_note : Icons.verified_outlined),
                                        label: Text(defect.isResolved ? 'Edytuj potwierdzenie' : 'Potwierdź usunięcie usterki'),
                                      ),
                                      if (defect.isResolved)
                                        OutlinedButton.icon(
                                          onPressed: () => _clearResolution(defect),
                                          icon: const Icon(Icons.undo),
                                          label: const Text('Cofnij potwierdzenie'),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryBox({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
