import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/defect_note.dart';
import 'database_service.dart';
import 'photo_service.dart';
import 'report_service.dart';

class AuditPackagePreview {
  final String syncId;
  final String client;
  final String storeNumber;
  final int defectsCount;
  final int photosCount;

  const AuditPackagePreview({
    required this.syncId,
    required this.client,
    required this.storeNumber,
    required this.defectsCount,
    required this.photosCount,
  });
}

class AuditPackageExportResult {
  final String path;
  final String filename;
  final int sizeBytes;
  final int photosCount;

  const AuditPackageExportResult({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.photosCount,
  });

  double get sizeMb => sizeBytes / (1024 * 1024);
}

class AuditPackageImportResult {
  final int auditId;
  final bool updatedExisting;
  final int importedPhotos;

  const AuditPackageImportResult({
    required this.auditId,
    required this.updatedExisting,
    required this.importedPhotos,
  });
}

class AuditPackageService {
  static const String _format = 'audytor-audit-package';
  static const int _formatVersion = 3;
  static const int _emailImageBudgetBytes =
      15 * 1024 * 1024;

  static Future<String?> pickPackageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  static Future<AuditPackagePreview> inspect(
    String packagePath,
  ) async {
    final decoded = await _decodePackage(packagePath);
    final manifest = decoded.manifest;
    final audit = _asMap(manifest['audit']);
    final legacySite = _asMap(manifest['site']);
    final defects = _asList(manifest['defects']);

    var photos = 0;

    for (final raw in defects) {
      final defect = _asMap(raw);
      photos += _asList(defect['photos']).length;

      for (final rawNote
          in _asList(defect['followup_notes'])) {
        photos +=
            _asList(_asMap(rawNote)['photos']).length;
      }
    }

    return AuditPackagePreview(
      syncId: (audit['sync_id'] as String?) ?? '',
      client: (audit['client'] as String?) ??
          (legacySite['name'] as String?) ??
          'Klient',
      storeNumber:
          (audit['store_number'] as String?) ??
              (legacySite['code'] as String?) ??
              '',
      defectsCount: defects.length,
      photosCount: photos,
    );
  }

  static Future<AuditPackageExportResult> exportForEmail({
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
    required Map<int, List<DefectNote>> notes,
  }) async {
    if (audit.id == null) {
      throw StateError(
        'Audyt nie ma identyfikatora.',
      );
    }

    final syncId =
        await DatabaseService.instance
            .ensureAuditSyncId(audit.id!);

    final archive = Archive();

    final reportBatch =
        await ReportService.generate(
      audit: audit,
      defects: defects,
      photos: photos,
      notes: notes,
    );

    for (var i = 0;
        i < reportBatch.parts.length;
        i++) {
      final report = reportBatch.parts[i];

      final name = reportBatch.parts.length == 1
          ? 'RAPORT_AUDYTU.pdf'
          : 'RAPORT_AUDYTU_CZESC_${(i + 1).toString().padLeft(2, '0')}.pdf';

      archive.addFile(
        ArchiveFile(
          name,
          report.bytes.length,
          report.bytes,
        ),
      );
    }

    final allSources = <_SourcePhoto>[];

    for (final defect in defects) {
      if (defect.id == null) continue;

      for (final photo
          in photos[defect.id] ??
              const <AuditPhoto>[]) {
        if (await File(photo.path).exists()) {
          allSources.add(
            _SourcePhoto(
              defect: defect,
              path: photo.path,
              kind: photo.kind,
              createdAt: photo.createdAt,
            ),
          );
        }
      }

      for (final note
          in notes[defect.id] ??
              const <DefectNote>[]) {
        for (final path in note.photoPaths) {
          if (await File(path).exists()) {
            allSources.add(
              _SourcePhoto(
                defect: defect,
                path: path,
                kind: 'note',
                createdAt: note.createdAt,
                noteId: note.id,
              ),
            );
          }
        }
      }
    }

    final targetBytes = allSources.isEmpty
        ? 0
        : (_emailImageBudgetBytes ~/
                allSources.length)
            .clamp(
              90 * 1024,
              330 * 1024,
            )
            .toInt();

    final photosByDefect =
        <int, List<Map<String, Object?>>>{};

    final notePhotosByNote =
        <int, List<Map<String, Object?>>>{};

    var counter = 0;

    for (final source in allSources) {
      final bytes =
          await PhotoService.compressForEmailPackage(
        source.path,
        targetBytes: targetBytes,
      );

      final name =
          'photos/${_safe(source.defect.positionNo)}_${counter.toString().padLeft(3, '0')}_${source.kind}.jpg';

      archive.addFile(
        ArchiveFile(
          name,
          bytes.length,
          bytes,
        ),
      );

      final entry = <String, Object?>{
        'file': name,
        'kind': source.kind,
        'created_at':
            source.createdAt.toIso8601String(),
      };

      if (source.noteId != null) {
        notePhotosByNote
            .putIfAbsent(
              source.noteId!,
              () => <Map<String, Object?>>[],
            )
            .add(entry);
      } else {
        photosByDefect
            .putIfAbsent(
              source.defect.id!,
              () => <Map<String, Object?>>[],
            )
            .add(entry);
      }

      counter++;
    }

    final manifest = <String, Object?>{
      'format': _format,
      'version': _formatVersion,
      'exported_at':
          DateTime.now().toIso8601String(),
      'audit': {
        'sync_id': syncId,
        'client': audit.client,
        'store_number': audit.storeNumber,
        'address': audit.address,
        'auditor': audit.auditor,
        'audit_type': audit.auditType,
        'started_at':
            audit.startedAt.toIso8601String(),
        'completed_at':
            audit.completedAt?.toIso8601String(),
        'notes': audit.notes,
        'status': audit.status,
      },
      'defects': defects.map((defect) {
        final followups =
            (notes[defect.id] ??
                    const <DefectNote>[])
                .map(
          (note) => {
            'note': note.text,
            'created_at':
                note.createdAt.toIso8601String(),
            'photos': note.id == null
                ? const <Map<String, Object?>>[]
                : notePhotosByNote[note.id!] ??
                    const <Map<String, Object?>>[],
          },
        ).toList();

        return {
          'position_no': defect.positionNo,
          'location': defect.location,
          'description': defect.description,
          'priority': defect.priority,
          'recommendation':
              defect.recommendation,
          'created_at':
              defect.createdAt.toIso8601String(),
          'is_resolved': defect.isResolved,
          'resolved_at':
              defect.resolvedAt?.toIso8601String(),
          'resolution_note':
              defect.resolutionNote,
          'nameplate_unavailable':
              defect.nameplateUnavailable,
          'photos':
              photosByDefect[defect.id] ??
                  const <Map<String, Object?>>[],
          'followup_notes': followups,
        };
      }).toList(),
    };

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent(' ')
          .convert(manifest),
    );

    archive.addFile(
      ArchiveFile(
        'manifest.json',
        manifestBytes.length,
        manifestBytes,
      ),
    );

    final readme = utf8.encode(
      'PACZKA AUDYTU - AUDYTOR\n\n'
      'Zawiera aktualny raport PDF, dane audytu, usterki, zdjęcia, '
      'potwierdzenia napraw oraz historię uwag po audycie.\n',
    );

    archive.addFile(
      ArchiveFile(
        'README.txt',
        readme.length,
        readme,
      ),
    );

    final encoded =
        ZipEncoder().encode(archive);

    if (encoded == null) {
      throw StateError(
        'Nie udało się utworzyć paczki audytu.',
      );
    }

    final docs =
        await getApplicationDocumentsDirectory();

    final dir = Directory(
      p.join(
        docs.path,
        'audit_packages',
      ),
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final filename =
        'Audyt_${_safe(audit.client)}_${_safe(audit.storeNumber)}_${_stamp(audit.startedAt)}_do_weryfikacji.audyt.zip';

    final file =
        File(p.join(dir.path, filename));

    await file.writeAsBytes(
      encoded,
      flush: true,
    );

    return AuditPackageExportResult(
      path: file.path,
      filename: filename,
      sizeBytes: await file.length(),
      photosCount: allSources.length,
    );
  }

  static Future<AuditPackageImportResult>
      importPackage(
    String packagePath, {
    bool allowUpdateExisting = true,
  }) async {
    final decoded =
        await _decodePackage(packagePath);

    final manifest = decoded.manifest;
    final auditMap =
        _asMap(manifest['audit']);
    final legacySite =
        _asMap(manifest['site']);
    final defectMaps =
        _asList(manifest['defects']);

    final syncId =
        ((auditMap['sync_id'] as String?) ?? '')
            .trim();

    if (syncId.isEmpty) {
      throw const FormatException(
        'Brak identyfikatora audytu.',
      );
    }

    final existingAudit =
        await DatabaseService.instance
            .getAuditBySyncId(syncId);

    if (existingAudit != null &&
        !allowUpdateExisting) {
      throw StateError(
        'Ten audyt już istnieje.',
      );
    }

    final client =
        (auditMap['client'] as String?) ??
            (legacySite['name'] as String?) ??
            'Klient';

    final storeNumber =
        (auditMap['store_number'] as String?) ??
            (legacySite['code'] as String?) ??
            '';

    final address =
        (auditMap['address'] as String?) ??
            (legacySite['address'] as String?) ??
            '';

    late final int auditId;
    final updatedExisting =
        existingAudit != null;

    if (existingAudit == null) {
      auditId =
          await DatabaseService.instance
              .insertAudit(
        Audit(
          client: client,
          storeNumber: storeNumber,
          address: address,
          auditor:
              (auditMap['auditor'] as String?) ??
                  '',
          auditType:
              (auditMap['audit_type'] as String?) ??
                  'Audyt techniczny',
          startedAt: DateTime.parse(
            auditMap['started_at'] as String,
          ),
          completedAt:
              _parseDate(auditMap['completed_at']),
          notes:
              (auditMap['notes'] as String?) ?? '',
          status:
              (auditMap['status'] as String?) ??
                  'completed',
          syncId: syncId,
        ),
      );
    } else {
      auditId = existingAudit.id!;

      await DatabaseService.instance
          .updateAudit(
        existingAudit.copyWith(
          client: client,
          storeNumber: storeNumber,
          address: address,
          auditor:
              (auditMap['auditor'] as String?) ??
                  existingAudit.auditor,
          auditType:
              (auditMap['audit_type'] as String?) ??
                  existingAudit.auditType,
          notes:
              (auditMap['notes'] as String?) ??
                  existingAudit.notes,
          status:
              (auditMap['status'] as String?) ??
                  existingAudit.status,
          completedAt:
              _parseDate(
                    auditMap['completed_at'],
                  ) ??
                  existingAudit.completedAt,
          syncId: syncId,
        ),
      );
    }

    var importedPhotos = 0;

    for (final raw in defectMaps) {
      final map = _asMap(raw);

      final position =
          (map['position_no'] as String?) ?? '';

      if (position.trim().isEmpty) continue;

      final existingDefect =
          await DatabaseService.instance
              .getDefectByPositionNo(
        auditId,
        position,
      );

      final importedDefect = Defect(
        id: existingDefect?.id,
        auditId: auditId,
        positionNo: position,
        location:
            (map['location'] as String?) ?? '',
        description:
            (map['description'] as String?) ?? '',
        priority:
            (map['priority'] as String?) ??
                'Średni',
        recommendation:
            (map['recommendation'] as String?) ??
                '',
        createdAt:
            _parseDate(map['created_at']) ??
                DateTime.now(),
        isResolved:
            map['is_resolved'] == true,
        resolvedAt:
            _parseDate(map['resolved_at']),
        resolutionNote:
            (map['resolution_note'] as String?) ??
                '',
        nameplateUnavailable:
            map['nameplate_unavailable'] == true,
      );

      late final int defectId;

      if (existingDefect == null) {
        defectId =
            await DatabaseService.instance
                .insertDefect(importedDefect);
      } else {
        defectId = existingDefect.id!;

        await DatabaseService.instance
            .updateDefect(importedDefect);
      }

      final photoMaps =
          _asList(map['photos'])
              .map(_asMap)
              .toList();

      for (final kind in const <String>[
        'issue',
        'nameplate',
        'resolution',
      ]) {
        final old =
            await DatabaseService.instance
                .getPhotosForDefect(
          defectId,
          kind: kind,
        );

        for (final photo in old) {
          await PhotoService.deleteIfExists(
            photo.path,
          );
        }

        final paths = <String>[];

        for (final photoMap
            in photoMaps.where(
          (x) =>
              (x['kind'] as String?) == kind,
        )) {
          final entryName =
              photoMap['file'] as String?;

          if (entryName == null) continue;

          final bytes =
              decoded.entries[entryName];

          if (bytes == null ||
              bytes.isEmpty) {
            continue;
          }

          paths.add(
            await PhotoService.persistBytes(
              Uint8List.fromList(bytes),
              prefix: 'import',
            ),
          );

          importedPhotos++;
        }

        await DatabaseService.instance
            .replacePhotos(
          defectId,
          paths,
          kind: kind,
        );
      }

      // Przy aktualizacji audytu historia uwag jest zastępowana
      // danymi z paczki, aby kolejne importy nie tworzyły duplikatów.
      final oldNotes =
          await DatabaseService.instance
              .getNotesForDefect(defectId);

      for (final note in oldNotes) {
        for (final path in note.photoPaths) {
          await PhotoService.deleteIfExists(path);
        }
      }

      await DatabaseService.instance
          .clearDefectNotes(defectId);

      for (final rawNote
          in _asList(map['followup_notes'])) {
        final noteMap = _asMap(rawNote);
        final paths = <String>[];

        for (final rawPhoto
            in _asList(noteMap['photos'])) {
          final photoMap =
              _asMap(rawPhoto);

          final entryName =
              photoMap['file'] as String?;

          if (entryName == null) continue;

          final bytes =
              decoded.entries[entryName];

          if (bytes == null ||
              bytes.isEmpty) {
            continue;
          }

          paths.add(
            await PhotoService.persistBytes(
              Uint8List.fromList(bytes),
              prefix: 'note_import',
            ),
          );

          importedPhotos++;
        }

        await DatabaseService.instance
            .addDefectNote(
          defectId: defectId,
          text:
              (noteMap['note'] as String?) ?? '',
          photoPaths: paths,
          createdAt:
              _parseDate(noteMap['created_at']),
        );
      }
    }

    return AuditPackageImportResult(
      auditId: auditId,
      updatedExisting: updatedExisting,
      importedPhotos: importedPhotos,
    );
  }

  static Future<_DecodedPackage> _decodePackage(
    String packagePath,
  ) async {
    final file = File(packagePath);

    if (!await file.exists()) {
      throw StateError(
        'Nie znaleziono pliku paczki.',
      );
    }

    final archive =
        ZipDecoder().decodeBytes(
      await file.readAsBytes(),
      verify: true,
    );

    final entries =
        <String, List<int>>{};

    for (final entry in archive.files) {
      if (!entry.isFile) continue;

      final content = entry.content;

      if (content is List<int>) {
        entries[entry.name] =
            List<int>.from(content);
      }
    }

    final manifestBytes =
        entries['manifest.json'];

    if (manifestBytes == null) {
      throw const FormatException(
        'Brak manifestu paczki audytu.',
      );
    }

    final raw = jsonDecode(
      utf8.decode(manifestBytes),
    );

    if (raw is! Map) {
      throw const FormatException(
        'Nieprawidłowy manifest paczki.',
      );
    }

    final manifest =
        Map<String, Object?>.from(raw);

    if (manifest['format'] != _format) {
      throw const FormatException(
        'To nie jest paczka aplikacji Audytor.',
      );
    }

    final version =
        (manifest['version'] as num?)
                ?.toInt() ??
            1;

    if (version < 1 ||
        version > _formatVersion) {
      throw const FormatException(
        'Nieobsługiwana wersja paczki audytu.',
      );
    }

    return _DecodedPackage(
      manifest: manifest,
      entries: entries,
    );
  }

  static Map<String, Object?> _asMap(
    Object? value,
  ) {
    if (value
        is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return Map<String, Object?>.from(
        value,
      );
    }

    return <String, Object?>{};
  }

  static List<Object?> _asList(
    Object? value,
  ) {
    if (value is List) {
      return List<Object?>.from(value);
    }

    return const <Object?>[];
  }

  static DateTime? _parseDate(
    Object? value,
  ) {
    if (value is! String ||
        value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static String _stamp(
    DateTime value,
  ) {
    String two(int n) =>
        n.toString().padLeft(2, '0');

    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }

  static String _safe(String value) {
    final cleaned =
        value.trim().replaceAll(
              RegExp(
                r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+',
              ),
              '_',
            );

    return cleaned.isEmpty
        ? 'audyt'
        : cleaned;
  }
}

class _DecodedPackage {
  final Map<String, Object?> manifest;
  final Map<String, List<int>> entries;

  const _DecodedPackage({
    required this.manifest,
    required this.entries,
  });
}

class _SourcePhoto {
  final Defect defect;
  final String path;
  final String kind;
  final DateTime createdAt;
  final int? noteId;

  const _SourcePhoto({
    required this.defect,
    required this.path,
    required this.kind,
    required this.createdAt,
    this.noteId,
  });
}
