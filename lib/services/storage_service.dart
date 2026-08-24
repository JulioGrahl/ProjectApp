import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  static final ImagePicker _picker = ImagePicker();

  /// Permite ao usuário escolher uma imagem da Galeria ou Câmera
  static Future<XFile?> pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      debugPrint('--- ERRO AO SELECIONAR IMAGEM: $e ---');
      return null;
    }
  }

  /// Envia a foto de perfil do usuário para o bucket `perfis_fotos` do Supabase Storage
  /// e atualiza o `user_metadata` com a URL pública resultante.
  static Future<String?> uploadProfilePhoto(XFile file) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final extension = file.name.split('.').last.toLowerCase();
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await Supabase.instance.client.storage
          .from('perfis_fotos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('perfis_fotos')
          .getPublicUrl(fileName);

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            ...user.userMetadata ?? {},
            'avatar_url': publicUrl,
          },
        ),
      );

      return publicUrl;
    } catch (e) {
      debugPrint('--- ERRO AO UPLOAD FOTO PERFIL: $e ---');
      rethrow;
    }
  }

  /// Remove a foto de perfil do usuário (atualizando `avatar_url` no metadata para null)
  static Future<void> removeProfilePhoto() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final updatedData = Map<String, dynamic>.from(user.userMetadata ?? {});
      updatedData.remove('avatar_url');
      updatedData['avatar_url'] = null;

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: updatedData,
        ),
      );
    } catch (e) {
      debugPrint('--- ERRO AO REMOVER FOTO PERFIL: $e ---');
      rethrow;
    }
  }

  /// Envia a foto do veículo para o bucket `veiculos_fotos` do Supabase Storage
  /// e atualiza a coluna `veiculo_foto_url` na tabela `vehicles`.
  static Future<String?> uploadVehiclePhoto(dynamic vehicleId, XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final extension = file.name.split('.').last.toLowerCase();
      final fileName = '${vehicleId}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await Supabase.instance.client.storage
          .from('veiculos_fotos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$extension',
              upsert: true,
            ),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('veiculos_fotos')
          .getPublicUrl(fileName);

      await Supabase.instance.client
          .from('vehicles')
          .update({'veiculo_foto_url': publicUrl})
          .eq('id', vehicleId);

      return publicUrl;
    } catch (e) {
      debugPrint('--- ERRO AO UPLOAD FOTO VEÍCULO: $e ---');
      rethrow;
    }
  }

  /// Remove a foto do veículo (setando `veiculo_foto_url` como null na tabela `vehicles`)
  static Future<void> removeVehiclePhoto(dynamic vehicleId) async {
    try {
      await Supabase.instance.client
          .from('vehicles')
          .update({'veiculo_foto_url': null})
          .eq('id', vehicleId);
    } catch (e) {
      debugPrint('--- ERRO AO REMOVER FOTO VEÍCULO: $e ---');
      rethrow;
    }
  }
}
