class Defect {
  final int? id;
  final int auditId;
  final String positionNo;
  final String location;
  final String description;
  final String priority;
  final String recommendation;
  final DateTime createdAt;
  final int? sourceDefectId;
  final bool isResolved;
  final DateTime? resolvedAt;
  final String resolutionNote;

  const Defect({
    this.id,
    required this.auditId,
    required this.positionNo,
    required this.location,
    required this.description,
    required this.priority,
    required this.recommendation,
    required this.createdAt,
    this.sourceDefectId,
    this.isResolved = false,
    this.resolvedAt,
    this.resolutionNote = '',
  });

  bool get inheritedFromPreviousAudit => sourceDefectId != null;

  Defect copyWith({
    int? id,
    int? auditId,
    String? positionNo,
    String? location,
    String? description,
    String? priority,
    String? recommendation,
    DateTime? createdAt,
    int? sourceDefectId,
    bool? isResolved,
    DateTime? resolvedAt,
    String? resolutionNote,
  }) {
    return Defect(
      id: id ?? this.id,
      auditId: auditId ?? this.auditId,
      positionNo: positionNo ?? this.positionNo,
      location: location ?? this.location,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      recommendation: recommendation ?? this.recommendation,
      createdAt: createdAt ?? this.createdAt,
      sourceDefectId: sourceDefectId ?? this.sourceDefectId,
      isResolved: isResolved ?? this.isResolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolutionNote: resolutionNote ?? this.resolutionNote,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'audit_id': auditId,
        'position_no': positionNo,
        'location': location,
        'description': description,
        'priority': priority,
        'recommendation': recommendation,
        'created_at': createdAt.toIso8601String(),
        'source_defect_id': sourceDefectId,
        'is_resolved': isResolved ? 1 : 0,
        'resolved_at': resolvedAt?.toIso8601String(),
        'resolution_note': resolutionNote,
      };

  factory Defect.fromMap(Map<String, Object?> map) => Defect(
        id: map['id'] as int?,
        auditId: map['audit_id'] as int,
        positionNo: map['position_no'] as String,
        location: (map['location'] as String?) ?? '',
        description: map['description'] as String,
        priority: (map['priority'] as String?) ?? 'Średni',
        recommendation: (map['recommendation'] as String?) ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        sourceDefectId: map['source_defect_id'] as int?,
        isResolved: ((map['is_resolved'] as int?) ?? 0) == 1,
        resolvedAt: map['resolved_at'] == null
            ? null
            : DateTime.parse(map['resolved_at'] as String),
        resolutionNote: (map['resolution_note'] as String?) ?? '',
      );
}
