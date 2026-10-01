import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
import '../widgets/empty_state.dart';
import 'audit_screen.dart';
import 'site_detail_screen.dart';
import 'site_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _importing = false;
  List<Site> _sites = [];
  List<Audit> _recentAudits = [];
  final Map<int, int> _defectCounts = {};
  final Map<int, int> _resolvedCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await DatabaseService.instance.getSites();
    final audits = await DatabaseService.instance.getRecentAudits(limit: 8);
    final defectCounts = <int, int>{};
    final resolvedCounts = <int, int>{};

    for (final audit in audits) {
      if (audit.id == null) continue;
      defectCounts[audit.id!] = await DatabaseService.instance.countDefects(audit.id!);
      resolvedCounts[audit.id!] = await DatabaseService.instance.countResolvedDefects(audit.id!);
    }

    if (!mounted) return;
    setState(() {
      _sites = sites;
      _recentAudits = audits;
      _defectCounts
        ..clear()
        ..addAll(defectCounts);
      _resolvedCounts
        ..clear()
        ..addAll(resolvedCounts);
      _loading = false;
    });
  }

  Future<void> _addSite() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SiteFormScreen()),
    );
    if (changed == true) await _load();
  }

  Future<void> _openSite(Site site) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SiteDetailScreen(site: site)),
    );
    await _load();
  }

  Future<void> _importAuditPackage() async {
    if (_importing) return;
    final path = await AuditPackageService.pickPackageFile();
    if (path == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final preview = await AuditPackageService.inspect(path);
      final existing = await DatabaseService.instance.getAuditBySyncId(preview.syncId);
      if (!mounted) return;

      final siteLabel = preview.siteCode.isEmpty
          ? preview.siteName
          : '${preview.siteCode} — ${preview.siteName}';
      final importDescription = existing == null
          ? 'Audyt zostanie dodany do aplikacji.'
          : 'Ten audyt już istnieje. Zostaną naniesione potwierdzenia usunięcia usterek i nowe zdjęcia po usunięciu. Oryginalne zdjęcia z audytu pozostaną bez zmian.';

      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(existing == null ? 'Importować audyt?' : 'Zaktualizować audyt?'),
          content: Text(
            '$siteLabel\n'
            '${preview.auditType}\n'
            '${DateFormat('dd.MM.yyyy HH:mm').format(preview.startedAt)}\n'
            '${preview.defectsCount} usterek • ${preview.photosCount} zdjęć\n\n'
            '$importDescription',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(existing == null ? 'Importuj' : 'Aktualizuj'),
            ),
          ],
        ),
      );
      if (accepted != true) {
        if (mounted) setState(() => _importing = false);
        return;
      }

      final result = await AuditPackageService.importPackage(path);
      await _load();
      if (!mounted) return;
      setState(() => _importing = false);

      final site = await DatabaseService.instance.getSiteById(result.siteId);
      final audit = await DatabaseService.instance.getAuditById(result.auditId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updatedExisting
                ? 'Audyt zaktualizowany. Zaimportowano ${result.importedPhotos} zdjęć.'
                : 'Audyt zaimportowany. Zaimportowano ${result.importedPhotos} zdjęć.',
          ),
        ),
      );
      if (site != null && audit != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AuditScreen(site: site, audit: audit)),
        );
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się zaimportować audytu: $e')),
      );
    }
  }

  Future<void> _openAudit(Audit audit) async {
    final site = _sites.where((s) => s.id == audit.siteId).firstOrNull;
    if (site == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditScreen(site: site, audit: audit)),
    );
    await _load();
  }

  String _siteLabel(Site site) {
    if (site.code.trim().isEmpty) return site.name;
    return '${site.code} — ${site.name}';
  }

  Iterable<Site> _filterSites(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _sites;
    return _sites.where((site) {
      return site.name.toLowerCase().contains(q) ||
          site.code.toLowerCase().contains(q) ||
          site.address.toLowerCase().contains(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audytor', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Panel główny', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Importuj audyt',
            onPressed: _importing ? null : _importAuditPackage,
            icon: _importing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.move_to_inbox_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wybierz obiekt',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Wpisz numer, nazwę lub adres obiektu.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          if (_sites.isEmpty)
                            const Text('Brak obiektów. Dodaj pierwszy obiekt.')
                          else
                            Autocomplete<Site>(
                              displayStringForOption: _siteLabel,
                              optionsBuilder: (textEditingValue) => _filterSites(textEditingValue.text),
                              onSelected: _openSite,
                              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: 'Obiekt',
                                    hintText: 'Szukaj obiektu…',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: const Icon(Icons.arrow_drop_down),
                                  ),
                                  onSubmitted: (_) => onFieldSubmitted(),
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                final items = options.toList();
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      width: MediaQuery.sizeOf(context).width - 32,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxHeight: 360),
                                        child: ListView.separated(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        shrinkWrap: true,
                                        itemCount: items.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final site = items[index];
                                          return ListTile(
                                            leading: const Icon(Icons.apartment_outlined),
                                            title: Text(site.name),
                                            subtitle: Text([
                                              if (site.code.isNotEmpty) 'Nr ${site.code}',
                                              if (site.address.isNotEmpty) site.address,
                                            ].join(' • ')),
                                            onTap: () => onSelected(site),
                                          );
                                        },
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _addSite,
                              icon: const Icon(Icons.add_business_outlined),
                              label: const Text('Dodaj nowy obiekt'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: _importing ? null : _importAuditPackage,
                              icon: _importing
                                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.move_to_inbox_outlined),
                              label: Text(_importing ? 'Importowanie…' : 'Importuj audyt od innego użytkownika'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ostatnie audyty',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text('${_recentAudits.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_recentAudits.isEmpty)
                    SizedBox(
                      height: 330,
                      child: EmptyState(
                        icon: Icons.history_toggle_off,
                        title: 'Brak ostatnich audytów',
                        subtitle: _sites.isEmpty
                            ? 'Dodaj obiekt, a następnie rozpocznij pierwszy audyt.'
                            : 'Wybierz obiekt powyżej i rozpocznij audyt.',
                        buttonLabel: _sites.isEmpty ? 'Dodaj obiekt' : null,
                        onPressed: _sites.isEmpty ? _addSite : null,
                      ),
                    )
                  else
                    ..._recentAudits.map((audit) {
                      final site = _sites.where((s) => s.id == audit.siteId).firstOrNull;
                      if (site == null) return const SizedBox.shrink();
                      final total = _defectCounts[audit.id] ?? 0;
                      final resolved = _resolvedCounts[audit.id] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            leading: CircleAvatar(
                              child: Icon(audit.isCompleted ? Icons.check_circle_outline : Icons.fact_check_outlined),
                            ),
                            title: Text(
                              site.name,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${audit.auditType}\n'
                              '${DateFormat('dd.MM.yyyy HH:mm').format(audit.startedAt)} • '
                              '$resolved/$total usunięte • '
                              '${audit.isCompleted ? 'Zakończony' : 'Roboczy'}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openAudit(audit),
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
