class Audit {
  final int? id;
  final int siteId;
  final String auditor;
  final String auditType;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String notes;
  final String status;
  final String syncId;

  const Audit({
    this.id,
    required this.siteId,
    required this.auditor,
    required this.auditType,
    required this.startedAt,
    this.completedAt,
    required this.notes,
    required this.status,
    this.syncId = '',
  });

  bool get isCompleted => status == 'completed';

  Audit copyWith({
    int? id,
    int? siteId,
    String? auditor,
    String? auditType,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
    String? status,
    String? syncId,
  }) {
    return Audit(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      auditor: auditor ?? this.auditor,
      auditType: auditType ?? this.auditType,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      syncId: syncId ?? this.syncId,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'site_id': siteId,
        'auditor': auditor,
        'audit_type': auditType,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'notes': notes,
        'status': status,
        'sync_id': syncId,
      };

  factory Audit.fromMap(Map<String, Object?> map) => Audit(
        id: map['id'] as int?,
        siteId: map['site_id'] as int,
        auditor: map['auditor'] as String,
        auditType: map['audit_type'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.parse(map['completed_at'] as String),
        notes: (map['notes'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'draft',
        syncId: (map['sync_id'] as String?) ?? '',
      );
}
