import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/audit.dart';
import '../models/audit_photo.dart';
import '../models/defect.dart';
import '../models/defect_note.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'audytor.db');

    _database = await openDatabase(
      path,
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV6(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try { await db.execute('ALTER TABLE defects ADD COLUMN is_resolved INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
          try { await db.execute('ALTER TABLE defects ADD COLUMN resolved_at TEXT'); } catch (_) {}
        }
        if (oldVersion < 3) {
          try { await db.execute("ALTER TABLE defects ADD COLUMN resolution_note TEXT NOT NULL DEFAULT ''"); } catch (_) {}
          try { await db.execute("ALTER TABLE photos ADD COLUMN kind TEXT NOT NULL DEFAULT 'issue'"); } catch (_) {}
        }
        if (oldVersion < 4) {
          try { await db.execute("ALTER TABLE audits ADD COLUMN sync_id TEXT NOT NULL DEFAULT ''"); } catch (_) {}
        }
        if (oldVersion < 5) {
          try { await db.execute('ALTER TABLE defects ADD COLUMN nameplate_unavailable INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
        }
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
      },
    );
    return _database!;
  }

  static Future<void> _createV6(Database db) async {
    await db.execute('''
      CREATE TABLE audits(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client TEXT NOT NULL DEFAULT '',
        store_number TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        auditor TEXT NOT NULL,
        audit_type TEXT NOT NULL DEFAULT 'Audyt techniczny',
        started_at TEXT NOT NULL,
        completed_at TEXT,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        sync_id TEXT NOT NULL DEFAULT ''
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
        is_resolved INTEGER NOT NULL DEFAULT 0,
        resolved_at TEXT,
        resolution_note TEXT NOT NULL DEFAULT '',
        nameplate_unavailable INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(audit_id) REFERENCES audits(id) ON DELETE CASCADE
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
    await _createNotesTables(db);
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');
  }

  static Future<void> _createNotesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS defect_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        defect_id INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(defect_id) REFERENCES defects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS defect_note_photos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(note_id) REFERENCES defect_notes(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _migrateToV6(Database db) async {
    await _createNotesTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE audits_new(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client TEXT NOT NULL DEFAULT '',
        store_number TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        auditor TEXT NOT NULL,
        audit_type TEXT NOT NULL DEFAULT 'Audyt techniczny',
        started_at TEXT NOT NULL,
        completed_at TEXT,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        sync_id TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      INSERT INTO audits_new(
        id, client, store_number, address, auditor, audit_type,
        started_at, completed_at, notes, status, sync_id
      )
      SELECT
        a.id,
        COALESCE(s.name, ''),
        COALESCE(s.code, ''),
        COALESCE(s.address, ''),
        a.auditor,
        a.audit_type,
        a.started_at,
        a.completed_at,
        a.notes,
        a.status,
        a.sync_id
      FROM audits a
      LEFT JOIN sites s ON s.id = a.site_id
    ''');
    await db.execute('DROP TABLE audits');
    await db.execute('ALTER TABLE audits_new RENAME TO audits');
    await db.execute('DROP TABLE IF EXISTS sites');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_audits_sync_id_unique
      ON audits(sync_id)
      WHERE TRIM(sync_id) <> ''
    ''');
  }

  Future<List<Audit>> getAudits() async {
    final db = await database;
    final rows = await db.query('audits', orderBy: 'started_at DESC');
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
    final id = await db.insert('audits', map);
    await setSetting('last_auditor', audit.auditor.trim());
    return id;
  }

  Future<void> updateAudit(Audit audit) async {
    if (audit.id == null) return;
    final db = await database;
    final map = audit.toMap()..remove('id');
    await db.update('audits', map, where: 'id = ?', whereArgs: [audit.id]);
  }

  Future<void> deleteAudit(int auditId) async {
    final db = await database;
    await db.delete('audits', where: 'id = ?', whereArgs: [auditId]);
  }

  Future<Audit?> getAuditBySyncId(String syncId) async {
    if (syncId.trim().isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'audits',
      where: 'sync_id = ?',
      whereArgs: [syncId.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Audit.fromMap(rows.first);
  }

  Future<String> ensureAuditSyncId(int auditId) async {
    final audit = await getAuditById(auditId);
    if (audit == null) throw StateError('Nie znaleziono audytu.');
    if (audit.syncId.trim().isNotEmpty) return audit.syncId;
    final syncId = _newSyncId();
    final db = await database;
    await db.update('audits', {'sync_id': syncId}, where: 'id = ?', whereArgs: [auditId]);
    return syncId;
  }

  Future<String> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? '' : ((rows.first['value'] as String?) ?? '');
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> confirmDefectResolution(int defectId, String note) async {
    final db = await database;
    final rows = await db.query(
      'defects',
      columns: ['resolved_at'],
      where: 'id = ?',
      whereArgs: [defectId],
      limit: 1,
    );
    final previous = rows.isEmpty ? null : rows.first['resolved_at'] as String?;
    await db.update(
      'defects',
      {
        'is_resolved': 1,
        'resolved_at': previous ?? DateTime.now().toIso8601String(),
        'resolution_note': note.trim(),
      },
      where: 'id = ?',
      whereArgs: [defectId],
    );
  }

  Future<void> clearDefectResolution(int defectId) async {
    final db = await database;
    await db.update(
      'defects',
      {'is_resolved': 0, 'resolved_at': null, 'resolution_note': ''},
      where: 'id = ?',
      whereArgs: [defectId],
    );
  }

  Future<List<AuditPhoto>> getPhotosForDefect(int defectId, {String? kind}) async {
    final db = await database;
    final rows = await db.query(
      'photos',
      where: kind == null ? 'defect_id = ?' : 'defect_id = ? AND kind = ?',
      whereArgs: kind == null ? [defectId] : [defectId, kind],
      orderBy: 'created_at ASC',
    );
    return rows.map(AuditPhoto.fromMap).toList();
  }

  Future<Map<int,List<AuditPhoto>>> getPhotosForDefects(List<Defect> defects) async {
    final result = <int,List<AuditPhoto>>{};
    for (final defect in defects) {
      if (defect.id != null) {
        result[defect.id!] = await getPhotosForDefect(defect.id!);
      }
    }
    return result;
  }

  Future<void> replacePhotos(int defectId, List<String> paths, {String kind = 'issue'}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('photos', where: 'defect_id = ? AND kind = ?', whereArgs: [defectId, kind]);
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

  Future<int> addDefectNote({
    required int defectId,
    required String text,
    required List<String> photoPaths,
    DateTime? createdAt,
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final noteId = await txn.insert('defect_notes', {
        'defect_id': defectId,
        'note': text.trim(),
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      });
      for (final path in photoPaths) {
        await txn.insert('defect_note_photos', {
          'note_id': noteId,
          'path': path,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      return noteId;
    });
  }

  Future<List<DefectNote>> getNotesForDefect(int defectId) async {
    final db = await database;
    final rows = await db.query(
      'defect_notes',
      where: 'defect_id = ?',
      whereArgs: [defectId],
      orderBy: 'created_at ASC',
    );
    final result = <DefectNote>[];
    for (final row in rows) {
      final noteId = row['id'] as int;
      final photoRows = await db.query(
        'defect_note_photos',
        columns: ['path'],
        where: 'note_id = ?',
        whereArgs: [noteId],
        orderBy: 'created_at ASC',
      );
      result.add(DefectNote(
        id: noteId,
        defectId: defectId,
        text: (row['note'] as String?) ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        photoPaths: photoRows.map((x) => x['path'] as String).toList(),
      ));
    }
    return result;
  }

  Future<Map<int,List<DefectNote>>> getNotesForDefects(List<Defect> defects) async {
    final result = <int,List<DefectNote>>{};
    for (final defect in defects) {
      if (defect.id != null) {
        result[defect.id!] = await getNotesForDefect(defect.id!);
      }
    }
    return result;
  }

  Future<void> clearDefectNotes(int defectId) async {
    final db = await database;
    await db.delete(
      'defect_notes',
      where: 'defect_id = ?',
      whereArgs: [defectId],
    );
  }

  Future<List<String>> getPhotoPathsForAudit(int auditId) async {
    final db = await database;
    final normal = await db.rawQuery('''
      SELECT p.path
      FROM photos p
      INNER JOIN defects d ON d.id = p.defect_id
      WHERE d.audit_id = ?
    ''', [auditId]);
    final follow = await db.rawQuery('''
      SELECT np.path
      FROM defect_note_photos np
      INNER JOIN defect_notes n ON n.id = np.note_id
      INNER JOIN defects d ON d.id = n.defect_id
      WHERE d.audit_id = ?
    ''', [auditId]);
    return [
      ...normal.map((x) => x['path'] as String),
      ...follow.map((x) => x['path'] as String),
    ];
  }

  String _newSyncId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return 'aud_${DateTime.now().microsecondsSinceEpoch}_$random';
  }
}
