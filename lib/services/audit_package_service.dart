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
import 'report_service.dart';

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
  static const int _formatVersion = 2;
  static const int _emailImageBudgetBytes = 15 * 1024 * 1024;

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
    for (final raw in defects) {
      photos += _asList(_asMap(raw)['photos']).length;
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

    final syncId =
        await DatabaseService.instance.ensureAuditSyncId(audit.id!);

    final archive = Archive();

    final report = await ReportService.generate(
      site: site,
      audit: audit,
      defects: defects,
      photos: photos,
      galleryHref: 'ZDJECIA.html',
    );

    archive.addFile(
      ArchiveFile(
        'RAPORT_AUDYTU.pdf',
        report.bytes.length,
        report.bytes,
      ),
    );

    final valid = <_SourcePhoto>[];

    for (final defect in defects) {
      if (defect.id == null) continue;

      for (final photo
          in photos[defect.id] ?? const <AuditPhoto>[]) {
        if (await File(photo.path).exists()) {
          valid.add(
            _SourcePhoto(
              defect: defect,
              photo: photo,
            ),
          );
        }
      }
    }

    final targetBytes = valid.isEmpty
        ? 0
        : (_emailImageBudgetBytes ~/ valid.length)
            .clamp(90 * 1024, 330 * 1024)
            .toInt();

    final photosByDefect =
        <int, List<Map<String, Object?>>>{};

    var counter = 0;

    for (final source in valid) {
      final bytes = await PhotoService.compressForEmailPackage(
        source.photo.path,
        targetBytes: targetBytes,
      );

      final name =
          'photos/${_safe(source.defect.positionNo)}_${counter.toString().padLeft(3, '0')}_${source.photo.kind}.jpg';

      archive.addFile(
        ArchiveFile(
          name,
          bytes.length,
          bytes,
        ),
      );

      photosByDefect
          .putIfAbsent(
            source.defect.id!,
            () => <Map<String, Object?>>[],
          )
          .add({
        'file': name,
        'kind': source.photo.kind,
        'created_at': source.photo.createdAt.toIso8601String(),
      });

      counter++;
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
      'defects': defects
          .map(
            (defect) => {
              'position_no': defect.positionNo,
              'location': defect.location,
              'description': defect.description,
              'priority': defect.priority,
              'recommendation': defect.recommendation,
              'created_at': defect.createdAt.toIso8601String(),
              'is_resolved': defect.isResolved,
              'resolved_at':
                  defect.resolvedAt?.toIso8601String(),
              'resolution_note': defect.resolutionNote,
              'nameplate_unavailable':
                  defect.nameplateUnavailable,
              'photos': photosByDefect[defect.id] ??
                  const <Map<String, Object?>>[],
            },
          )
          .toList(),
    };

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent(' ').convert(manifest),
    );

    archive.addFile(
      ArchiveFile(
        'manifest.json',
        manifestBytes.length,
        manifestBytes,
      ),
    );

    final html = _buildGallery(
      site,
      defects,
      photosByDefect,
    );

    final htmlBytes = utf8.encode(html);

    archive.addFile(
      ArchiveFile(
        'ZDJECIA.html',
        htmlBytes.length,
        htmlBytes,
      ),
    );

    const readme = '''
PACZKA AUDYTU - AUDYTOR

RAPORT_AUDYTU.pdf
- aktualny raport PDF

ZDJECIA.html
- galeria wszystkich zdjęć
- kliknięcie miniatury otwiera pełne zdjęcie z folderu photos

photos/
- skompresowane zdjęcia do wysyłki

manifest.json
- dane potrzebne do importu audytu w aplikacji

Paczka może zostać przesłana do innego użytkownika aplikacji Audytor w celu wykonania weryfikacji lub reaudytu.
''';

    final readmeBytes = utf8.encode(readme);

    archive.addFile(
      ArchiveFile(
        'README.txt',
        readmeBytes.length,
        readmeBytes,
      ),
    );

    final encoded = ZipEncoder().encode(archive);

    if (encoded == null) {
      throw StateError(
          'Nie udało się utworzyć paczki audytu.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(docs.path, 'audit_packages'),
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final filename =
        'Audyt_${_safe(site.code.isNotEmpty ? site.code : site.name)}_${_stamp(audit.startedAt)}_do_weryfikacji.audyt.zip';

    final file = File(
      p.join(dir.path, filename),
    );

    await file.writeAsBytes(
      encoded,
      flush: true,
    );

    return AuditPackageExportResult(
      path: file.path,
      filename: filename,
      sizeBytes: await file.length(),
      photosCount: valid.length,
    );
  }

  static String _buildGallery(
    Site site,
    List<Defect> defects,
    Map<int, List<Map<String, Object?>>> photosByDefect,
  ) {
    String esc(String value) =>
        const HtmlEscape().convert(value);

    final out = StringBuffer();

    out.write(
      '<!doctype html><html lang="pl"><head><meta charset="utf-8">',
    );
    out.write(
      '<meta name="viewport" content="width=device-width,initial-scale=1">',
    );
    out.write(
      '<title>Zdjęcia audytu</title>',
    );
    out.write('<style>');
    out.write(
      'body{font-family:Arial,sans-serif;margin:20px;background:#f4f6f8;color:#182635}',
    );
    out.write(
      'section{background:#fff;padding:16px;margin:0 0 18px;border-radius:12px}',
    );
    out.write(
      '.photos{display:flex;flex-wrap:wrap;gap:10px}',
    );
    out.write(
      'figure{margin:0;width:220px}',
    );
    out.write(
      'img{width:220px;height:170px;object-fit:contain;background:#eee;border-radius:8px}',
    );
    out.write(
      'figcaption{font-size:12px;margin-top:4px;color:#526579}',
    );
    out.write('</style></head><body>');

    out.write(
      '<h1>Zdjęcia audytu – ${esc(site.name)}</h1>',
    );

    for (final defect in defects) {
      out.write(
        '<section id="usterka-${defect.id}">',
      );
      out.write(
        '<h2>Pozycja ${esc(defect.positionNo)}</h2>',
      );
      out.write(
        '<p>${esc(defect.description)}</p>',
      );

      if (defect.nameplateUnavailable) {
        out.write(
          '<p><strong>Brak tabliczki znamionowej.</strong></p>',
        );
      }

      out.write('<div class="photos">');

      for (final photo
          in photosByDefect[defect.id] ??
              const <Map<String, Object?>>[]) {
        final file = photo['file'] as String;
        final kind =
            (photo['kind'] as String?) ?? 'issue';

        final label = switch (kind) {
          'resolution' => 'Po naprawie',
          'nameplate' => 'Tabliczka znamionowa',
          _ => 'Usterka',
        };

        out.write(
          '<figure><a href="${esc(file)}"><img src="${esc(file)}" alt="${esc(label)}"></a>',
        );
        out.write(
          '<figcaption>${esc(label)}</figcaption></figure>',
        );
      }

      out.write('</div></section>');
    }

    out.write('</body></html>');

    return out.toString();
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

    final syncId =
        ((auditMap['sync_id'] as String?) ?? '').trim();

    if (syncId.isEmpty) {
      throw const FormatException(
          'Brak identyfikatora audytu.');
    }

    final existingAudit =
        await DatabaseService.instance.getAuditBySyncId(syncId);

    if (existingAudit != null && !allowUpdateExisting) {
      throw StateError(
          'Ten audyt już istnieje.');
    }

    final site = await _resolveSite(
      siteMap,
      existingAudit?.siteId,
    );

    late final int auditId;
    final updatedExisting = existingAudit != null;

    if (existingAudit == null) {
      auditId =
          await DatabaseService.instance.insertAudit(
        Audit(
          siteId: site.id!,
          auditor:
              (auditMap['auditor'] as String?) ?? '',
          auditType:
              (auditMap['audit_type'] as String?) ??
                  'Audyt',
          startedAt:
              DateTime.parse(auditMap['started_at'] as String),
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

      await DatabaseService.instance.updateAudit(
        existingAudit.copyWith(
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
              _parseDate(auditMap['completed_at']) ??
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

      late final int defectId;

      final importedDefect = Defect(
        id: existingDefect?.id,
        auditId: auditId,
        positionNo: position,
        location:
            (map['location'] as String?) ?? '',
        description:
            (map['description'] as String?) ?? '',
        priority:
            (map['priority'] as String?) ?? 'Średni',
        recommendation:
            (map['recommendation'] as String?) ?? '',
        createdAt:
            _parseDate(map['created_at']) ??
                DateTime.now(),
        isResolved: map['is_resolved'] == true,
        resolvedAt:
            _parseDate(map['resolved_at']),
        resolutionNote:
            (map['resolution_note'] as String?) ?? '',
        nameplateUnavailable:
            map['nameplate_unavailable'] == true,
      );

      if (existingDefect == null) {
        defectId =
            await DatabaseService.instance.insertDefect(
          importedDefect,
        );
      } else {
        defectId = existingDefect.id!;
        await DatabaseService.instance.updateDefect(
          importedDefect,
        );
      }

      final photoMaps =
          _asList(map['photos']).map(_asMap).toList();

      for (final kind in const <String>[
        'issue',
        'nameplate',
        'resolution',
      ]) {
        final old = await DatabaseService.instance
            .getPhotosForDefect(
          defectId,
          kind: kind,
        );

        for (final photo in old) {
          await PhotoService.deleteIfExists(photo.path);
        }

        final paths = <String>[];

        for (final photoMap in photoMaps.where(
          (x) => (x['kind'] as String?) == kind,
        )) {
          final entryName =
              photoMap['file'] as String?;

          if (entryName == null) continue;

          final bytes =
              decoded.entries[entryName];

          if (bytes == null || bytes.isEmpty) continue;

          paths.add(
            await PhotoService.persistBytes(
              Uint8List.fromList(bytes),
              prefix: 'import',
            ),
          );

          importedPhotos++;
        }

        await DatabaseService.instance.replacePhotos(
          defectId,
          paths,
          kind: kind,
        );
      }
    }

    return AuditPackageImportResult(
      auditId: auditId,
      siteId: site.id!,
      updatedExisting: updatedExisting,
      importedPhotos: importedPhotos,
    );
  }

  static Future<Site> _resolveSite(
    Map<String, Object?> siteMap,
    int? preferredSiteId,
  ) async {
    if (preferredSiteId != null) {
      final site =
          await DatabaseService.instance.getSiteById(
        preferredSiteId,
      );

      if (site != null) return site;
    }

    final code =
        ((siteMap['code'] as String?) ?? '').trim();
    final name =
        ((siteMap['name'] as String?) ?? 'Obiekt').trim();
    final address =
        ((siteMap['address'] as String?) ?? '').trim();

    final existing =
        await DatabaseService.instance.findSiteForImport(
      code: code,
      name: name,
      address: address,
    );

    if (existing != null) return existing;

    final id =
        await DatabaseService.instance.insertSite(
      Site(
        name: name.isEmpty
            ? 'Obiekt importowany'
            : name,
        address: address,
        code: code,
        createdAt:
            _parseDate(siteMap['created_at']) ??
                DateTime.now(),
      ),
    );

    return (await DatabaseService.instance.getSiteById(id))!;
  }

  static Future<_DecodedPackage> _decodePackage(
    String packagePath,
  ) async {
    final file = File(packagePath);

    if (!await file.exists()) {
      throw StateError(
          'Nie znaleziono pliku paczki.');
    }

    final bytes = await file.readAsBytes();

    final archive = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
    );

    final entries = <String, List<int>>{};

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
          'Brak manifestu paczki audytu.');
    }

    final raw =
        jsonDecode(utf8.decode(manifestBytes));

    if (raw is! Map) {
      throw const FormatException(
          'Nieprawidłowy manifest paczki.');
    }

    final manifest =
        Map<String, Object?>.from(raw);

    if (manifest['format'] != _format) {
      throw const FormatException(
          'To nie jest paczka aplikacji Audytor.');
    }

    final version =
        (manifest['version'] as num?)?.toInt() ?? 1;

    if (version < 1 || version > _formatVersion) {
      throw const FormatException(
          'Nieobsługiwana wersja paczki audytu.');
    }

    return _DecodedPackage(
      manifest: manifest,
      entries: entries,
    );
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return Map<String, Object?>.from(value);
    }

    return <String, Object?>{};
  }

  static List<Object?> _asList(Object? value) {
    if (value is List) {
      return List<Object?>.from(value);
    }

    return const <Object?>[];
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static String _stamp(DateTime value) {
    String two(int n) =>
        n.toString().padLeft(2, '0');

    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}';
  }

  static String _safe(String value) {
    final cleaned = value.trim().replaceAll(
          RegExp(
              r'[^a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ_-]+'),
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
  final AuditPhoto photo;

  const _SourcePhoto({
    required this.defect,
    required this.photo,
  });
}
