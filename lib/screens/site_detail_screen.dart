import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';
import '../widgets/empty_state.dart';
import 'audit_screen.dart';
import 'audit_setup_screen.dart';
import 'site_form_screen.dart';

class SiteDetailScreen extends StatefulWidget {
  final Site site;

  const SiteDetailScreen({super.key, required this.site});

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  late Site _site;
  bool _loading = true;
  List<Audit> _audits = [];
  final Map<int, int> _defectCounts = {};
  final Map<int, int> _resolvedCounts = {};

  @override
  void initState() {
    super.initState();
    _site = widget.site;
    _load();
  }

  Future<void> _load() async {
    final freshSite = await DatabaseService.instance.getSiteById(_site.id!);
    final audits = await DatabaseService.instance.getAuditsForSite(_site.id!);
    final counts = <int, int>{};
    final resolved = <int, int>{};
    for (final audit in audits) {
      if (audit.id != null) {
        counts[audit.id!] = await DatabaseService.instance.countDefects(audit.id!);
        resolved[audit.id!] = await DatabaseService.instance.countResolvedDefects(audit.id!);
      }
    }
    if (!mounted) return;
    setState(() {
      if (freshSite != null) _site = freshSite;
      _audits = audits;
      _defectCounts
        ..clear()
        ..addAll(counts);
      _resolvedCounts
        ..clear()
        ..addAll(resolved);
      _loading = false;
    });
  }

  Future<void> _startAudit() async {
    final audit = await Navigator.of(context).push<Audit>(
      MaterialPageRoute(builder: (_) => AuditSetupScreen(site: _site)),
    );
    if (audit == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditScreen(site: _site, audit: audit)),
    );
    await _load();
  }

  Future<void> _editSite() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SiteFormScreen(site: _site)),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteSite() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć obiekt?'),
        content: const Text(
          'Usunięte zostaną także wszystkie audyty, usterki, potwierdzenia usunięcia i zdjęcia tego obiektu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (confirmed != true) return;
    final photoPaths = await DatabaseService.instance.getPhotoPathsForSite(_site.id!);
    for (final path in photoPaths) {
      await PhotoService.deleteIfExists(path);
    }
    await DatabaseService.instance.deleteSite(_site.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _deleteAudit(Audit audit) async {
    if (audit.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć audyt?'),
        content: const Text('Audyt, jego usterki, potwierdzenia usunięcia i zdjęcia zostaną trwale usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (confirmed != true) return;
    final paths = await DatabaseService.instance.getPhotoPathsForAudit(audit.id!);
    for (final path in paths) {
      await PhotoService.deleteIfExists(path);
    }
    await DatabaseService.instance.deleteAudit(audit.id!);
    await _load();
  }

  String _statusText(Audit audit, int resolved, int total) {
    final base = audit.isCompleted ? 'Zakończony' : 'Roboczy';
    return '$base • $resolved/$total usunięte';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_site.name),
        actions: [
          IconButton(
            tooltip: 'Edytuj obiekt',
            onPressed: _editSite,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteSite();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Usuń obiekt')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startAudit,
        icon: const Icon(Icons.playlist_add_check_circle_outlined),
        label: const Text('Nowy audyt'),
      ),
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
                            _site.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (_site.code.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Nr / kod: ${_site.code}'),
                          ],
                          if (_site.address.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_outlined, size: 18),
                                const SizedBox(width: 6),
                                Expanded(child: Text(_site.address)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _editSite,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edytuj dane obiektu'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Audyty',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (_audits.isEmpty)
                    SizedBox(
                      height: 380,
                      child: EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'Brak audytów',
                        subtitle: 'Rozpocznij pierwszy audyt dla tego obiektu.',
                        buttonLabel: 'Nowy audyt',
                        onPressed: _startAudit,
                      ),
                    )
                  else
                    ..._audits.map((audit) {
                      final total = _defectCounts[audit.id] ?? 0;
                      final resolved = _resolvedCounts[audit.id] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                leading: CircleAvatar(
                                  child: Icon(
                                    audit.isCompleted ? Icons.check : Icons.edit_note,
                                  ),
                                ),
                                title: Text(audit.auditType, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${DateFormat('dd.MM.yyyy HH:mm').format(audit.startedAt)}\n${_statusText(audit, resolved, total)}',
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'delete') _deleteAudit(audit);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'delete', child: Text('Usuń audyt')),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => AuditScreen(site: _site, audit: audit)),
                                  );
                                  await _load();
                                },
                              ),
                            ],
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
