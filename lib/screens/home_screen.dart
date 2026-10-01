import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import 'audit_screen.dart';
import 'audit_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _importing = false;
  List<Audit> _audits = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final audits = await DatabaseService.instance.getAudits();
    if (!mounted) return;
    setState(() {
      _audits = audits;
      _loading = false;
    });
  }

  Future<void> _newAudit() async {
    final audit = await Navigator.of(context).push<Audit>(
      MaterialPageRoute(builder: (_) => const AuditSetupScreen()),
    );
    if (audit == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditScreen(audit: audit)),
    );
    await _load();
  }

  Future<void> _openAudit(Audit audit) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditScreen(audit: audit)),
    );
    await _load();
  }

  Future<void> _import() async {
    if (_importing) return;
    final path = await AuditPackageService.pickPackageFile();
    if (path == null) return;
    setState(() => _importing = true);

    try {
      final preview = await AuditPackageService.inspect(path);
      if (!mounted) return;

      final yes = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Importować audyt?'),
          content: Text(
            '${preview.client} • sklep ${preview.storeNumber}\n'
            '${preview.defectsCount} usterek • ${preview.photosCount} zdjęć',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importuj'),
            ),
          ],
        ),
      );

      if (yes != true) {
        if (mounted) setState(() => _importing = false);
        return;
      }

      final result = await AuditPackageService.importPackage(path);
      await _load();

      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updatedExisting
                ? 'Audyt zaktualizowany. Zaimportowano ${result.importedPhotos} zdjęć.'
                : 'Audyt zaimportowany. Zaimportowano ${result.importedPhotos} zdjęć.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import nie powiódł się: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = _audits.where((audit) {
      if (q.isEmpty) return true;
      return audit.client.toLowerCase().contains(q) ||
          audit.storeNumber.toLowerCase().contains(q) ||
          audit.address.toLowerCase().contains(q) ||
          audit.auditor.toLowerCase().contains(q);
    }).toList();

    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audytor'),
        actions: [
          IconButton(
            tooltip: 'Importuj audyt',
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newAudit,
        icon: const Icon(Icons.add),
        label: const Text('Nowy audyt'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Szukaj klienta, numeru sklepu, adresu lub audytora',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          q.isEmpty ? 'Audyty' : 'Znalezione audyty',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text('${visible.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (visible.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Brak audytów do wyświetlenia.'),
                      ),
                    ),
                  ...visible.map(
                    (audit) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          leading: CircleAvatar(
                            child: Icon(
                              audit.isCompleted
                                  ? Icons.check_rounded
                                  : Icons.assignment_outlined,
                            ),
                          ),
                          title: Text(
                            audit.client,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Sklep ${audit.storeNumber} • ${audit.auditType}\n'
                            '${df.format(audit.startedAt)} • ${audit.auditor}\n'
                            '${audit.isCompleted ? 'Zakończony' : 'W trakcie'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openAudit(audit),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
