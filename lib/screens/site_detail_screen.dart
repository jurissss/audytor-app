import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';
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

  @override
  void initState() {
    super.initState();
    _site = widget.site;
    _load();
  }

  Future<void> _load() async {
    final site = await DatabaseService.instance.getSiteById(_site.id!);
    final audits = await DatabaseService.instance.getAuditsForSite(_site.id!);
    if (!mounted) return;
    setState(() {
      if (site != null) _site = site;
      _audits = audits;
      _loading = false;
    });
  }

  Future<void> _newAudit() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => AuditSetupScreen(site: _site)),
    );
    if (id == null) return;
    final audit = await DatabaseService.instance.getAuditById(id);
    if (!mounted || audit == null) return;
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
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usunąć obiekt?'),
        content: const Text(
          'Zostaną usunięte wszystkie audyty, usterki i zdjęcia tego obiektu.',
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
        await DatabaseService.instance.getPhotoPathsForSite(_site.id!);
    for (final path in paths) {
      await PhotoService.deleteIfExists(path);
    }
    await DatabaseService.instance.deleteSite(_site.id!);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Obiekt'),
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
              PopupMenuItem(
                value: 'delete',
                child: Text('Usuń obiekt'),
              ),
            ],
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _site.name,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (_site.code.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text('Kod: ${_site.code}'),
                          ],
                          if (_site.address.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(_site.address),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Audyty',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (_audits.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Brak audytów dla tego obiektu.'),
                      ),
                    ),
                  ..._audits.map(
                    (audit) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            child: Icon(
                              audit.isCompleted
                                  ? Icons.check_rounded
                                  : Icons.assignment_outlined,
                            ),
                          ),
                          title: Text(
                            audit.auditType,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${df.format(audit.startedAt)} • ${audit.auditor}\n'
                            '${audit.isCompleted ? 'Zakończony' : 'W trakcie'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AuditScreen(site: _site, audit: audit),
                              ),
                            );
                            await _load();
                          },
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
