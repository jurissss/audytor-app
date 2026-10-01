class DefectNote {
  final int? id;
  final int defectId;
  final String text;
  final DateTime createdAt;
  final List<String> photoPaths;

  const DefectNote({
    this.id,
    required this.defectId,
    required this.text,
    required this.createdAt,
    this.photoPaths = const [],
  });
}
