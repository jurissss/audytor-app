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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _code;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site?.name ?? '');
    _address = TextEditingController(text: widget.site?.address ?? '');
    _code = TextEditingController(text: widget.site?.code ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _code.text.trim();
    final duplicate = await DatabaseService.instance.isSiteCodeTaken(
      code,
      excludeSiteId: widget.site?.id,
    );
    if (duplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Obiekt o numerze „$code” już istnieje.')),
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

    try {
      if (widget.site == null) {
        await DatabaseService.instance.insertSite(site);
      } else {
        await DatabaseService.instance.updateSite(site);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się zapisać obiektu. Sprawdź, czy numer nie jest już używany.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.site == null ? 'Nowy obiekt' : 'Edytuj obiekt')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Nr / kod obiektu *',
                  prefixIcon: Icon(Icons.tag),
                  helperText: 'Numer musi być unikalny.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Podaj numer / kod obiektu'
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nazwa obiektu *',
                  prefixIcon: Icon(Icons.apartment),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Podaj nazwę obiektu'
                    : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Zapisz obiekt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
