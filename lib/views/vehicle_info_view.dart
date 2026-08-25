import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/services/storage_service.dart';
import 'package:projectapp/services/theme_service.dart';
import 'package:projectapp/services/vehicle_service.dart';
import 'package:projectapp/views/account_view.dart';
import 'package:projectapp/views/add_refuel_view.dart';
import 'package:projectapp/views/refuel_history_view.dart';

class VehicleInfoView extends StatefulWidget {
  const VehicleInfoView({super.key});

  @override
  State<VehicleInfoView> createState() => _VehicleInfoViewState();
}

class _VehicleInfoViewState extends State<VehicleInfoView> {
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _yearController = TextEditingController();
  final _odometerController = TextEditingController();

  Map<String, dynamic>? currentVehicle;
  List<Map<String, dynamic>> userVehicles = [];
  int _userStreakDays = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    VehicleService.activeVehicleNotifier.addListener(_onActiveVehicleChanged);
    VehicleService.userVehiclesNotifier.addListener(_onUserVehiclesChanged);
    fetchVehicles();
  }

  @override
  void dispose() {
    VehicleService.activeVehicleNotifier.removeListener(_onActiveVehicleChanged);
    VehicleService.userVehiclesNotifier.removeListener(_onUserVehiclesChanged);
    _brandController.dispose();
    _modelController.dispose();
    _nicknameController.dispose();
    _yearController.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  void _onActiveVehicleChanged() {
    if (mounted) {
      setState(() {
        currentVehicle = VehicleService.activeVehicleNotifier.value;
      });
      _fetchStreakData();
    }
  }

  void _onUserVehiclesChanged() {
    if (mounted) {
      setState(() {
        userVehicles = VehicleService.userVehiclesNotifier.value;
      });
    }
  }

  Future<void> fetchVehicles() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final list = await VehicleService.loadVehicles();
      if (mounted) {
        setState(() {
          userVehicles = list;
          currentVehicle = VehicleService.activeVehicleNotifier.value;
          _isLoading = false;
        });
      }
      await _fetchStreakData();
    } catch (error) {
      debugPrint('--- ERRO AO BUSCAR GARAGEM DE VEÍCULOS: $error ---');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchStreakData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final refuelsCount = await Supabase.instance.client
          .from('refuels')
          .select()
          .eq('user_id', user.id);

      final streak = (refuelsCount as List).length;

      if (mounted) {
        setState(() {
          _userStreakDays = streak;
        });
      }
    } catch (e) {
      debugPrint('--- ERRO STREAK: $e ---');
    }
  }

  Future<void> _pickAndUploadVehiclePhoto(dynamic vehicleId) async {
    try {
      final file = await StorageService.pickImage(ImageSource.gallery);
      if (file == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Enviando foto do veículo...'),
              ],
            ),
            backgroundColor: Color(0xFF1E2028),
          ),
        );
      }

      final url = await StorageService.uploadVehiclePhoto(vehicleId, file);
      if (url != null) {
        await fetchVehicles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto do veículo atualizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('--- ERRO UPLOAD FOTO VEÍCULO: $e ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar foto: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _clearControllers() {
    _brandController.clear();
    _modelController.clear();
    _nicknameController.clear();
    _yearController.clear();
    _odometerController.clear();
  }

  Future<void> _saveVehicle(
      BuildContext modalContext, StateSetter setModalState) async {
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final nickname = _nicknameController.text.trim();
    final yearText = _yearController.text.trim();
    final kmText = _odometerController.text.trim();

    if (brand.isEmpty || model.isEmpty || yearText.isEmpty || kmText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, preencha a marca, modelo, ano e quilometragem.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setModalState(() {
      _isSubmitting = true;
    });

    try {
      final cleanYear = yearText.replaceAll(RegExp(r'[^0-9]'), '');
      final cleanKm = kmText.replaceAll(RegExp(r'[^0-9]'), '');
      final mileage = int.tryParse(cleanKm) ?? 0;

      await VehicleService.addVehicle(
        brand: brand,
        model: model,
        year: cleanYear,
        mileage: mileage,
        drivetrain: 'FWD',
        nickname: nickname,
      );

      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }

      _clearControllers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veículo adicionado à sua garagem com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await fetchVehicles();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar veículo: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (modalContext.mounted) {
        setModalState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showAddVehicleBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
                top: 16,
                left: 24,
                right: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'NOVO VEÍCULO DA GARAGEM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cadastre outro carro para alternar contexto e telemetria',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _brandController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Marca (ex: BMW ou Volkswagen)',
                        prefixIcon: Icon(Icons.branding_watermark_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _modelController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Modelo (ex: 320i ou Gol)',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Ano (ex: 2000 ou 2021)',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _odometerController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Quilometragem Atual (km)',
                        prefixIcon: Icon(Icons.speed_outlined),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ValueListenableBuilder<Color>(
                      valueListenable: ThemeService.accentColor,
                      builder: (_, activeAccent, _) {
                        return SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _saveVehicle(
                                    modalContext, setModalState),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: activeAccent,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor:
                                  activeAccent.withValues(alpha: 0.5),
                              elevation: 0,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_rounded,
                                          color: Colors.black),
                                      SizedBox(width: 8),
                                      Text('ADICIONAR À GARAGEM'),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditVehicleModal(BuildContext context, Color activeAccent) {
    if (currentVehicle == null) return;

    final currentDescription =
        currentVehicle?['description'] as String? ?? 'Uso diário & alta performance';
    final currentMileage = (currentVehicle?['mileage'] as num?)?.toInt() ?? 0;
    final currentBrand = currentVehicle?['brand'] as String? ?? '';
    final currentModel = currentVehicle?['model'] as String? ?? '';
    final currentYear = currentVehicle?['year']?.toString() ?? '';
    final currentNickname = currentVehicle?['nickname'] as String? ?? '';

    final descController = TextEditingController(text: currentDescription);
    final kmController = TextEditingController(
        text: currentMileage > 0 ? currentMileage.toString() : '');
    final brandController = TextEditingController(text: currentBrand);
    final modelController = TextEditingController(text: currentModel);
    final yearController = TextEditingController(text: currentYear);
    final nicknameController = TextEditingController(text: currentNickname);

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'EDITAR DADOS DO VEÍCULO',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Atualize a foto, apelido, ano, modelo e odômetro do carro',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),

                    // 1. AÇÃO DE UPLOAD/ALTERAÇÃO DE FOTO NO MODAL
                    InkWell(
                      onTap: () async {
                        final vehicleId = currentVehicle!['id'];
                        await _pickAndUploadVehiclePhoto(vehicleId);
                        setModalState(() {});
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1D26),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: activeAccent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.camera_alt_rounded,
                                color: activeAccent, size: 22),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ALTERAR FOTO DO VEÍCULO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Toque para escolher uma imagem da galeria',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.grey[600], size: 14),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 2. APELIDO DO VEÍCULO
                    TextField(
                      controller: nicknameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Apelido do Veículo (ex: Goleta, Alemão)',
                        hintText: 'ex: Goleta ou Projeto Pista',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. MARCA E MODELO
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: brandController,
                            style: const TextStyle(color: Colors.white),
                            decoration:
                                const InputDecoration(labelText: 'Marca'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: modelController,
                            style: const TextStyle(color: Colors.white),
                            decoration:
                                const InputDecoration(labelText: 'Modelo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. ANO E QUILOMETRAGEM (KM)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: yearController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Ano (ex: 2021)',
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: kmController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Quilometragem (KM)',
                              prefixIcon: Icon(Icons.speed_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 5. DESCRIÇÃO DO CARRO
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Descrição / Biografia do Carro',
                        hintText: 'ex: Uso diário, Projeto de pista',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setModalState(() => isSaving = true);
                                final newDesc = descController.text.trim();
                                final newKm =
                                    int.tryParse(kmController.text.trim()) ??
                                        currentMileage;
                                final newBrand = brandController.text.trim();
                                final newModel = modelController.text.trim();
                                final newYear = yearController.text.trim();
                                final newNickname =
                                    nicknameController.text.trim();

                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(sheetContext);

                                try {
                                  await VehicleService.updateVehicle(
                                    vehicleId: currentVehicle!['id'].toString(),
                                    updates: {
                                      'nickname': newNickname,
                                      'year': newYear,
                                      'description': newDesc.isEmpty
                                          ? 'Projeto de telemetria'
                                          : newDesc,
                                      'mileage': newKm,
                                      if (newBrand.isNotEmpty) 'brand': newBrand,
                                      if (newModel.isNotEmpty) 'model': newModel,
                                    },
                                  );

                                  await fetchVehicles();

                                  nav.pop();

                                  if (mounted) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Dados do veículo atualizados!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  debugPrint(
                                      '--- ERRO AO EDITAR VEÍCULO: $err ---');
                                  if (modalCtx.mounted) {
                                    setModalState(() => isSaving = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeAccent,
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text('SALVAR ALTERAÇÕES'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () => _confirmDeleteVehicle(sheetContext, currentVehicle!),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 18),
                        label: const Text(
                          'EXCLUIR VEÍCULO',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.0,
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
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        descController.dispose();
        kmController.dispose();
        brandController.dispose();
        modelController.dispose();
        yearController.dispose();
        nicknameController.dispose();
      });
    });
  }

  void _confirmDeleteVehicle(BuildContext sheetContext, Map<String, dynamic> vehicle) {
    final vehicleId = vehicle['id']?.toString();
    if (vehicleId == null) return;

    final brand = vehicle['brand'] as String? ?? 'Veículo';
    final model = vehicle['model'] as String? ?? '';

    final messenger = ScaffoldMessenger.of(context);
    final navSheet = Navigator.of(sheetContext);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final navDialog = Navigator.of(dialogCtx);
        return AlertDialog(
          backgroundColor: const Color(0xFF14161C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.redAccent, width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 10),
              Text(
                'EXCLUIR VEÍCULO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          content: Text(
            'Tem certeza que deseja excluir o veículo "$brand $model"? Todos os abastecimentos e manutenções vinculados serão permanentemente removidos.',
            style: const TextStyle(color: Colors.grey, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => navDialog.pop(),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () async {
                navDialog.pop();
                navSheet.pop();

                try {
                  await VehicleService.deleteVehicle(vehicleId);
                  await JarvisAiService.clearCache();
                  await fetchVehicles();
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Veículo excluído com sucesso.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Erro ao excluir veículo: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              child: const Text('EXCLUIR', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
  }

  void _showQrCodeShareModal(
      BuildContext context, String userId, Color activeAccent) {
    final shareUrl = 'https://seuapp.com/u/$userId';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121316),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'CARTÃO DE VISITA DIGITAL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escaneie ou compartilhe seu perfil de motorista',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: activeAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: activeAccent.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _buildFirst2NeonQrCode(activeAccent, scaleFactor: 1.5),
                ),
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1D24),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded,
                          color: Colors.grey, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          shareUrl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareUrl));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.white),
                              SizedBox(width: 10),
                              Text('Link de perfil copiado para a área de transferência!'),
                            ],
                          ),
                          backgroundColor: Colors.green[700],
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded,
                        color: Colors.black, size: 20),
                    label: const Text(
                      'COPIAR LINK DE PERFIL',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: activeAccent,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatInteger(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  Widget _buildMultiVehicleCarousel(
      List<Map<String, dynamic>> vehicles, Map<String, dynamic>? active, Color activeAccent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.garage_rounded, color: activeAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'SUA GARAGEM (${vehicles.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: vehicles.length + 1,
            itemBuilder: (context, index) {
              if (index == vehicles.length) {
                return GestureDetector(
                  onTap: () => _showAddVehicleBottomSheet(context),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1014),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            color: activeAccent, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          '+ ADICIONAR',
                          style: TextStyle(
                            color: activeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final v = vehicles[index];
              final isSelected = active != null &&
                  v['id'].toString() == active['id'].toString();
              final nick = v['nickname'] as String?;
              final title = (nick != null && nick.trim().isNotEmpty)
                  ? '${v['brand']} ${v['model']} (${nick.trim()})'
                  : '${v['brand']} ${v['model']}';
              final mileage = (v['mileage'] as num?)?.toInt() ?? 0;

              return GestureDetector(
                onTap: () {
                  VehicleService.setActiveVehicle(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 175,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1B1D26)
                        : const Color(0xFF0F1014),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? activeAccent
                          : Colors.white.withValues(alpha: 0.08),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: activeAccent.withValues(alpha: 0.2),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? activeAccent
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isSelected ? 'ATIVO NO APP' : '${v['year'] ?? ''}',
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF121316)
                                    : Colors.grey[400],
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.directions_car_rounded,
                            size: 16,
                            color: isSelected ? activeAccent : Colors.grey,
                          ),
                        ],
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${_formatInteger(mileage)} km',
                        style: TextStyle(
                          color: isSelected ? activeAccent : Colors.grey[400],
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateCard(Color activeAccent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
      decoration: BoxDecoration(
        color: const Color(0xFF090A0D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF1F2128),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activeAccent.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                  color: activeAccent.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.garage_rounded,
              size: 56,
              color: activeAccent,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'SUA GARAGEM ESTÁ VAZIA',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Cadastre seu primeiro veículo para desbloquear a garagem e a telemetria preditiva do Jarvis.',
            style: TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddVehicleBottomSheet(context),
              icon: const Icon(Icons.add_rounded, color: Color(0xFF090A0D)),
              label: const Text(
                'CADASTRAR VEÍCULO',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: activeAccent,
                foregroundColor: const Color(0xFF090A0D),
                elevation: 0,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetailsView(
      Map<String, dynamic> vehicle, Color activeAccent) {
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    final fullName = user?.userMetadata?['full_name'] as String?;
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final pilotName = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName.trim().split(' ').first.toUpperCase()
        : (user?.email != null ? user!.email!.split('@').first.toUpperCase() : 'PILOTO');

    final brand = (vehicle['brand'] as String? ?? 'VEÍCULO').toUpperCase();
    final model = (vehicle['model'] as String? ?? 'MODELO').toUpperCase();
    final nickname = vehicle['nickname'] as String?;
    final year = vehicle['year']?.toString() ?? '2021';
    final rawMileage = (vehicle['mileage'] as num?)?.toInt() ?? 0;
    final description = vehicle['description'] as String? ?? 'Uso diário & telemetria ativa';
    final drivetrain = vehicle['drivetrain'] as String?; // ex: FWD, RWD, AWD, 4x4
    final photoUrl = vehicle['veiculo_foto_url'] as String?;
    final bool hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Carrossel de seleção multi-veículos da garagem
        if (userVehicles.isNotEmpty) ...[
          _buildMultiVehicleCarousel(userVehicles, vehicle, activeAccent),
          const SizedBox(height: 24),
        ],

        // 1. TOPO: ANO & ODÔMETRO, MARCA, MODELO, APELIDO EM DESTAQUE & BADGE DE TRAÇÃO
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rawMileage > 0 ? '$year • ${_formatInteger(rawMileage)} KM' : year,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8E8E93),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    brand,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    model,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: activeAccent,
                      letterSpacing: -0.5,
                      height: 1.05,
                    ),
                  ),
                  if (nickname != null && nickname.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '// CALLSIGN:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF71717A),
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          nickname.trim().toUpperCase(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2.8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (drivetrain != null && drivetrain.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1D22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      drivetrain.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. VITRINE AUTOMOTIVA PADRONIZADA COM ÁREA DE FOTO LIMPA
        SizedBox(
          height: 280,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GarageSlatsPainter(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.1),
                      radius: 0.85,
                      colors: [
                        activeAccent.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: hasPhoto
                        ? Image.network(
                            photoUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildShowcaseFallback(activeAccent),
                          )
                        : _buildShowcaseFallback(activeAccent),
                  ),
                ),
              ),

              // QR Code Interativo no Canto Inferior Direito
              Positioned(
                bottom: 12,
                right: 0,
                child: GestureDetector(
                  onTap: () =>
                      _showQrCodeShareModal(context, userId, activeAccent),
                  child: Tooltip(
                    message: 'Toque para abrir e compartilhar QR Code de Perfil',
                    child: _buildFirst2NeonQrCode(activeAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. SEÇÃO DO PILOTO E STREAK
        Row(
          children: [
            if (avatarUrl != null && avatarUrl.isNotEmpty)
              CircleAvatar(
                radius: 15,
                backgroundImage: NetworkImage(avatarUrl),
              )
            else
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFF1F2128),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            const SizedBox(width: 10),
            Text(
              pilotName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF14161D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(
                    'Sequência: $_userStreakDays ${_userStreakDays == 1 ? "dia" : "dias"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // DESCRIÇÃO DO VEÍCULO
        const Text(
          'DESCRIÇÃO DO VEÍCULO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8E8E93),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),

        // 4. AÇÕES DE GERENCIAMENTO (EDITAR, PERSONALIZAR)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            InkWell(
              onTap: () => _showEditVehicleModal(context, activeAccent),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: activeAccent, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EDITAR',
                      style: TextStyle(
                        color: activeAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: activeAccent,
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountView(),
                  ),
                ).then((_) => fetchVehicles());
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PERSONALIZAR',
                      style: TextStyle(
                        color: activeAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.palette_outlined,
                      size: 15,
                      color: activeAccent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        const SizedBox(height: 20),

        // ABASTECER E HISTÓRICO
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showAddRefuelBottomSheet(
                      context,
                      vehicle: currentVehicle,
                      onRefuelSaved: fetchVehicles,
                    );
                  },
                  icon: const Icon(
                    Icons.local_gas_station_rounded,
                    color: Color(0xFF090A0D),
                    size: 18,
                  ),
                  label: const Text(
                    'ABASTECER',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeAccent,
                    foregroundColor: const Color(0xFF090A0D),
                    elevation: 0,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RefuelHistoryView(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.assignment_outlined,
                    color: Colors.grey,
                    size: 18,
                  ),
                  label: const Text(
                    'HISTÓRICO DE SERVIÇOS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF14161C),
                    side: const BorderSide(color: Color(0xFF27272A), width: 1.0),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildShowcaseFallback(Color activeAccent) {
    return Center(
      child: Icon(
        Icons.directions_car_filled_rounded,
        size: 80,
        color: activeAccent.withValues(alpha: 0.45),
      ),
    );
  }

  Widget _buildFirst2NeonQrCode(Color activeAccent, {double scaleFactor = 1.0}) {
    return Container(
      width: 58 * scaleFactor,
      height: 58 * scaleFactor,
      padding: EdgeInsets.all(4 * scaleFactor),
      decoration: BoxDecoration(
        color: activeAccent,
        borderRadius: BorderRadius.circular(4 * scaleFactor),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 2 * scaleFactor,
            left: 2 * scaleFactor,
            child: Container(
                width: 14 * scaleFactor,
                height: 14 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            top: 2 * scaleFactor,
            right: 2 * scaleFactor,
            child: Container(
                width: 14 * scaleFactor,
                height: 14 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            bottom: 2 * scaleFactor,
            left: 2 * scaleFactor,
            child: Container(
                width: 14 * scaleFactor,
                height: 14 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            top: 4 * scaleFactor,
            left: 4 * scaleFactor,
            child: Container(
                width: 10 * scaleFactor,
                height: 10 * scaleFactor,
                color: activeAccent),
          ),
          Positioned(
            top: 4 * scaleFactor,
            right: 4 * scaleFactor,
            child: Container(
                width: 10 * scaleFactor,
                height: 10 * scaleFactor,
                color: activeAccent),
          ),
          Positioned(
            bottom: 4 * scaleFactor,
            left: 4 * scaleFactor,
            child: Container(
                width: 10 * scaleFactor,
                height: 10 * scaleFactor,
                color: activeAccent),
          ),
          Positioned(
            top: 6 * scaleFactor,
            left: 6 * scaleFactor,
            child: Container(
                width: 6 * scaleFactor,
                height: 6 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            top: 6 * scaleFactor,
            right: 6 * scaleFactor,
            child: Container(
                width: 6 * scaleFactor,
                height: 6 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            bottom: 6 * scaleFactor,
            left: 6 * scaleFactor,
            child: Container(
                width: 6 * scaleFactor,
                height: 6 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            bottom: 6 * scaleFactor,
            right: 6 * scaleFactor,
            child: Container(
                width: 12 * scaleFactor,
                height: 12 * scaleFactor,
                color: Colors.black),
          ),
          Positioned(
            top: 20 * scaleFactor,
            left: 20 * scaleFactor,
            child: Container(
                width: 10 * scaleFactor,
                height: 10 * scaleFactor,
                color: Colors.black),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (_, activeAccent, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF000000),
          appBar: AppBar(
            title: const Text(
              'GARAGEM DE VEÍCULOS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF000000),
            elevation: 0,
            centerTitle: true,
          ),
          body: SafeArea(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: activeAccent,
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: currentVehicle == null
                        ? _buildEmptyStateCard(activeAccent)
                        : _buildVehicleDetailsView(
                            currentVehicle!, activeAccent),
                  ),
          ),
        );
      },
    );
  }
}

class GarageSlatsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    const double step = 14.0;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
