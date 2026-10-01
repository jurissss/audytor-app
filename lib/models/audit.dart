class Audit {
  final int? id;
  final int siteId;
  final String auditor;
  final String auditType;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String notes;
  final String status;
  final int? parentAuditId;
  final DateTime? reauditStartedAt;
  final DateTime? reauditCompletedAt;
  final String reauditNotes;
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
    this.parentAuditId,
    this.reauditStartedAt,
    this.reauditCompletedAt,
    this.reauditNotes = '',
    this.syncId = '',
  });

  bool get isCompleted => status == 'completed';
  bool get isReaudit => parentAuditId != null;
  bool get hasReaudit => reauditStartedAt != null;
  bool get isReauditInProgress => reauditStartedAt != null && reauditCompletedAt == null;
  bool get isReauditCompleted => reauditCompletedAt != null;

  Audit copyWith({
    int? id,
    int? siteId,
    String? auditor,
    String? auditType,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
    String? status,
    int? parentAuditId,
    DateTime? reauditStartedAt,
    DateTime? reauditCompletedAt,
    String? reauditNotes,
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
      parentAuditId: parentAuditId ?? this.parentAuditId,
      reauditStartedAt: reauditStartedAt ?? this.reauditStartedAt,
      reauditCompletedAt: reauditCompletedAt ?? this.reauditCompletedAt,
      reauditNotes: reauditNotes ?? this.reauditNotes,
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
        'parent_audit_id': parentAuditId,
        'reaudit_started_at': reauditStartedAt?.toIso8601String(),
        'reaudit_completed_at': reauditCompletedAt?.toIso8601String(),
        'reaudit_notes': reauditNotes,
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
        parentAuditId: map['parent_audit_id'] as int?,
        reauditStartedAt: map['reaudit_started_at'] == null
            ? null
            : DateTime.parse(map['reaudit_started_at'] as String),
        reauditCompletedAt: map['reaudit_completed_at'] == null
            ? null
            : DateTime.parse(map['reaudit_completed_at'] as String),
        reauditNotes: (map['reaudit_notes'] as String?) ?? '',
        syncId: (map['sync_id'] as String?) ?? '',
      );
}
