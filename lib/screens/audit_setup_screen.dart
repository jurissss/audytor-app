import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../services/database_service.dart';

class AuditSetupScreen extends StatefulWidget {
  const AuditSetupScreen({super.key});

  @override
  State<AuditSetupScreen> createState() => _AuditSetupScreenState();
}

class _AuditSetupScreenState extends State<AuditSetupScreen> {
  final _key = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _store = TextEditingController();
  final _address = TextEditingController();
  final _auditor = TextEditingController();
  final _type = TextEditingController(text: 'Audyt techniczny');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLastAuditor();
  }

  Future<void> _loadLastAuditor() async {
    final value = await DatabaseService.instance.getSetting('last_auditor');
    if (mounted && _auditor.text.isEmpty) _auditor.text = value;
  }

  @override
  void dispose() {
    _client.dispose();
    _store.dispose();
    _address.dispose();
    _auditor.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await DatabaseService.instance.insertAudit(
      Audit(
        client: _client.text.trim(),
        storeNumber: _store.text.trim(),
        address: _address.text.trim(),
        auditor: _auditor.text.trim(),
        auditType: _type.text.trim(),
        startedAt: DateTime.now(),
      ),
    );
    final audit = await DatabaseService.instance.getAuditById(id);
    if (!mounted) return;
    Navigator.pop(context, audit);
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
              controller: _client,
              decoration: const InputDecoration(labelText: 'Klient *', prefixIcon: Icon(Icons.business_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'Podaj klienta' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _store,
              decoration: const InputDecoration(labelText: 'Numer sklepu *', prefixIcon: Icon(Icons.numbers_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'Podaj numer sklepu' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Adres *', prefixIcon: Icon(Icons.location_on_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'Podaj adres' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _auditor,
              decoration: const InputDecoration(
                labelText: 'Audytor *',
                helperText: 'Ostatnio wpisany audytor jest zapamiętywany.',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Podaj audytora' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _type,
              decoration: const InputDecoration(
                labelText: 'Typ audytu *',
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Podaj typ audytu' : null,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Rozpocznij audyt'),
            ),
          ],
        ),
      ),
    );
  }
}
