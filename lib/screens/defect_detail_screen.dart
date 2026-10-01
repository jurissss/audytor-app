import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit_photo.dart';
import '../models/defect.dart';

class DefectDetailScreen extends StatelessWidget {
  final Defect defect;
  final List<AuditPhoto> photos;
  final List<AuditPhoto> resolutionPhotos;

  const DefectDetailScreen({
    super.key,
    required this.defect,
    required this.photos,
    this.resolutionPhotos = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pozycja ${defect.positionNo}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pozycja ${defect.positionNo}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Chip(label: Text(defect.priority)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Chip(
                    avatar: Icon(
                      defect.isResolved ? Icons.check_circle : Icons.pending_actions,
                      size: 18,
                    ),
                    label: Text(defect.isResolved ? 'Usunięta' : 'Do usunięcia'),
                  ),
                  if (defect.isResolved && defect.resolvedAt != null) ...[
                    const SizedBox(height: 6),
                    Text('Usunięto: ${DateFormat('dd.MM.yyyy HH:mm').format(defect.resolvedAt!)}'),
                  ],
                  if (defect.location.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Lokalizacja', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(defect.location),
                  ],
                  const SizedBox(height: 14),
                  const Text('Opis usterki', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(defect.description),
                  if (defect.recommendation.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Zalecenie', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(defect.recommendation),
                  ],
                  if (defect.resolutionNote.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text('Komentarz po usunięciu', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(defect.resolutionNote),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Zdjęcia z audytu (${photos.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (photos.isEmpty)
            const Text('Brak zdjęć z audytu.')
          else
            ...photos.map((photo) => _PhotoTile(photo: photo)),
          const SizedBox(height: 20),
          Text(
            'Zdjęcia po usunięciu (${resolutionPhotos.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (resolutionPhotos.isEmpty)
            const Text('Nie dodano zdjęć po usunięciu.')
          else
            ...resolutionPhotos.map((photo) => _PhotoTile(photo: photo)),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final AuditPhoto photo;

  const _PhotoTile({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: File(photo.path).existsSync()
            ? Image.file(File(photo.path), fit: BoxFit.cover)
            : Container(
                height: 180,
                alignment: Alignment.center,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Text('Brak pliku zdjęcia'),
              ),
      ),
    );
  }
}
