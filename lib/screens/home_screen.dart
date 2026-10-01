import 'package:flutter/material.dart';

import '../models/site.dart';
import '../services/audit_package_service.dart';
import '../services/database_service.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await DatabaseService.instance.getSites();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _loading = false;
    });
  }

  Future<void> _newSite() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SiteFormScreen()),
    );
    if (changed == true) await _load();
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
            '${preview.siteName}\n'
            '${preview.auditType}\n'
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
              child: _sites.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 140),
                        Icon(Icons.apartment_outlined, size: 72),
                        SizedBox(height: 18),
                        Center(child: Text('Brak obiektów')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _sites.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final site = _sites[index];
                        return Card(
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              [
                                if (site.code.isNotEmpty) site.code,
                                if (site.address.isNotEmpty) site.address,
                              ].join(' • '),
                            ),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SiteDetailScreen(site: site),
                                ),
                              );
                              await _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
