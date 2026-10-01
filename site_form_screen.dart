import 'package:flutter/material.dart';

import '../models/site.dart';
import '../services/database_service.dart';

class SiteFormScreen extends StatefulWidget {
  final Site? site;
  const SiteFormScreen({super.key, this.site});

  @override
  State<SiteFormScreen> createState() => _SiteFormScreenState();
}

class _SiteFormScreenState extends State<SiteFormScreen> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site?.name ?? '');
    _code = TextEditingController(text: widget.site?.code ?? '');
    _address = TextEditingController(text: widget.site?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;

    final code = _code.text.trim();
    if (await DatabaseService.instance
        .isSiteCodeTaken(code, excludeSiteId: widget.site?.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ten kod obiektu jest już używany.')),
      );
      return;
    }

    setState(() => _saving = true);

    final site = Site(
      id: widget.site?.id,
      name: _name.text.trim(),
      address: _address.text.trim(),
      code: code,
      createdAt: widget.site?.createdAt ?? DateTime.now(),
    );

    if (widget.site == null) {
      await DatabaseService.instance.insertSite(site);
    } else {
      await DatabaseService.instance.updateSite(site);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.site == null ? 'Nowy obiekt' : 'Edytuj obiekt'),
      ),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nazwa obiektu *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Podaj nazwę obiektu' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Kod / numer obiektu'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Adres'),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
  }
}
