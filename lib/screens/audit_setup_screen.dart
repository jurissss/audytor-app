import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/database_service.dart';

class AuditSetupScreen extends StatefulWidget {
  final Site site;
  const AuditSetupScreen({super.key, required this.site});

  @override
  State<AuditSetupScreen> createState() => _AuditSetupScreenState();
}

class _AuditSetupScreenState extends State<AuditSetupScreen> {
  final _key = GlobalKey<FormState>();
  final _auditor = TextEditingController();
  final _type = TextEditingController(text: 'Audyt techniczny');
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _auditor.dispose();
    _type.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);

    final id = await DatabaseService.instance.insertAudit(
      Audit(
        siteId: widget.site.id!,
        auditor: _auditor.text.trim(),
        auditType: _type.text.trim(),
        startedAt: DateTime.now(),
        notes: _notes.text.trim(),
        status: 'draft',
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nowy audyt')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _auditor,
              decoration: const InputDecoration(labelText: 'Audytor *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Podaj audytora' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _type,
              decoration: const InputDecoration(labelText: 'Typ audytu *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Podaj typ audytu' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Uwagi'),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Rozpocznij audyt'),
            ),
          ],
        ),
      ),
    );
  }
}
