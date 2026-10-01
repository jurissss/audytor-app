class Audit {
  final int? id;
  final String client;
  final String storeNumber;
  final String address;
  final String auditor;
  final String auditType;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String notes;
  final String status;
  final String syncId;

  const Audit({
    this.id,
    required this.client,
    required this.storeNumber,
    required this.address,
    required this.auditor,
    this.auditType = 'Audyt techniczny',
    required this.startedAt,
    this.completedAt,
    this.notes = '',
    this.status = 'draft',
    this.syncId = '',
  });

  bool get isCompleted => status == 'completed';

  Audit copyWith({
    int? id,
    String? client,
    String? storeNumber,
    String? address,
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
      client: client ?? this.client,
      storeNumber: storeNumber ?? this.storeNumber,
      address: address ?? this.address,
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
        'client': client,
        'store_number': storeNumber,
        'address': address,
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
        client: (map['client'] as String?) ?? '',
        storeNumber: (map['store_number'] as String?) ?? '',
        address: (map['address'] as String?) ?? '',
        auditor: (map['auditor'] as String?) ?? '',
        auditType: (map['audit_type'] as String?) ?? 'Audyt techniczny',
        startedAt: DateTime.parse(map['started_at'] as String),
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.parse(map['completed_at'] as String),
        notes: (map['notes'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'draft',
        syncId: (map['sync_id'] as String?) ?? '',
      );
}
