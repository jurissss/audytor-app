import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/site.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, 'audytor.db'),
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sites(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT NOT NULL DEFAULT '',
            code TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_sites_code_unique
          ON sites(code COLLATE NOCASE)
          WHERE TRIM(code) <> ''
        ''');
        await db.execute('''
          CREATE TABLE audits(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            site_id INTEGER NOT NULL,
            auditor TEXT NOT NULL,
            audit_type TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            notes TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'draft',
            parent_audit_id INTEGER,
            reaudit_started_at TEXT,
            reaudit_completed_at TEXT,
            reaudit_notes TEXT NOT NULL DEFAULT '',
            sync_id TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(site_id) REFERENCES sites(id) ON DELETE CASCADE,
            FOREIGN KEY(parent_audit_id) REFERENCES audits(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_audits_sync_id_unique
          ON audits(sync_id)
          WHERE TRIM(sync_id) <> ''
        ''');
        await db.execute('''
          CREATE TABLE defects(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            audit_id INTEGER NOT NULL,
            position_no TEXT NOT NULL,
            location TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL,
            priority TEXT NOT NULL DEFAULT 'Średni',
            recommendation TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            source_defect_id INTEGER,
            is_resolved INTEGER NOT NULL DEFAULT 0,
            resolved_at TEXT,
            resolution_note TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(audit_id) REFERENCES audits(id) ON DELETE CASCADE,
            FOREIGN KEY(source_defect_id) REFERENCES defects(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE photos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            defect_id INTEGER NOT NULL,
            path TEXT NOT NULL,
            created_at TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'issue',
            FOREIGN KEY(defect_id) REFERENCES defects(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE audits ADD COLUMN parent_audit_id INTEGER');
          await db.execute('ALTER TABLE defects ADD COLUMN source_defect_id INTEGER');
          await db.execute('ALTER TABLE defects ADD COLUMN is_resolved INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE defects ADD COLUMN resolved_at TEXT');
          try {
            await db.execute('''
              CREATE UNIQUE INDEX idx_sites_code_unique
              ON sites(code COLLATE NOCASE)
              WHERE TRIM(code) <> ''
            ''');
          } catch (_) {
            // Stara baza może zawierać duplikaty. Formularz nadal blokuje nowe.
          }
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE audits ADD COLUMN reaudit_started_at TEXT');
          await db.execute('ALTER TABLE audits ADD COLUMN reaudit_completed_at TEXT');
          await db.execute("ALTER TABLE audits ADD COLUMN reaudit_notes TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE defects ADD COLUMN resolution_note TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE photos ADD COLUMN kind TEXT NOT NULL DEFAULT 'issue'");
        }

        if (oldVersion < 4) {
          await db.execute("ALTER TABLE audits ADD COLUMN sync_id TEXT NOT NULL DEFAULT ''");
          try {
            await db.execute('''
              CREATE UNIQUE INDEX idx_audits_sync_id_unique
              ON audits(sync_id)
              WHERE TRIM(sync_id) <> ''
            ''');
          } catch (_) {
            // Nie blokujemy migracji starej bazy.
          }
        }
      },
    );
    return _database!;
  }

  Future<List<Site>> getSites() async {
    final db = await database;
    final rows = await db.query('sites', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Site.fromMap).toList();
  }

  Future<Site?> getSiteById(int id) async {
    final db = await database;
    final rows = await db.query('sites', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Site.fromMap(rows.first);
  }

  Future<Site?> findSiteForImport({
    required String code,
    required String name,
    required String address,
  }) async {
    final db = await database;
    if (code.trim().isNotEmpty) {
      final rows = await db.query(
        'sites',
        where: 'LOWER(TRIM(code)) = LOWER(?)',
        whereArgs: [code.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) return Site.fromMap(rows.first);
    }
    final rows = await db.query(
      'sites',
      where: 'LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(address)) = LOWER(?)',
      whereArgs: [name.trim(), address.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Site.fromMap(rows.first);
  }

  Future<bool> isSiteCodeTaken(String code, {int? excludeSiteId}) async {
    final normalized = code.trim();
    if (normalized.isEmpty) return false;
    final db = await database;
    final where = excludeSiteId == null
        ? 'LOWER(TRIM(code)) = LOWER(?)'
        : 'LOWER(TRIM(code)) = LOWER(?) AND id <> ?';
    final args = excludeSiteId == null
        ? <Object?>[normalized]
        : <Object?>[normalized, excludeSiteId];
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM sites WHERE $where', args);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  Future<int> insertSite(Site site) async {
    final db = await database;
    final map = site.toMap()..remove('id');
    return db.insert('sites', map);
  }

  Future<void> updateSite(Site site) async {
    if (site.id == null) return;
    final db = await database;
    final map = site.toMap()..remove('id');
    await db.update('sites', map, where: 'id = ?', whereArgs: [site.id]);
  }

  Future<void> deleteSite(int id) async {
    final db = await database;
    await db.delete('sites', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getPhotoPathsForSite(int siteId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.path
      FROM photos p
      INNER JOIN defects d ON d.id = p.defect_id
      INNER JOIN audits a ON a.id = d.audit_id
      WHERE a.site_id = ?
    ''', [siteId]);
    return rows.map((row) => row['path'] as String).toList();
  }

  Future<List<Audit>> getAuditsForSite(int siteId) async {
    final db = await database;
    final rows = await db.query(
      'audits',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'started_at DESC',
    );
    return rows.map(Audit.fromMap).toList();
  }

  Future<List<Audit>> getRecentAudits({int limit = 8}) async {
    final db = await database;
    final rows = await db.query(
      'audits',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(Audit.fromMap).toList();
  }

  Future<Audit?> getAuditById(int id) async {
    final db = await database;
    final rows = await db.query('audits', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Audit.fromMap(rows.first);
  }

  Future<int> insertAudit(Audit audit) async {
    final db = await database;
    final map = audit.toMap()..remove('id');
    if (((map['sync_id'] as String?) ?? '').trim().isEmpty) {
      map['sync_id'] = _newSyncId();
    }
    return db.insert('audits', map);
  }

  Future<Audit?> getAuditBySyncId(String syncId) async {
    final normalized = syncId.trim();
    if (normalized.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'audits',
      where: 'sync_id = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    return rows.isEmpty ? null : Audit.fromMap(rows.first);
  }

  Future<String> ensureAuditSyncId(int auditId) async {
    final db = await database;
    final rows = await db.query(
      'audits',
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [auditId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Nie znaleziono audytu.');
    final current = ((rows.first['sync_id'] as String?) ?? '').trim();
    if (current.isNotEmpty) return current;
    final generated = _newSyncId();
    await db.update('audits', {'sync_id': generated}, where: 'id = ?', whereArgs: [auditId]);
    return generated;
  }

  Future<void> updateAudit(Audit audit) async {
    if (audit.id == null) return;
    final db = await database;
    final map = audit.toMap()..remove('id');
    await db.update('audits', map, where: 'id = ?', whereArgs: [audit.id]);
  }

  Future<void> startReaudit(int auditId) async {
    final db = await database;
    await db.update(
      'audits',
      {
        'reaudit_started_at': DateTime.now().toIso8601String(),
        'reaudit_completed_at': null,
        'reaudit_notes': '',
      },
      where: 'id = ?',
      whereArgs: [auditId],
    );
  }

  Future<void> completeReaudit(int auditId, String notes) async {
    final db = await database;
    await db.update(
      'audits',
      {
        'reaudit_completed_at': DateTime.now().toIso8601String(),
        'reaudit_notes': notes.trim(),
      },
      where: 'id = ?',
      whereArgs: [auditId],
    );
  }

  Future<List<String>> getPhotoPathsForAudit(int auditId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.path
      FROM photos p
      INNER JOIN defects d ON d.id = p.defect_id
      WHERE d.audit_id = ?
    ''', [auditId]);
    return rows.map((row) => row['path'] as String).toList();
  }

  Future<void> deleteAudit(int auditId) async {
    final db = await database;
    await db.delete('audits', where: 'id = ?', whereArgs: [auditId]);
  }

  Future<int> countDefects(int auditId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM defects WHERE audit_id = ?',
      [auditId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countResolvedDefects(int auditId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM defects WHERE audit_id = ? AND is_resolved = 1',
      [auditId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Defect>> getDefectsForAudit(int auditId) async {
    final db = await database;
    final rows = await db.query(
      'defects',
      where: 'audit_id = ?',
      whereArgs: [auditId],
      orderBy: "CAST(position_no AS INTEGER) ASC, position_no ASC",
    );
    return rows.map(Defect.fromMap).toList();
  }

  Future<Defect?> getDefectByPositionNo(int auditId, String positionNo) async {
    final db = await database;
    final rows = await db.query(
      'defects',
      where: 'audit_id = ? AND position_no = ?',
      whereArgs: [auditId, positionNo],
      limit: 1,
    );
    return rows.isEmpty ? null : Defect.fromMap(rows.first);
  }

  Future<int> insertDefect(Defect defect) async {
    final db = await database;
    final map = defect.toMap()..remove('id');
    return db.insert('defects', map);
  }

  Future<void> updateDefect(Defect defect) async {
    if (defect.id == null) return;
    final db = await database;
    final map = defect.toMap()..remove('id');
    await db.update('defects', map, where: 'id = ?', whereArgs: [defect.id]);
  }

  Future<void> confirmDefectResolution(int defectId, String note) async {
    final db = await database;
    final rows = await db.query(
      'defects',
      columns: ['resolved_at'],
      where: 'id = ?',
      whereArgs: [defectId],
      limit: 1,
    );
    final existingResolvedAt = rows.isEmpty ? null : rows.first['resolved_at'] as String?;
    await db.update(
      'defects',
      {
        'is_resolved': 1,
        'resolved_at': existingResolvedAt ?? DateTime.now().toIso8601String(),
        'resolution_note': note.trim(),
      },
      where: 'id = ?',
      whereArgs: [defectId],
    );
  }

  Future<void> updateDefectResolutionFromImport(
    int defectId, {
    required bool isResolved,
    DateTime? resolvedAt,
    required String note,
  }) async {
    final db = await database;
    await db.update(
      'defects',
      {
        'is_resolved': isResolved ? 1 : 0,
        'resolved_at': isResolved ? resolvedAt?.toIso8601String() : null,
        'resolution_note': isResolved ? note.trim() : '',
      },
      where: 'id = ?',
      whereArgs: [defectId],
    );
  }

  Future<void> clearDefectResolution(int defectId) async {
    final db = await database;
    await db.update(
      'defects',
      {
        'is_resolved': 0,
        'resolved_at': null,
        'resolution_note': '',
      },
      where: 'id = ?',
      whereArgs: [defectId],
    );
  }

  Future<void> deleteDefect(int id) async {
    final db = await database;
    await db.delete('defects', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> getNextPositionNo(int auditId) async {
    final defects = await getDefectsForAudit(auditId);
    var max = 0;
    for (final defect in defects) {
      final n = int.tryParse(defect.positionNo) ?? 0;
      if (n > max) max = n;
    }
    return (max + 1).toString().padLeft(3, '0');
  }

  Future<List<AuditPhoto>> getPhotosForDefect(
    int defectId, {
    String? kind,
  }) async {
    final db = await database;
    final rows = await db.query(
      'photos',
      where: kind == null ? 'defect_id = ?' : 'defect_id = ? AND kind = ?',
      whereArgs: kind == null ? [defectId] : [defectId, kind],
      orderBy: 'created_at ASC',
    );
    return rows.map(AuditPhoto.fromMap).toList();
  }

  Future<void> replacePhotos(
    int defectId,
    List<String> paths, {
    String kind = 'issue',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'photos',
        where: 'defect_id = ? AND kind = ?',
        whereArgs: [defectId, kind],
      );
      for (final path in paths) {
        await txn.insert('photos', {
          'defect_id': defectId,
          'path': path,
          'created_at': DateTime.now().toIso8601String(),
          'kind': kind,
        });
      }
    });
  }

  Future<Map<int, List<AuditPhoto>>> getPhotosForDefects(
    List<Defect> defects, {
    String? kind,
  }) async {
    final result = <int, List<AuditPhoto>>{};
    for (final defect in defects) {
      if (defect.id != null) {
        result[defect.id!] = await getPhotosForDefect(defect.id!, kind: kind);
      }
    }
    return result;
  }

  String _newSyncId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return 'aud_${DateTime.now().microsecondsSinceEpoch}_$random';
  }

}
