class Site {
  final int? id;
  final String name;
  final String address;
  final String code;
  final DateTime createdAt;

  const Site({
    this.id,
    required this.name,
    required this.address,
    required this.code,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'code': code,
        'created_at': createdAt.toIso8601String(),
      };

  factory Site.fromMap(Map<String, Object?> map) => Site(
        id: map['id'] as int?,
        name: map['name'] as String,
        address: (map['address'] as String?) ?? '',
        code: (map['code'] as String?) ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
