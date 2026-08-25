import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/storage_service.dart';
import 'package:projectapp/services/theme_service.dart';
import 'package:projectapp/services/vehicle_service.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/views/alert_preferences_view.dart';
import 'package:projectapp/views/vehicle_info_view.dart';
import 'package:projectapp/views/vehicle_maintenances_view.dart';

// ─────────────────────────────────────────────
// ACCOUNT VIEW — NIGHT DRIVER / MODERN BRUTALISM
// ─────────────────────────────────────────────

class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  bool _isSigningOut = false;
  bool _isUploadingProfile = false;
  bool _isUploadingVehicle = false;

  // System & Monetization State
  bool _hapticFeedback = true;
  bool _dataSaver = false;
  int _jarvisLevel = 1; // 0 = Silencioso, 1 = Padrão, 2 = Agressivo
  final bool _isPremium = false; // Trava de monetização para recursos PRO

  Map<String, dynamic>? activeVehicle;

  @override
  void initState() {
    super.initState();
    _fetchVehicle();
    _loadJarvisMode();
  }

  Future<void> _loadJarvisMode() async {
    final mode = await JarvisAiService.loadJarvisMode();
    if (mounted) {
      setState(() {
        _jarvisLevel = mode;
      });
    }
  }

  void _triggerHaptic() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _fetchVehicle() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final vehicles = await VehicleService.loadVehicles();
      final data =
          VehicleService.activeVehicleNotifier.value ?? vehicles.firstOrNull;
      if (mounted) setState(() => activeVehicle = data);
    } catch (e) {
      debugPrint('--- ERRO AO BUSCAR VEÍCULO NA CONTA: $e ---');
    }
  }

  Future<void> _signOut() async {
    _triggerHaptic();
    setState(() => _isSigningOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao sair: ${error.toString()}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<ImageSource?> _showSourcePickerModal() async {
    _triggerHaptic();
    final accent = ThemeService.accentColor.value;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHandle(),
                const SizedBox(height: 16),
                const Text(
                  'ORIGEM DA FOTO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Icon(Icons.photo_library_rounded, color: accent),
                  title: const Text('Galeria de Fotos',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _triggerHaptic();
                    Navigator.pop(ctx, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt_rounded, color: accent),
                  title: const Text('Tirar Foto da Câmera',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _triggerHaptic();
                    Navigator.pop(ctx, ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    final source = await _showSourcePickerModal();
    if (source == null) return;
    final file = await StorageService.pickImage(source);
    if (file == null) return;
    setState(() => _isUploadingProfile = true);
    try {
      await StorageService.uploadProfilePhoto(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto de perfil atualizada com sucesso!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao enviar foto: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingProfile = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    setState(() => _isUploadingProfile = true);
    try {
      await StorageService.removeProfilePhoto();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto de perfil removida. Usando ícone padrão.'),
          backgroundColor: Colors.blueGrey,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao remover foto: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingProfile = false);
    }
  }

  Future<void> _pickAndUploadVehiclePhoto() async {
    if (activeVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Cadastre um veículo primeiro antes de adicionar uma foto.'),
        backgroundColor: Colors.amber,
      ));
      return;
    }
    final source = await _showSourcePickerModal();
    if (source == null) return;
    final file = await StorageService.pickImage(source);
    if (file == null) return;
    setState(() => _isUploadingVehicle = true);
    try {
      await StorageService.uploadVehiclePhoto(activeVehicle!['id'], file);
      await _fetchVehicle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto do veículo atualizada com sucesso!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao enviar foto do veículo: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingVehicle = false);
    }
  }

  Future<void> _removeVehiclePhoto() async {
    if (activeVehicle == null) return;
    setState(() => _isUploadingVehicle = true);
    try {
      await StorageService.removeVehiclePhoto(activeVehicle!['id']);
      await _fetchVehicle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto do veículo removida. Usando layout padrão.'),
          backgroundColor: Colors.blueGrey,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao remover foto do veículo: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingVehicle = false);
    }
  }

  void _showPhotoManagementModal({
    required String? avatarUrl,
    required String? vehiclePhotoUrl,
    required String? vehicleName,
  }) {
    _triggerHaptic();
    final accent = ThemeService.accentColor.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _sheetHandle()),
                const SizedBox(height: 20),
                const Text(
                  'GERENCIAR FOTOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Personalize o perfil e a vitrine do veículo',
                  style: TextStyle(color: Colors.grey, fontSize: 12.5),
                ),
                const SizedBox(height: 24),
                _photoTile(
                  ctx: ctx,
                  icon: Icons.person_rounded,
                  accent: accent,
                  title: 'Alterar Foto de Perfil',
                  subtitle: avatarUrl != null && avatarUrl.isNotEmpty
                      ? 'Foto personalizada ativa'
                      : 'Utilizando avatar padrão',
                  hasPhoto: avatarUrl != null && avatarUrl.isNotEmpty,
                  onAdd: () {
                    _triggerHaptic();
                    Navigator.pop(ctx);
                    _pickAndUploadProfilePhoto();
                  },
                  onRemove: () {
                    _triggerHaptic();
                    Navigator.pop(ctx);
                    _removeProfilePhoto();
                  },
                ),
                const Divider(color: Colors.white10, height: 24),
                _photoTile(
                  ctx: ctx,
                  icon: Icons.directions_car_filled_rounded,
                  accent: accent,
                  title: vehicleName != null
                      ? 'Foto do $vehicleName'
                      : 'Foto do Veículo (Vitrine)',
                  subtitle: vehiclePhotoUrl != null && vehiclePhotoUrl.isNotEmpty
                      ? 'Foto na vitrine ativa'
                      : 'Sem foto cadastrada',
                  hasPhoto:
                      vehiclePhotoUrl != null && vehiclePhotoUrl.isNotEmpty,
                  onAdd: () {
                    _triggerHaptic();
                    Navigator.pop(ctx);
                    _pickAndUploadVehiclePhoto();
                  },
                  onRemove: () {
                    _triggerHaptic();
                    Navigator.pop(ctx);
                    _removeVehiclePhoto();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditCallsignModal(String currentName) {
    _triggerHaptic();
    final controller = TextEditingController(text: currentName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _sheetHandle()),
              const SizedBox(height: 20),
              const Text(
                'EDITAR CALLSIGN',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Nome de identificação impresso na placa do piloto',
                style: TextStyle(color: Colors.grey, fontSize: 12.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
                decoration: const InputDecoration(
                  labelText: 'Callsign / Nome do Piloto',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    _triggerHaptic();
                    final newName = controller.text.trim().toUpperCase();
                    if (newName.isEmpty) return;
                    final nav = Navigator.of(sheetCtx);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      // =========================================================================
                      // REQUISITO DE BACKEND (SUPABASE):
                      // Validar se este Callsign é UNIQUE na tabela de perfis do Supabase 
                      // antes de persistir a alteração, garantindo unicidade na rede social.
                      // Exemplo de consulta:
                      // final existing = await Supabase.instance.client
                      //     .from('profiles')
                      //     .select('id')
                      //     .eq('callsign', newName)
                      //     .maybeSingle();
                      // if (existing != null && existing['id'] != userId) {
                      //   throw Exception('Este Callsign já está em uso por outro piloto.');
                      // }
                      // =========================================================================

                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(data: {'full_name': newName}),
                      );
                      nav.pop();
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Callsign atualizado com sucesso!'),
                        backgroundColor: Colors.green,
                      ));
                      if (mounted) setState(() {});
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(
                        content: Text('Erro: $e'),
                        backgroundColor: Colors.redAccent,
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeService.accentColor.value,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  child: const Text('SALVAR CALLSIGN'),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    });
  }

  // ─── HELPERS ───────────────────────────────

  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _photoTile({
    required BuildContext ctx,
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required bool hasPhoto,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accent),
      ),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.add_a_photo_outlined, color: accent),
            onPressed: onAdd,
            tooltip: 'Alterar foto',
          ),
          if (hasPhoto)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              onPressed: onRemove,
              tooltip: 'Remover foto',
            ),
        ],
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Não informado';
    final name =
        user?.userMetadata?['full_name'] as String? ?? 'PILOTO';
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final vehiclePhotoUrl =
        activeVehicle?['veiculo_foto_url'] as String?;
    final vehicleName = activeVehicle != null
        ? '${activeVehicle!['brand']} ${activeVehicle!['model']}'
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'MINHA CONTA',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // ── HEADER: PLACA DE VEÍCULO REAL ───────────
              _PilotLicensePlateHeader(
                name: name,
                email: email,
                avatarUrl: avatarUrl,
                isUploading: _isUploadingProfile || _isUploadingVehicle,
                onEditCallsign: () => _showEditCallsignModal(name),
                onManagePhotos: () => _showPhotoManagementModal(
                  avatarUrl: avatarUrl,
                  vehiclePhotoUrl: vehiclePhotoUrl,
                  vehicleName: vehicleName,
                ),
              ),
              const SizedBox(height: 32),

              // ── SECTION: PERSONALIZAÇÃO ────────────────
              const _SectionHeader(label: 'PERSONALIZAÇÃO'),
              const SizedBox(height: 12),

              _ThemeColorCard(onColorSelected: _triggerHaptic),
              const SizedBox(height: 32),

              // ── SECTION: GARAGEM & VEÍCULOS ────────────
              const _SectionHeader(label: 'GARAGEM & VEÍCULOS'),
              const SizedBox(height: 12),

              _ConfigCard(
                icon: Icons.garage_rounded,
                title: 'Minha Garagem',
                subtitle: 'Gerenciar, editar e trocar veículos ativos',
                onTap: () {
                  _triggerHaptic();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VehicleInfoView(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              _ConfigCard(
                icon: Icons.build_circle_outlined,
                title: 'Manutenções Preventivas',
                subtitle: 'Revisões, prazos e controle por km',
                onTap: () {
                  _triggerHaptic();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VehicleMaintenancesView(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // ── SECTION: JARVIS / IA ───────────────────
              const _SectionHeader(label: 'JARVIS / IA'),
              const SizedBox(height: 12),

              _JarvisPreferenceCard(
                level: _jarvisLevel,
                isPremium: _isPremium,
                onChanged: (v) async {
                  _triggerHaptic();
                  setState(() => _jarvisLevel = v);
                  await JarvisAiService.setJarvisMode(v);
                },
                onLockedSelected: () {
                  _triggerHaptic();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Modo Agressivo disponível apenas para assinantes PRO.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Color(0xFF1E1F28),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              _ConfigCard(
                icon: Icons.notifications_active_outlined,
                title: 'Preferências de Alertas',
                subtitle: 'Avisos mecânicos, financeiros e prazos',
                onTap: () {
                  _triggerHaptic();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AlertPreferencesView(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // ── SECTION: SISTEMA ───────────────────────
              const _SectionHeader(label: 'SISTEMA'),
              const SizedBox(height: 12),

              _ToggleCard(
                icon: Icons.vibration_rounded,
                title: 'Feedback Tátil',
                subtitle: 'Vibração em ações e confirmações',
                value: _hapticFeedback,
                onChanged: (v) {
                  setState(() => _hapticFeedback = v);
                  if (v) HapticFeedback.lightImpact();
                },
              ),
              const SizedBox(height: 12),

              _ToggleCard(
                icon: Icons.data_saver_on_rounded,
                title: 'Modo Economia de Dados',
                subtitle: 'Reduz sincronizações em redes móveis',
                value: _dataSaver,
                onChanged: (v) {
                  _triggerHaptic();
                  setState(() => _dataSaver = v);
                },
              ),
              const SizedBox(height: 32),

              // ── DANGER ZONE ────────────────────────────
              _DangerZone(
                isSigningOut: _isSigningOut,
                onSignOut: _signOut,
              ),
              const SizedBox(height: 24),

              // ── SYSTEM FOOTER ──────────────────────────
              const _SystemFooter(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// COMPONENT: _PilotLicensePlateHeader — Placa de Veículo Real
// ═══════════════════════════════════════════════════════

class _PilotLicensePlateHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? avatarUrl;
  final bool isUploading;
  final VoidCallback onEditCallsign;
  final VoidCallback onManagePhotos;

  const _PilotLicensePlateHeader({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.isUploading,
    required this.onEditCallsign,
    required this.onManagePhotos,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.accentColor.value;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // ── TARJA SUPERIOR DA PLACA (Estilo Mercosul Dark/Neon) ──
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: accent.withValues(alpha: 0.35), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'BRASIL',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                Text(
                  'PILOT LICENSE // OFFICIAL',
                  style: TextStyle(
                    color: accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // ── CORPO DA PLACA (Estamparia do Callsign + Parafusos) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                // Parafusos decorativos + Botão de edição
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _screwHead(),
                    Text(
                      '// CALLSIGN REGISTRADO',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    GestureDetector(
                      onTap: onEditCallsign,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // TEXTO PRINCIPAL CENTRALIZADO DA PLACA (Estamparia em Caixa Alta Bold)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Text(
                    name.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.5,
                      shadows: [
                        Shadow(
                          color: accent.withValues(alpha: 0.8),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── RODAPÉ DA PLACA: Avatar + Email do Piloto ──
                Row(
                  children: [
                    GestureDetector(
                      onTap: onManagePhotos,
                      child: Stack(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E2028),
                              border: Border.all(color: accent, width: 1.5),
                            ),
                            child: isUploading
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  )
                                : ClipOval(
                                    child: avatarUrl != null && avatarUrl!.isNotEmpty
                                        ? Image.network(
                                            avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx2, e, st) => Icon(
                                              Icons.person_rounded,
                                              size: 26,
                                              color: accent,
                                            ),
                                          )
                                        : Icon(Icons.person_rounded, size: 26, color: accent),
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 15,
                              height: 15,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF0F1015), width: 1.5),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, size: 8, color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.verified_user_rounded, size: 12, color: accent),
                              const SizedBox(width: 4),
                              Text(
                                'PILOTO VERIFICADO',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _screwHead(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _screwHead() {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2A2C36),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 1,
          color: Colors.white54,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _SectionHeader
// ═══════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: ThemeService.accentColor.value,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _ConfigCard
// ═══════════════════════════════════════════════

class _ConfigCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ConfigCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.accentColor.value;
    return Material(
      color: const Color(0xFF111318),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[600], size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _ToggleCard
// ═══════════════════════════════════════════════

class _ToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.accentColor.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111318),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (value ? accent : Colors.grey).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: value ? accent : Colors.grey[600], size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
            inactiveThumbColor: Colors.grey[700],
            inactiveTrackColor: Colors.white10,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _ThemeColorCard
// ═══════════════════════════════════════════════

class _ThemeColorCard extends StatelessWidget {
  final VoidCallback onColorSelected;

  const _ThemeColorCard({required this.onColorSelected});

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.accentColor.value;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111318),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.palette_outlined, color: accent, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cor de Destaque do App',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tema de acentos da interface',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<Color>(
            valueListenable: ThemeService.accentColor,
            builder: (_, activeColor, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ThemeService.availableThemes.map((option) {
                  final isSelected =
                      activeColor.toARGB32() == option.color.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      onColorSelected();
                      ThemeService.setAccentColor(option.color);
                    },
                    child: Tooltip(
                      message: option.name,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: isSelected ? 44 : 34,
                        height: isSelected ? 44 : 34,
                        decoration: BoxDecoration(
                          color: option.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: isSelected ? 3 : 0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: option.color.withValues(
                                  alpha: isSelected ? 0.6 : 0.15),
                              blurRadius: isSelected ? 14 : 4,
                              spreadRadius: isSelected ? 2 : 0,
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded,
                                color: Colors.black, size: 20)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _JarvisPreferenceCard (com Trava PRO)
// ═══════════════════════════════════════════════

class _JarvisPreferenceCard extends StatelessWidget {
  final int level;
  final bool isPremium;
  final ValueChanged<int> onChanged;
  final VoidCallback onLockedSelected;

  const _JarvisPreferenceCard({
    required this.level,
    required this.isPremium,
    required this.onChanged,
    required this.onLockedSelected,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ThemeService.accentColor.value;

    const levels = [
      _JarvisLevel(
        label: 'SILENCIOSO',
        sublabel: 'Apenas alertas\ncríticos',
        icon: Icons.do_not_disturb_on_total_silence_rounded,
        isProOnly: false,
      ),
      _JarvisLevel(
        label: 'PADRÃO',
        sublabel: 'Recomendações\nbalanceadas',
        icon: Icons.tune_rounded,
        isProOnly: false,
      ),
      _JarvisLevel(
        label: 'AGRESSIVO',
        sublabel: 'Análise contínua\nem tempo real',
        icon: Icons.whatshot_rounded,
        isProOnly: true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111318),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.psychology_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo Copiloto Jarvis',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Frequência e agressividade da IA',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(3, (i) {
              final isSelected = level == i;
              final lvl = levels[i];
              final isLocked = lvl.isProOnly && !isPremium;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  child: GestureDetector(
                    onTap: () {
                      if (isLocked) {
                        onLockedSelected();
                      } else {
                        onChanged(i);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.15)
                            : (isLocked
                                ? Colors.white.withValues(alpha: 0.02)
                                : Colors.white.withValues(alpha: 0.04)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? accent.withValues(alpha: 0.5)
                              : (isLocked
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.08)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            children: [
                              Icon(
                                lvl.icon,
                                color: isSelected
                                    ? accent
                                    : (isLocked
                                        ? Colors.grey[700]
                                        : Colors.grey[600]),
                                size: 22,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    lvl.label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isSelected
                                          ? accent
                                          : (isLocked
                                              ? Colors.grey[600]
                                              : Colors.grey[500]),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (isLocked) ...[
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Icons.lock_rounded,
                                      size: 10,
                                      color: Colors.amber,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                lvl.sublabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isLocked
                                      ? Colors.grey[800]
                                      : Colors.grey[700],
                                  fontSize: 8.5,
                                ),
                              ),
                            ],
                          ),
                          if (isLocked)
                            Positioned(
                              top: -6,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.amber.withValues(alpha: 0.4),
                                      width: 0.8),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 7,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _JarvisLevel {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isProOnly;

  const _JarvisLevel({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.isProOnly,
  });
}

// ═══════════════════════════════════════════════
// COMPONENT: _DangerZone
// ═══════════════════════════════════════════════

class _DangerZone extends StatelessWidget {
  final bool isSigningOut;
  final VoidCallback onSignOut;

  const _DangerZone({required this.isSigningOut, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 16),
              SizedBox(width: 8),
              Text(
                'ZONA DE RISCO',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isSigningOut ? null : onSignOut,
              icon: isSigningOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.redAccent,
                      ),
                    )
                  : const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 18),
              label: Text(
                isSigningOut ? 'SAINDO...' : 'SAIR DA CONTA',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.4,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// COMPONENT: _SystemFooter — Terminal-style info
// ═══════════════════════════════════════════════

class _SystemFooter extends StatelessWidget {
  const _SystemFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 14),
        Text(
          'SYS_VERSION: 1.2.0  //  BUILD 2026',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'NUCLEUS: JARVIS ONLINE  //  STATUS: ■ ATIVO',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[800],
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
