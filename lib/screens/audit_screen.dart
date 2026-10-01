import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/site.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';
import '../services/report_service.dart';
import 'defect_form_screen.dart';
import 'defect_resolution_screen.dart';
import 'photo_viewer_screen.dart';

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
  final Map<int, List<AuditPhoto>> _photos = {};

  @override
  void initState() {
    super.initState();
    _audit = widget.audit;
    _load();
  }

  Future<void> _load() async {
    final freshAudit =
        await DatabaseService.instance.getAuditById(_audit.id!);
    final defects =
        await DatabaseService.instance.getDefectsForAudit(_audit.id!);
    final photos =
        await DatabaseService.instance.getPhotosForDefects(defects);

    if (!mounted) return;

    setState(() {
      if (freshAudit != null) _audit = freshAudit;
      _defects = defects;
      _photos
        ..clear()
        ..addAll(photos);
      _loading = false;
    });
  }

  Future<void> _addDefect() async {
    final next =
        await DatabaseService.instance.getNextPositionNo(_audit.id!);

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
          initialPhotos:
              _photos[defect.id] ?? const <AuditPhoto>[],
        ),
      ),
    );

    if (changed == true) await _load();
  }

  Future<void> _deleteDefect(Defect defect) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Usunąć pozycję ${defect.positionNo}?',
        ),
        content: const Text(
          'Usterka i cała jej dokumentacja zdjęciowa zostaną trwale usunięte.',
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

    for (final photo
        in _photos[defect.id] ?? const <AuditPhoto>[]) {
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
          'Audyt zawiera ${_defects.length} usterek. Po zakończeniu można nadal generować raport oraz potwierdzać usunięcie usterek.',
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

  Future<void> _confirmResolution(Defect defect) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DefectResolutionScreen(
          defect: defect,
          initialPhotos:
              _photos[defect.id] ?? const <AuditPhoto>[],
        ),
      ),
    );

    if (changed == true) await _load();
  }

  Future<void> _clearResolution(Defect defect) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Cofnąć potwierdzenie usunięcia?',
        ),
        content: const Text(
          'Data, komentarz i zdjęcia po naprawie zostaną usunięte.',
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

    final resolutionPhotos =
        (_photos[defect.id] ?? const <AuditPhoto>[])
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

    await DatabaseService.instance
        .clearDefectResolution(defect.id!);

    await _load();
  }

  Future<void> _deleteAudit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usunąć audyt?'),
        content: const Text(
          'Audyt, wszystkie usterki, potwierdzenia usunięcia i zdjęcia zostaną trwale usunięte.',
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

    final paths =
        await DatabaseService.instance.getPhotoPathsForAudit(
      _audit.id!,
    );

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
      final report = await ReportService.generate(
        site: widget.site,
        audit: _audit,
        defects: _defects,
        photos: _photos,
      );

      if (!mounted) return;

      setState(() => _generating = false);

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aktualny raport PDF gotowy',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Raport został utworzony na podstawie bieżącego stanu audytu, w tym potwierdzonych napraw.',
                ),
                const SizedBox(height: 8),
                Text(report.filename),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () =>
                      ReportService.share(report),
                  icon:
                      const Icon(Icons.share_outlined),
                  label:
                      const Text('Udostępnij PDF'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      ReportService.printReport(report),
                  icon:
                      const Icon(Icons.print_outlined),
                  label: const Text(
                    'Drukuj / zapisz jako PDF',
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
        SnackBar(
          content: Text(
            'Nie udało się wygenerować raportu: $e',
          ),
        ),
      );
    }
  }

  Future<void> _exportPackage() async {
    if (_exporting) return;

    setState(() => _exporting = true);

    try {
      final result =
          await AuditPackageService.exportForEmail(
        site: widget.site,
        audit: _audit,
        defects: _defects,
        photos: _photos,
      );

      if (!mounted) return;

      setState(() => _exporting = false);

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paczka audytu gotowa',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${result.photosCount} zdjęć • ${result.sizeMb.toStringAsFixed(1)} MB',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Paczka zawiera raport PDF, galerię HTML, manifest oraz skompresowane zdjęcia. Może zostać przesłana innemu użytkownikowi Audytora.',
                ),
                if (result.sizeMb > 20) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Uwaga: paczka przekracza 20 MB. Niektóre skrzynki pocztowe mogą mieć niższy limit.',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    await Share.shareXFiles(
                      [XFile(result.path)],
                      subject:
                          'Audyt ${widget.site.name}',
                      text:
                          'Paczka audytu do importu w aplikacji Audytor.',
                    );
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: const Text(
                    'Wyślij / udostępnij paczkę',
                  ),
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
        SnackBar(
          content: Text(
            'Nie udało się przygotować paczki: $e',
          ),
        ),
      );
    }
  }

  Color _priorityColor(
    String priority,
    ColorScheme scheme,
  ) {
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
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    final resolved =
        _defects.where((x) => x.isResolved).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyt'),
        actions: [
          IconButton(
            tooltip: 'Generuj aktualny PDF',
            onPressed:
                _generating ? null : _generateReport,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.picture_as_pdf_outlined,
                  ),
          ),
          IconButton(
            tooltip:
                'Eksportuj audyt do wysłania',
            onPressed:
                _exporting ? null : _exportPackage,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.outbox_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteAudit();
              }
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
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  110,
                ),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.site.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(_audit.auditType),
                          const SizedBox(height: 5),
                          Text(
                            '${dateFormat.format(_audit.startedAt)} • ${_audit.auditor}',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  '${_defects.length} usterek',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  '$resolved usuniętych',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  _audit.isCompleted
                                      ? 'Audyt zakończony'
                                      : 'Audyt w trakcie',
                                ),
                              ),
                            ],
                          ),
                          if (!_audit.isCompleted) ...[
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: _complete,
                              icon: const Icon(
                                Icons.check_circle_outline,
                              ),
                              label: const Text(
                                'Zakończ audyt',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_defects.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Brak usterek. Dodaj pierwszą pozycję.',
                        ),
                      ),
                    ),
                  ..._defects.map(
                    (defect) {
                      final all = _photos[defect.id] ??
                          const <AuditPhoto>[];
                      final issueCount = all
                          .where((x) => x.isIssue)
                          .length;
                      final plateCount = all
                          .where((x) => x.isNameplate)
                          .length;
                      final resolutionCount = all
                          .where((x) => x.isResolution)
                          .length;

                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 10,
                        ),
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(
                                            'Poz. ${defect.positionNo}',
                                            style: Theme.of(
                                                    context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight:
                                                      FontWeight
                                                          .w700,
                                                ),
                                          ),
                                          if (defect.location
                                              .isNotEmpty)
                                            Text(
                                              defect.location,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration:
                                          BoxDecoration(
                                        color:
                                            _priorityColor(
                                          defect.priority,
                                          scheme,
                                        ),
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          20,
                                        ),
                                      ),
                                      child: Text(
                                        defect.priority,
                                        style:
                                            const TextStyle(
                                          color:
                                              Colors.white,
                                          fontWeight:
                                              FontWeight
                                                  .w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(defect.description),
                                if (defect
                                    .recommendation
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 7),
                                  Text(
                                    'Zalecenie: ${defect.recommendation}',
                                    style:
                                        const TextStyle(
                                      color:
                                          Color(0xFF526579),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Text(
                                  'Zdjęcia: usterka $issueCount • tabliczka ${defect.nameplateUnavailable ? "brak" : plateCount} • po naprawie $resolutionCount',
                                  style:
                                      const TextStyle(
                                    fontSize: 12,
                                    color:
                                        Color(0xFF66788A),
                                  ),
                                ),
                                if (all.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 92,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: all.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (_, photoIndex) {
                                        final photo = all[photoIndex];
                                        final label = switch (photo.kind) {
                                          'nameplate' => 'Tabliczka',
                                          'resolution' => 'Po naprawie',
                                          _ => 'Usterka',
                                        };
                                        return InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onTap: () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => PhotoViewerScreen(
                                                photos: all,
                                                initialIndex: photoIndex,
                                              ),
                                            ),
                                          ),
                                          child: SizedBox(
                                            width: 112,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  Image.file(
                                                    File(photo.path),
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) =>
                                                        const ColoredBox(
                                                      color: Color(0xFFE5E9EE),
                                                      child: Icon(
                                                        Icons.broken_image_outlined,
                                                      ),
                                                    ),
                                                  ),
                                                  Align(
                                                    alignment: Alignment.bottomCenter,
                                                    child: Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 3,
                                                      ),
                                                      color: Colors.black54,
                                                      child: Text(
                                                        label,
                                                        textAlign: TextAlign.center,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Dotknij miniatury, aby otworzyć pełne zdjęcie i powiększać je gestem.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF66788A),
                                    ),
                                  ),
                                ],
                                if (defect.isResolved) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width:
                                        double.infinity,
                                    padding:
                                        const EdgeInsets
                                            .all(12),
                                    decoration:
                                        BoxDecoration(
                                      color:
                                          Colors.green
                                              .shade50,
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        12,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Text(
                                          'USTERKA USUNIĘTA'
                                          '${defect.resolvedAt != null ? " • ${dateFormat.format(defect.resolvedAt!)}" : ""}',
                                          style:
                                              TextStyle(
                                            fontWeight:
                                                FontWeight
                                                    .w700,
                                            color:
                                                Colors
                                                    .green
                                                    .shade800,
                                          ),
                                        ),
                                        if (defect
                                            .resolutionNote
                                            .isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets
                                                    .only(
                                              top: 5,
                                            ),
                                            child: Text(
                                              defect
                                                  .resolutionNote,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!_audit
                                        .isCompleted)
                                      OutlinedButton
                                          .icon(
                                        onPressed: () =>
                                            _editDefect(
                                          defect,
                                        ),
                                        icon: const Icon(
                                          Icons
                                              .edit_outlined,
                                        ),
                                        label:
                                            const Text(
                                          'Edytuj',
                                        ),
                                      ),
                                    if (_audit
                                            .isCompleted &&
                                        !defect
                                            .isResolved)
                                      FilledButton
                                          .icon(
                                        onPressed: () =>
                                            _confirmResolution(
                                          defect,
                                        ),
                                        icon: const Icon(
                                          Icons
                                              .check_circle_outline,
                                        ),
                                        label:
                                            const Text(
                                          'Potwierdź usunięcie',
                                        ),
                                      ),
                                    if (defect
                                        .isResolved)
                                      OutlinedButton
                                          .icon(
                                        onPressed: () =>
                                            _confirmResolution(
                                          defect,
                                        ),
                                        icon: const Icon(
                                          Icons
                                              .add_a_photo_outlined,
                                        ),
                                        label:
                                            const Text(
                                          'Edytuj potwierdzenie',
                                        ),
                                      ),
                                    if (defect
                                        .isResolved)
                                      OutlinedButton
                                          .icon(
                                        onPressed: () =>
                                            _clearResolution(
                                          defect,
                                        ),
                                        icon: const Icon(
                                          Icons.undo,
                                        ),
                                        label:
                                            const Text(
                                          'Cofnij usunięcie',
                                        ),
                                      ),
                                    if (!_audit
                                        .isCompleted)
                                      TextButton
                                          .icon(
                                        onPressed: () =>
                                            _deleteDefect(
                                          defect,
                                        ),
                                        icon: const Icon(
                                          Icons
                                              .delete_outline,
                                        ),
                                        label:
                                            const Text(
                                          'Usuń',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
