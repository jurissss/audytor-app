import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import 'audit_screen.dart';
import 'site_detail_screen.dart';
import 'site_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _importing = false;
  List<Site> _sites = [];
  List<_AuditListItem> _audits = [];

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
    final sites = await DatabaseService.instance.getSites();
    final audits = <_AuditListItem>[];
    for (final site in sites) {
      if (site.id == null) continue;
      final rows = await DatabaseService.instance.getAuditsForSite(site.id!);
      audits.addAll(rows.map((audit) => _AuditListItem(site, audit)));
    }
    audits.sort((a, b) => b.audit.startedAt.compareTo(a.audit.startedAt));

    if (!mounted) return;
    setState(() {
      _sites = sites;
      _audits = audits;
      _loading = false;
    });
  }

  Future<void> _newSite() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SiteFormScreen()),
    );
    if (changed == true) await _load();
  }

  Future<void> _openSite(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SiteDetailScreen(site: site)),
    );
    await _load();
  }

  Future<void> _openAudit(_AuditListItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuditScreen(site: item.site, audit: item.audit),
      ),
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
            '${preview.siteName}\n${preview.auditType}\n'
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
    final filteredSites = _sites.where((site) {
      if (q.isEmpty) return true;
      return site.name.toLowerCase().contains(q) ||
          site.code.toLowerCase().contains(q) ||
          site.address.toLowerCase().contains(q);
    }).toList();

    final visibleAudits = _audits.where((item) {
      if (q.isEmpty) return true;
      return item.site.name.toLowerCase().contains(q) ||
          item.site.code.toLowerCase().contains(q) ||
          item.audit.auditType.toLowerCase().contains(q) ||
          item.audit.auditor.toLowerCase().contains(q);
    }).take(q.isEmpty ? 8 : 30).toList();

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
        onPressed: _newSite,
        icon: const Icon(Icons.add),
        label: const Text('Nowy obiekt'),
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
                      hintText: 'Szukaj obiektu, kodu lub audytu',
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
                          q.isEmpty ? 'Ostatnie audyty' : 'Znalezione audyty',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text('${visibleAudits.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (visibleAudits.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Brak audytów do wyświetlenia.'),
                      ),
                    ),
                  ...visibleAudits.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            child: Icon(
                              item.audit.isCompleted
                                  ? Icons.check_rounded
                                  : Icons.assignment_outlined,
                            ),
                          ),
                          title: Text(
                            item.site.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${item.audit.auditType} • ${df.format(item.audit.startedAt)}\n'
                            '${item.audit.auditor} • ${item.audit.isCompleted ? 'Zakończony' : 'W trakcie'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openAudit(item),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Obiekty',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Text('${filteredSites.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (filteredSites.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Nie znaleziono obiektów.'),
                      ),
                    ),
                  ...filteredSites.map(
                    (site) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.apartment_outlined),
                          ),
                          title: Text(
                            site.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if (site.code.isNotEmpty) site.code,
                              if (site.address.isNotEmpty) site.address,
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openSite(site),
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

class _AuditListItem {
  final Site site;
  final Audit audit;

  const _AuditListItem(this.site, this.audit);
}
