class Vehicle {
  final String id;
  final String userId;
  final String brand;
  final String model;
  final String? year;
  final int mileage;
  final String? drivetrain;
  final String? nickname;
  final String? description;
  final String? veiculoFotoUrl;
  final String? jarvisLastInsight;
  final String? jarvisInsightStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Vehicle({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    this.year,
    required this.mileage,
    this.drivetrain,
    this.nickname,
    this.description,
    this.veiculoFotoUrl,
    this.jarvisLastInsight,
    this.jarvisInsightStatus,
    this.createdAt,
    this.updatedAt,
  });

  /// Instancia um objeto Vehicle a partir de um Map vindo do Supabase
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      brand: map['brand'] as String? ?? '',
      model: map['model'] as String? ?? '',
      year: map['year']?.toString(),
      mileage: (map['mileage'] as num?)?.toInt() ?? 0,
      drivetrain: map['drivetrain'] as String?,
      nickname: map['nickname'] as String?,
      description: map['description'] as String?,
      veiculoFotoUrl: map['veiculo_foto_url'] as String?,
      jarvisLastInsight: map['jarvis_last_insight'] as String?,
      jarvisInsightStatus: map['jarvis_insight_status'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  /// Converte o objeto Vehicle para Map pronto para persistência no Supabase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'brand': brand,
      'model': model,
      if (year != null) 'year': year,
      'mileage': mileage,
      if (drivetrain != null) 'drivetrain': drivetrain,
      if (nickname != null) 'nickname': nickname,
      if (description != null) 'description': description,
      if (veiculoFotoUrl != null) 'veiculo_foto_url': veiculoFotoUrl,
      if (jarvisLastInsight != null) 'jarvis_last_insight': jarvisLastInsight,
      if (jarvisInsightStatus != null) 'jarvis_insight_status': jarvisInsightStatus,
    };
  }

  /// Retorna uma cópia do Vehicle com os campos atualizados
  Vehicle copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? year,
    int? mileage,
    String? drivetrain,
    String? nickname,
    String? description,
    String? veiculoFotoUrl,
    String? jarvisLastInsight,
    String? jarvisInsightStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      mileage: mileage ?? this.mileage,
      drivetrain: drivetrain ?? this.drivetrain,
      nickname: nickname ?? this.nickname,
      description: description ?? this.description,
      veiculoFotoUrl: veiculoFotoUrl ?? this.veiculoFotoUrl,
      jarvisLastInsight: jarvisLastInsight ?? this.jarvisLastInsight,
      jarvisInsightStatus: jarvisInsightStatus ?? this.jarvisInsightStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
