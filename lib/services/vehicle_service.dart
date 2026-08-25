import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/models/vehicle_model.dart';

class VehicleService {
  static const String _activeVehicleKey = 'active_vehicle_id';

  /// Notificador reativo do veículo ativo selecionado na sessão
  static final ValueNotifier<Map<String, dynamic>?> activeVehicleNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// Notificador reativo da lista de todos os veículos do usuário
  static final ValueNotifier<List<Map<String, dynamic>>> userVehiclesNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  /// Inicializa e carrega os veículos do usuário logado
  static Future<List<Map<String, dynamic>>> loadVehicles({
    String? preferredVehicleId,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      activeVehicleNotifier.value = null;
      userVehiclesNotifier.value = [];
      return [];
    }

    try {
      final data = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      final list = (data as List)
          .map((v) => Vehicle.fromMap(Map<String, dynamic>.from(v)).toMap())
          .toList();
      userVehiclesNotifier.value = list;

      if (list.isEmpty) {
        activeVehicleNotifier.value = null;
        return [];
      }

      // Recupera preferências locais de veículo ativo
      final prefs = await SharedPreferences.getInstance();
      final savedId = preferredVehicleId ?? prefs.getString(_activeVehicleKey);

      Map<String, dynamic>? selected;
      if (savedId != null) {
        selected = list.firstWhere(
          (v) => v['id']?.toString() == savedId,
          orElse: () => list.first,
        );
      } else {
        selected = list.first;
      }

      activeVehicleNotifier.value = selected;
      if (selected['id'] != null) {
        await prefs.setString(_activeVehicleKey, selected['id'].toString());
      }

      return list;
    } catch (e) {
      debugPrint('--- ERRO AO CARREGAR VEÍCULOS NO VEHICLE SERVICE: $e ---');
      return userVehiclesNotifier.value;
    }
  }

  /// Define um veículo específico como ativo na sessão e persiste no SharedPreferences
  static Future<void> setActiveVehicle(Map<String, dynamic> vehicle) async {
    activeVehicleNotifier.value = vehicle;
    final vehicleId = vehicle['id']?.toString();
    if (vehicleId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeVehicleKey, vehicleId);
    }
  }

  /// Cadastra um novo veículo no Supabase e o define como ativo automaticamente
  static Future<Map<String, dynamic>?> addVehicle({
    required String brand,
    required String model,
    required String year,
    required int mileage,
    required String drivetrain,
    String? nickname,
    String? description,
    String? photoUrl,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    try {
      final payload = <String, dynamic>{
        'user_id': user.id,
        'brand': brand.trim(),
        'model': model.trim(),
        'year': year.trim(),
        'mileage': mileage,
        'drivetrain': drivetrain.trim().toUpperCase(),
        'nickname': (nickname != null && nickname.trim().isNotEmpty) ? nickname.trim() : null,
        'description': description?.trim() ?? '',
        'veiculo_foto_url': photoUrl,
        'created_at': DateTime.now().toIso8601String(),
      };

      final newRecords = await Supabase.instance.client
          .from('vehicles')
          .insert(payload)
          .select();

      final firstRecord = (newRecords as List).first;
      final createdVehicle = Vehicle.fromMap(Map<String, dynamic>.from(firstRecord)).toMap();
      await loadVehicles(preferredVehicleId: createdVehicle['id']?.toString());
      return createdVehicle;
    } catch (e) {
      debugPrint('--- ERRO AO ADICIONAR NOVO VEÍCULO: $e ---');
      rethrow;
    }
  }

  /// Atualiza os dados de um veículo existente
  static Future<void> updateVehicle({
    required String vehicleId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final cleanUpdates = Map<String, dynamic>.from(updates);
      cleanUpdates['updated_at'] = DateTime.now().toIso8601String();

      // Mapeamento estrito para as colunas do Supabase
      if (cleanUpdates.containsKey('nickname') && cleanUpdates['nickname'] is String) {
        final nick = (cleanUpdates['nickname'] as String).trim();
        cleanUpdates['nickname'] = nick.isEmpty ? null : nick;
      }
      if (cleanUpdates.containsKey('year') && cleanUpdates['year'] != null) {
        cleanUpdates['year'] = cleanUpdates['year'].toString().trim();
      }

      await Supabase.instance.client
          .from('vehicles')
          .update(cleanUpdates)
          .eq('id', vehicleId);

      await loadVehicles(preferredVehicleId: vehicleId);
    } catch (e) {
      debugPrint('--- ERRO AO ATUALIZAR VEÍCULO: $e ---');
      rethrow;
    }
  }

  /// Exclui um veículo e desvincula/remove seus registros no Supabase
  static Future<void> deleteVehicle(String vehicleId) async {
    try {
      final client = Supabase.instance.client;
      // 1. Remove os abastecimentos e manutenções atrelados a este veículo
      await client.from('refuels').delete().eq('vehicle_id', vehicleId);
      await client.from('vehicle_maintenances').delete().eq('vehicle_id', vehicleId);

      // 2. Remove o registro do veículo
      await client.from('vehicles').delete().eq('id', vehicleId);

      // 3. Limpa a preferência local se o excluído for o ativo
      final prefs = await SharedPreferences.getInstance();
      if (activeVehicleNotifier.value?['id']?.toString() == vehicleId) {
        await prefs.remove(_activeVehicleKey);
      }

      // 4. Recarrega a lista de veículos
      await loadVehicles();
    } catch (e) {
      debugPrint('--- ERRO AO EXCLUIR VEÍCULO: $e ---');
      rethrow;
    }
  }
}
