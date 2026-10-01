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
import '../models/site.dart';
import 'database_service.dart';
import 'photo_service.dart';

class AuditPackagePreview {
  final String syncId;
  final String siteName;
  final String siteCode;
  final String auditType;
  final DateTime startedAt;
  final int defectsCount;
  final int photosCount;

  const AuditPackagePreview({
    required this.syncId,
    required this.siteName,
    required this.siteCode,
    required this.auditType,
    required this.startedAt,
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
  final int siteId;
  final bool updatedExisting;
  final int importedPhotos;

  const AuditPackageImportResult({
    required this.auditId,
    required this.siteId,
    required this.updatedExisting,
    required this.importedPhotos,
  });
}

class AuditPackageService {
  static const String _format = 'audytor-audit-package';
  static const int _formatVersion = 1;

  // Budżet obrazów celowo niższy niż typowy limit załącznika e-mail 20–25 MB.
  // Zostaje zapas na manifest i narzut ZIP.
  static const int _emailImageBudgetBytes = 16 * 1024 * 1024;

  static Future<String?> pickPackageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  static Future<AuditPackagePreview> inspect(String packagePath) async {
    final decoded = await _decodePackage(packagePath);
    final manifest = decoded.manifest;
    final site = _asMap(manifest['site']);
    final audit = _asMap(manifest['audit']);
    final defects = _asList(manifest['defects']);

    var photos = 0;
    for (final rawDefect in defects) {
      final defect = _asMap(rawDefect);
      photos += _asList(defect['photos']).length;
    }

    return AuditPackagePreview(
      syncId: (audit['sync_id'] as String?) ?? '',
      siteName: (site['name'] as String?) ?? 'Obiekt',
      siteCode: (site['code'] as String?) ?? '',
      auditType: (audit['audit_type'] as String?) ?? 'Audyt',
      startedAt: DateTime.parse(audit['started_at'] as String),
      defectsCount: defects.length,
      photosCount: photos,
    );
  }

  static Future<AuditPackageExportResult> exportForEmail({
    required Site site,
    required Audit audit,
    required List<Defect> defects,
    required Map<int, List<AuditPhoto>> photos,
  }) async {
    if (audit.id == null) {
      throw StateError('Audyt nie ma identyfikatora.');
    }

    final syncId = await DatabaseService.instance.ensureAuditSyncId(audit.id!);
    final archive = Archive();

    final validPhotos = <_SourcePhoto>[];
    for (final defect in defects) {
      final defectId = defect.id;
      if (defectId == null) continue;
      for (final photo in photos[defectId] ?? const <AuditPhoto>[]) {
        if (await File(photo.path).exists()) {
          validPhotos.add(_SourcePhoto(defect: defect, photo: photo));
        }
      }
    }

    final perPhotoTarget = validPhotos.isEmpty
        ? 0
        : (_emailImageBudgetBytes ~/ validPhotos.length)
            .clamp(95 * 1024, 350 * 1024)
            .toInt();

    final photoManifestByDefect = <int, List<Map<String, Object?>>>{};
    var photoCounter = 0;

    for (final source in validPhotos) {
      final compressed = await PhotoService.compressForEmailPackage(
        source.photo.path,
        targetBytes: perPhotoTarget,
      );
      final safePosition = _safe(source.defect.positionNo);
      final entryName = 'photos/${safePosition}_${photoCounter.toString().padLeft(3, '0')}_${source.photo.kind}.jpg';
      archive.addFile(ArchiveFile(entryName, compressed.length, compressed));
      photoManifestByDefect.putIfAbsent(source.defect.id!, () => <Map<String, Object?>>[]).add({
        'file': entryName,
        'kind': source.photo.kind,
        'created_at': source.photo.createdAt.toIso8601String(),
      });
      photoCounter++;
    }

    final manifest = <String, Object?>{
      'format': _format,
      'version': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'site': {
        'name': site.name,
        'address': site.address,
        'code': site.code,
        'created_at': site.createdAt.toIso8601String(),
      },
      'audit': {
        'sync_id': syncId,
        'auditor': audit.auditor,
        'audit_type': audit.auditType,
        'started_at': audit.startedAt.toIso8601String(),
        'completed_at': audit.completedAt?.toIso8601String(),
        'notes': audit.notes,
        'status': audit.status,
      },
      'defects': defects.map((defect) => {
            'position_no': defect.positionNo,
            'location': defect.location,
            'description': defect.description,
            'priority': defect.priority,
            'recommendation': defect.recommendation,
            'created_at': defect.createdAt.toIso8601String(),
            'is_resolved': defect.isResolved,
            'resolved_at': defect.resolvedAt?.toIso8601String(),
            'resolution_note': defect.resolutionNote,
            'photos': photoManifestByDefect[defect.id] ?? const <Map<String, Object?>>[],
          }).toList(),
    };

    final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    const readme = 'Paczka audytu aplikacji Audytor. Otwórz ją w aplikacji przez opcję „Importuj audyt”.';
    final readmeBytes = utf8.encode(readme);
    archive.addFile(ArchiveFile('README.txt', readmeBytes.length, readmeBytes));

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('Nie udało się utworzyć paczki audytu.');

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'audit_packages'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = _stamp(audit.startedAt);
    final filename = 'Audyt_${_safe(site.code.isNotEmpty ? site.code : site.name)}_${stamp}_do_weryfikacji.audyt.zip';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(encoded, flush: true);

    return AuditPackageExportResult(
      path: file.path,
      filename: filename,
      sizeBytes: await file.length(),
      photosCount: validPhotos.length,
    );
  }

  static Future<AuditPackageImportResult> importPackage(
    String packagePath, {
    bool allowUpdateExisting = true,
  }) async {
    final decoded = await _decodePackage(packagePath);
    final manifest = decoded.manifest;
    final siteMap = _asMap(manifest['site']);
    final auditMap = _asMap(manifest['audit']);
    final defectMaps = _asList(manifest['defects']);
    final syncId = (auditMap['sync_id'] as String?)?.trim() ?? '';
    if (syncId.isEmpty) throw const FormatException('Paczka nie zawiera identyfikatora audytu.');

    final existingAudit = await DatabaseService.instance.getAuditBySyncId(syncId);
    if (existingAudit != null && !allowUpdateExisting) {
      throw StateError('Ten audyt już istnieje.');
    }

    final site = await _resolveSite(siteMap, existingAudit?.siteId);
    late final int auditId;
    final updatedExisting = existingAudit != null;

    if (existingAudit == null) {
      final newAudit = Audit(
        siteId: site.id!,
        auditor: (auditMap['auditor'] as String?) ?? '',
        auditType: (auditMap['audit_type'] as String?) ?? 'Audyt',
        startedAt: DateTime.parse(auditMap['started_at'] as String),
        completedAt: _parseDate(auditMap['completed_at']),
        notes: (auditMap['notes'] as String?) ?? '',
        status: (auditMap['status'] as String?) ?? 'completed',
        syncId: syncId,
      );
      auditId = await DatabaseService.instance.insertAudit(newAudit);
    } else {
      auditId = existingAudit.id!;
      final updated = existingAudit.copyWith(
        auditor: (auditMap['auditor'] as String?) ?? existingAudit.auditor,
        auditType: (auditMap['audit_type'] as String?) ?? existingAudit.auditType,
        notes: (auditMap['notes'] as String?) ?? existingAudit.notes,
        status: (auditMap['status'] as String?) ?? existingAudit.status,
        completedAt: _parseDate(auditMap['completed_at']) ?? existingAudit.completedAt,
        syncId: syncId,
      );
      await DatabaseService.instance.updateAudit(updated);
    }

    var importedPhotos = 0;
    for (final rawDefect in defectMaps) {
      final map = _asMap(rawDefect);
      final position = (map['position_no'] as String?) ?? '';
      if (position.trim().isEmpty) continue;

      final existingDefect = await DatabaseService.instance.getDefectByPositionNo(auditId, position);
      late final int defectId;

      if (existingDefect == null) {
        final defect = Defect(
          auditId: auditId,
          positionNo: position,
          location: (map['location'] as String?) ?? '',
          description: (map['description'] as String?) ?? '',
          priority: (map['priority'] as String?) ?? 'Średni',
          recommendation: (map['recommendation'] as String?) ?? '',
          createdAt: _parseDate(map['created_at']) ?? DateTime.now(),
          isResolved: map['is_resolved'] == true,
          resolvedAt: _parseDate(map['resolved_at']),
          resolutionNote: (map['resolution_note'] as String?) ?? '',
        );
        defectId = await DatabaseService.instance.insertDefect(defect);
      } else {
        defectId = existingDefect.id!;
        await DatabaseService.instance.updateDefectResolutionFromImport(
          defectId,
          isResolved: map['is_resolved'] == true,
          resolvedAt: _parseDate(map['resolved_at']),
          note: (map['resolution_note'] as String?) ?? '',
        );
      }

      final photoMaps = _asList(map['photos']).map(_asMap).toList();
      final kinds = <String>{'issue', 'resolution'};
      for (final kind in kinds) {
        // Przy aktualizacji istniejącego audytu zachowujemy oryginalne zdjęcia usterki
        // w pełniejszej jakości. Z paczki zwrotnej podmieniamy tylko potwierdzenia.
        if (updatedExisting && existingDefect != null && kind == 'issue') continue;

        final oldPhotos = await DatabaseService.instance.getPhotosForDefect(defectId, kind: kind);
        for (final old in oldPhotos) {
          await PhotoService.deleteIfExists(old.path);
        }

        final paths = <String>[];
        for (final photoMap in photoMaps.where((m) => (m['kind'] as String?) == kind)) {
          final entryName = photoMap['file'] as String?;
          if (entryName == null) continue;
          final bytes = decoded.entries[entryName];
          if (bytes == null || bytes.isEmpty) continue;
          final path = await PhotoService.persistBytes(Uint8List.fromList(bytes), prefix: 'import');
          paths.add(path);
          importedPhotos++;
        }
        await DatabaseService.instance.replacePhotos(defectId, paths, kind: kind);
      }
    }

    return AuditPackageImportResult(
      auditId: auditId,
      siteId: site.id!,
      updatedExisting: updatedExisting,
      importedPhotos: importedPhotos,
    );
  }

  static Future<Site> _resolveSite(Map<String, Object?> siteMap, int? preferredSiteId) async {
    if (preferredSiteId != null) {
      final existing = await DatabaseService.instance.getSiteById(preferredSiteId);
      if (existing != null) return existing;
    }

    final code = ((siteMap['code'] as String?) ?? '').trim();
    final name = ((siteMap['name'] as String?) ?? 'Obiekt').trim();
    final address = ((siteMap['address'] as String?) ?? '').trim();
    final existing = await DatabaseService.instance.findSiteForImport(
      code: code,
      name: name,
      address: address,
    );
    if (existing != null) return existing;

    final id = await DatabaseService.instance.insertSite(
      Site(
        name: name.isEmpty ? 'Obiekt importowany' : name,
        address: address,
        code: code,
        createdAt: _parseDate(siteMap['created_at']) ?? DateTime.now(),
      ),
    );
    return (await DatabaseService.instance.getSiteById(id))!;
  }

  static Future<_DecodedPackage> _decodePackage(String packagePath) async {
    final file = File(packagePath);
    if (!await file.exists()) throw StateError('Nie znaleziono pliku paczki.');
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final entries = <String, List<int>>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final content = entry.content;
      if (content is List<int>) {
        entries[entry.name] = content;
      } else if (content is Uint8List) {
        entries[entry.name] = content;
      }
    }
    final manifestBytes = entries['manifest.json'];
    if (manifestBytes == null) throw const FormatException('Brak manifestu paczki audytu.');
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map) throw const FormatException('Nieprawidłowy manifest paczki.');
    final normalized = Map<String, Object?>.from(manifest as Map);
    if (normalized['format'] != _format) throw const FormatException('To nie jest paczka aplikacji Audytor.');
    if ((normalized['version'] as num?)?.toInt() != _formatVersion) {
      throw const FormatException('Nieobsługiwana wersja paczki audytu.');
    }
    return _DecodedPackage(manifest: normalized, entries: entries);
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return <String, Object?>{};
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) return List<Object?>.from(value);
    return const <Object?>[];
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String _stamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }

  static String _safe(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'), '_');
    return cleaned.isEmpty ? 'audyt' : cleaned;
  }
}

class _DecodedPackage {
  final Map<String, Object?> manifest;
  final Map<String, List<int>> entries;

  const _DecodedPackage({required this.manifest, required this.entries});
}

class _SourcePhoto {
  final Defect defect;
  final AuditPhoto photo;

  const _SourcePhoto({required this.defect, required this.photo});
}
