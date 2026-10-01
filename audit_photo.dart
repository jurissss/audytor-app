class AuditPhoto {
  final int? id;
  final int defectId;
  final String path;
  final DateTime createdAt;
  final String kind;

  const AuditPhoto({
    this.id,
    required this.defectId,
    required this.path,
    required this.createdAt,
    this.kind = 'issue',
  });

  bool get isIssue => kind == 'issue';
  bool get isNameplate => kind == 'nameplate';
  bool get isResolution => kind == 'resolution';

  Map<String, Object?> toMap() => {
        'id': id,
        'defect_id': defectId,
        'path': path,
        'created_at': createdAt.toIso8601String(),
        'kind': kind,
      };

  factory AuditPhoto.fromMap(Map<String, Object?> map) => AuditPhoto(
        id: map['id'] as int?,
        defectId: map['defect_id'] as int,
        path: map['path'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        kind: (map['kind'] as String?) ?? 'issue',
      );
}
