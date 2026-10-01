import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../models/site.dart';
import '../services/database_service.dart';

class AuditSetupScreen extends StatefulWidget {
  final Site site;
  final String title;
  final String buttonLabel;
  final String initialAuditor;
  final String initialType;
  final String initialNotes;
  final int? parentAuditId;

  const AuditSetupScreen({
    super.key,
    required this.site,
    this.title = 'Rozpocznij audyt',
    this.buttonLabel = 'Rozpocznij audyt',
    this.initialAuditor = '',
    this.initialType = 'Audyt techniczny',
    this.initialNotes = '',
    this.parentAuditId,
  });

  @override
  State<AuditSetupScreen> createState() => _AuditSetupScreenState();
}

class _AuditSetupScreenState extends State<AuditSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _auditor;
  late final TextEditingController _type;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _auditor = TextEditingController(text: widget.initialAuditor);
    _type = TextEditingController(text: widget.initialType);
    _notes = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _auditor.dispose();
    _type.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final audit = Audit(
      siteId: widget.site.id!,
      auditor: _auditor.text.trim(),
      auditType: _type.text.trim(),
      startedAt: DateTime.now(),
      notes: _notes.text.trim(),
      status: 'draft',
      parentAuditId: widget.parentAuditId,
    );
    final id = await DatabaseService.instance.insertAudit(audit);
    if (!mounted) return;
    Navigator.of(context).pop(audit.copyWith(id: id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.apartment),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.site.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _auditor,
              decoration: const InputDecoration(
                labelText: 'Audytor *',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Podaj imię i nazwisko audytora'
                  : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _type,
              decoration: const InputDecoration(
                labelText: 'Typ audytu *',
                prefixIcon: Icon(Icons.fact_check_outlined),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Podaj typ audytu'
                  : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Uwagi ogólne',
                prefixIcon: Icon(Icons.notes),
              ),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _start,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(widget.buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
