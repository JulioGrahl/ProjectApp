import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/services/vehicle_service.dart';

class FactoryMaintenanceSuggestion {
  final String title;
  final int defaultIntervalKm;
  final String explanation;
  final String intervalText;
  final IconData icon;

  const FactoryMaintenanceSuggestion({
    required this.title,
    required this.defaultIntervalKm,
    required this.explanation,
    required this.intervalText,
    required this.icon,
  });
}

class VehicleMaintenancesView extends StatefulWidget {
  const VehicleMaintenancesView({super.key});

  @override
  State<VehicleMaintenancesView> createState() => _VehicleMaintenancesViewState();
}

class _VehicleMaintenancesViewState extends State<VehicleMaintenancesView> {
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _dataFuture = _fetchMaintenancesAndVehicle();
    });
  }

  /// Busca o veículo principal, as manutenções cadastradas e a margem de antecedência do usuário
  Future<Map<String, dynamic>> _fetchMaintenancesAndVehicle() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return {
        'vehicle': null,
        'maintenances': <Map<String, dynamic>>[],
        'thresholdKm': 1000,
      };
    }

    try {
      // 1. Busca veículo principal ou ativo do usuário
      final vehicleData = VehicleService.activeVehicleNotifier.value ??
          (await VehicleService.loadVehicles()).firstOrNull;

      final vehicleId = vehicleData?['id']?.toString();
      if (vehicleId == null || vehicleId.isEmpty) {
        return {
          'vehicle': null,
          'maintenances': <Map<String, dynamic>>[],
          'thresholdKm': 1000,
        };
      }

      // 2. Busca preferências de alerta para saber a margem de antecedência (default: 1000 km)
      final alertPrefs = await Supabase.instance.client
          .from('user_alert_preferences')
          .select('mileage_threshold_km')
          .eq('user_id', userId)
          .maybeSingle();

      final thresholdKm =
          (alertPrefs?['mileage_threshold_km'] as num?)?.toInt() ?? 1000;

      // 3. Busca manutenções cadastradas ESTRITAMENTE para este veículo
      final maintenancesData = await Supabase.instance.client
          .from('vehicle_maintenances')
          .select()
          .eq('user_id', userId)
          .eq('vehicle_id', vehicleId)
          .order('target_mileage', ascending: true);

      return {
        'vehicle': vehicleData,
        'maintenances': List<Map<String, dynamic>>.from(maintenancesData),
        'thresholdKm': thresholdKm,
      };
    } catch (error) {
      debugPrint('--- ERRO AO CARREGAR MANUTENÇÕES: $error ---');
      rethrow;
    }
  }

  /// Exclui uma manutenção do banco de dados
  Future<void> _deleteMaintenance(String id) async {
    try {
      await Supabase.instance.client
          .from('vehicle_maintenances')
          .delete()
          .eq('id', id);

      JarvisAiService.clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Manutenção removida com sucesso.'),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _refreshData();
      }
    } catch (error) {
      debugPrint('--- ERRO AO EXCLUIR MANUTENÇÃO: $error ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Alterna o status de concluído de uma manutenção
  Future<void> _toggleCompleteMaintenance(
    String id,
    bool currentCompletedStatus,
  ) async {
    final newStatus = !currentCompletedStatus;
    try {
      await Supabase.instance.client
          .from('vehicle_maintenances')
          .update({'is_completed': newStatus}).eq('id', id);

      JarvisAiService.clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newStatus
                      ? Icons.check_circle_rounded
                      : Icons.restart_alt_rounded,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Text(
                  newStatus
                      ? 'Manutenção marcada como concluída!'
                      : 'Manutenção reaberta!',
                ),
              ],
            ),
            backgroundColor: newStatus ? Colors.green : Colors.amber[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
        _refreshData();
      }
    } catch (error) {
      debugPrint('--- ERRO AO ATUALIZAR STATUS: $error ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Exibe o modal moderno de criação de nova manutenção preventiva
  void _showAddMaintenanceModal(
    BuildContext context,
    Map<String, dynamic>? currentVehicle,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final currentKm = (currentVehicle?['mileage'] as num?)?.toInt() ?? 0;

    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final lastMileageController =
        TextEditingController(text: currentKm > 0 ? currentKm.toString() : '');
    final targetMileageController = TextEditingController(
      text: currentKm > 0 ? (currentKm + 10000).toString() : '10000',
    );

    bool isSubmitting = false;

    final factorySuggestions = const [
      FactoryMaintenanceSuggestion(
        title: 'Óleo do Motor & Filtro',
        defaultIntervalKm: 10000,
        explanation: 'Lubrifica e resfria as componentes internas do motor. Previne acúmulo de borra e desgaste prematuro dos pistões.',
        intervalText: 'Recomendado a cada 10.000 km ou 12 meses',
        icon: Icons.opacity_rounded,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Pastilhas de Freio',
        defaultIntervalKm: 25000,
        explanation: 'Garantem a fricção para a frenagem. Pastilhas desgastadas aumentam a distância de parada e riscam os discos.',
        intervalText: 'Recomendado a cada 25.000 km ou ao notar ruídos',
        icon: Icons.album_outlined,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Correia Dentada & Esticador',
        defaultIntervalKm: 50000,
        explanation: 'Sincroniza o virabrequim com o comando de válvulas. Seu rompimento causa colisão mecânica e retífica completa do motor.',
        intervalText: 'Recomendado a cada 50.000 km ou 3 a 5 anos',
        icon: Icons.settings_suggest_rounded,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Velas de Ignição',
        defaultIntervalKm: 30000,
        explanation: 'Geram a faísca ideal para a combustão. Velas gastas causam perda de potência, engasgos e consumo elevado.',
        intervalText: 'Recomendado a cada 30.000 km',
        icon: Icons.flash_on_rounded,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Fluido de Freio',
        defaultIntervalKm: 20000,
        explanation: 'Transmite a pressão hidráulica aos freios. Por absorver umidade (higroscópico), perde o ponto de ebulição e compromete a frenagem.',
        intervalText: 'Recomendado a cada 20.000 km ou 2 anos',
        icon: Icons.water_drop_rounded,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Filtro de Combustível',
        defaultIntervalKm: 10000,
        explanation: 'Retém partículas de sujeira do combustível antes dos bicos injetores, prevenindo falhas na aceleração.',
        intervalText: 'Recomendado a cada 10.000 km',
        icon: Icons.filter_alt_outlined,
      ),
      FactoryMaintenanceSuggestion(
        title: 'Alinhamento & Balanceamento',
        defaultIntervalKm: 10000,
        explanation: 'Evita a deformação irregular da banda de rodagem dos pneus e elimina vibrações indesejadas na direção.',
        intervalText: 'Recomendado a cada 10.000 km ou ao trocar pneus',
        icon: Icons.tire_repair_rounded,
      ),
    ];

    FactoryMaintenanceSuggestion? selectedSuggestion;
    final userVehicles = VehicleService.userVehiclesNotifier.value;
    Map<String, dynamic>? selectedVehicle = currentVehicle ?? VehicleService.activeVehicleNotifier.value;
    if (selectedVehicle == null && userVehicles.isNotEmpty) {
      selectedVehicle = userVehicles.first;
    }
    String? selectedVehicleId = selectedVehicle?['id']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            void applyKmIncrement(int kmToAdd) {
              final baseKm =
                  int.tryParse(lastMileageController.text.trim()) ?? currentKm;
              targetMileageController.text = (baseKm + kmToAdd).toString();
              setModalState(() {});
            }

            Future<void> handleSave() async {
              if (!formKey.currentState!.validate()) return;

              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sessão expirada. Faça login novamente.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final title = titleController.text.trim();
              final lastMileage = int.tryParse(
                    lastMileageController.text
                        .trim()
                        .replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  currentKm;
              final targetMileage = int.tryParse(
                    targetMileageController.text
                        .trim()
                        .replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;

              if (targetMileage <= lastMileage) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'A quilometragem limite deve ser maior que a da última troca.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              setModalState(() => isSubmitting = true);

              try {
                await Supabase.instance.client
                    .from('vehicle_maintenances')
                    .insert({
                  'user_id': user.id,
                  'vehicle_id': selectedVehicleId ?? selectedVehicle?['id'],
                  'title': title,
                  'last_mileage': lastMileage,
                  'target_mileage': targetMileage,
                  'is_completed': false,
                  'created_at': DateTime.now().toIso8601String(),
                });

                if (modalContext.mounted) {
                  Navigator.pop(modalContext);
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.white),
                          SizedBox(width: 10),
                          Text('Manutenção agendada com sucesso!'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }

                if (mounted) {
                  _refreshData();
                }
              } catch (error) {
                debugPrint('--- ERRO AO SALVAR MANUTENÇÃO: $error ---');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar: ${error.toString()}'),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } finally {
                if (modalContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
                top: 16,
                left: 24,
                right: 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Barra superior de arraste
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

                      // Título do modal
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.build_circle_rounded,
                            color: primaryColor,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Nova Manutenção',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Defina a revisão e o limite de km para acompanhar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Seletor de veículo se houver mais de 1 cadastrado
                      if (userVehicles.length > 1) ...[
                        Text(
                          'Selecione o Veículo',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242731),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedVehicleId,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF242731),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              items: userVehicles.map((v) {
                                return DropdownMenuItem<String>(
                                  value: v['id'].toString(),
                                  child: Text('${v['brand']} ${v['model']} (${v['year'] ?? ''})'),
                                );
                              }).toList(),
                              onChanged: (newId) {
                                if (newId != null) {
                                  final found = userVehicles.firstWhere(
                                    (v) => v['id'].toString() == newId,
                                    orElse: () => userVehicles.first,
                                  );
                                  setModalState(() {
                                    selectedVehicleId = newId;
                                    selectedVehicle = found;
                                    final km = (found['mileage'] as num?)?.toInt() ?? 0;
                                    lastMileageController.text =
                                        km > 0 ? km.toString() : '';
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Sugestões de Fábrica pré-configuradas
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Sugestões Inteligentes de Fábrica',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: factorySuggestions.map((suggestion) {
                            final isSelected =
                                selectedSuggestion?.title == suggestion.title;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ActionChip(
                                avatar: Icon(
                                  suggestion.icon,
                                  size: 16,
                                  color: isSelected
                                      ? const Color(0xFF121316)
                                      : primaryColor,
                                ),
                                label: Text(suggestion.title),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? const Color(0xFF121316)
                                      : Colors.white,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                                backgroundColor: isSelected
                                    ? primaryColor
                                    : const Color(0xFF242731),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                side: BorderSide(
                                  color: isSelected
                                      ? primaryColor
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                                onPressed: () {
                                  titleController.text = suggestion.title;
                                  final baseKm = int.tryParse(
                                          lastMileageController.text.trim()) ??
                                      currentKm;
                                  targetMileageController.text =
                                      (baseKm + suggestion.defaultIntervalKm)
                                          .toString();
                                  setModalState(() {
                                    selectedSuggestion = suggestion;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Explicação Educacional da Sugestão Selecionada
                      if (selectedSuggestion != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    selectedSuggestion!.icon,
                                    size: 16,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'POR QUE E QUANDO REVISAR?',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                selectedSuggestion!.explanation,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    selectedSuggestion!.intervalText,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),

                      // Campo Título do Serviço
                      TextFormField(
                        controller: titleController,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Título do Serviço',
                          hintText: 'Ex: Troca de Óleo 5W30',
                          prefixIcon: Icon(Icons.handyman_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe o nome do serviço ou peça.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo Quilometragem da última troca
                      TextFormField(
                        controller: lastMileageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quilometragem da Última Troca (km)',
                          hintText: 'Ex: 45000',
                          prefixIcon: const Icon(Icons.history_toggle_off_rounded),
                          suffixText: 'km',
                          suffixStyle: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe a quilometragem da última troca.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo Quilometragem limite / próxima troca
                      TextFormField(
                        controller: targetMileageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quilometragem Alvo / Limite (km)',
                          hintText: 'Ex: 55000',
                          prefixIcon: const Icon(Icons.flag_circle_outlined),
                          suffixText: 'km',
                          suffixStyle: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe a quilometragem limite para a troca.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Botões rápidos de acréscimo de km
                      Row(
                        children: [
                          Text(
                            'Adicionar:',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildIntervalChip('+5.000 km', () => applyKmIncrement(5000), primaryColor),
                          const SizedBox(width: 6),
                          _buildIntervalChip('+10.000 km', () => applyKmIncrement(10000), primaryColor),
                          const SizedBox(width: 6),
                          _buildIntervalChip('+20.000 km', () => applyKmIncrement(20000), primaryColor),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Botão Salvar Manutenção
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isSubmitting ? null : handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: const Color(0xFF121316),
                            disabledBackgroundColor:
                                primaryColor.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF121316),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      color: Color(0xFF121316),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Cadastrar Manutenção'),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titleController.dispose();
        lastMileageController.dispose();
        targetMileageController.dispose();
      });
    });
  }

  static Widget _buildIntervalChip(
    String label,
    VoidCallback onTap,
    Color primaryColor,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF242731),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primaryColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Retorna ícone representativo com base no título
  IconData _getServiceIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('óleo') || lower.contains('oleo')) {
      return Icons.opacity_rounded;
    } else if (lower.contains('freio') || lower.contains('pastilha')) {
      return Icons.album_outlined;
    } else if (lower.contains('correia')) {
      return Icons.settings_suggest_rounded;
    } else if (lower.contains('filtro')) {
      return Icons.filter_alt_outlined;
    } else if (lower.contains('pneu') || lower.contains('alinhamento') || lower.contains('balanceamento')) {
      return Icons.tire_repair_rounded;
    } else if (lower.contains('vela')) {
      return Icons.flash_on_rounded;
    }
    return Icons.build_circle_outlined;
  }

  /// Card visual de manutenção preventiva com status inteligente
  Widget _buildMaintenanceCard({
    required ThemeData theme,
    required Map<String, dynamic> item,
    required int currentVehicleKm,
    required int thresholdKm,
  }) {
    final id = item['id']?.toString() ?? '';
    final title = item['title'] as String? ?? 'Manutenção Preventiva';
    final targetMileage = (item['target_mileage'] as num?)?.toInt() ?? 0;
    final lastMileage = (item['last_mileage'] as num?)?.toInt() ?? 0;
    final isCompleted = item['is_completed'] as bool? ?? false;

    // Cálculo do status e km restantes
    final remainingKm = targetMileage - currentVehicleKm;
    final totalSpan = (targetMileage - lastMileage) > 0
        ? (targetMileage - lastMileage)
        : 10000;
    final elapsedSpan = currentVehicleKm - lastMileage;
    final progress = isCompleted
        ? 1.0
        : (elapsedSpan / totalSpan).clamp(0.0, 1.0);

    Color statusColor;
    String statusLabel;
    String detailLabel;
    IconData statusIcon;

    if (isCompleted) {
      statusColor = Colors.grey;
      statusLabel = 'Concluída';
      detailLabel = 'Realizada';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (remainingKm <= 0) {
      statusColor = Colors.redAccent;
      statusLabel = 'Vencida';
      final overdueKm = remainingKm.abs();
      detailLabel = overdueKm == 0
          ? 'Limite atingido!'
          : 'Ultrapassou $overdueKm km!';
      statusIcon = Icons.error_outline_rounded;
    } else if (remainingKm <= thresholdKm) {
      statusColor = Colors.amberAccent;
      statusLabel = 'Próxima';
      detailLabel = 'Faltam apenas $remainingKm km';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.greenAccent;
      statusLabel = 'Em dia';
      detailLabel = 'Faltam $remainingKm km';
      statusIcon = Icons.shield_outlined;
    }

    final serviceIcon = _getServiceIcon(title);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2028),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCompleted
              ? Colors.white.withValues(alpha: 0.04)
              : statusColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho: Ícone do Serviço, Título e Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? Colors.white.withValues(alpha: 0.05)
                          : statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      serviceIcon,
                      size: 26,
                      color: isCompleted ? Colors.grey : statusColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? Colors.grey[400] : Colors.white,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 13,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                detailLabel,
                                style: TextStyle(
                                  color: isCompleted
                                      ? Colors.grey[500]
                                      : Colors.grey[300],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.grey[400],
                      size: 22,
                    ),
                    color: const Color(0xFF242731),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'toggle') {
                        _toggleCompleteMaintenance(id, isCompleted);
                      } else if (value == 'delete') {
                        _deleteMaintenance(id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? Icons.restart_alt_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: isCompleted
                                  ? Colors.amberAccent
                                  : Colors.greenAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isCompleted
                                  ? 'Reabrir Manutenção'
                                  : 'Marcar como Concluída',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: const Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Excluir',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Barra de Progresso
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF2A2D3A),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCompleted ? Colors.grey : statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Informações de Quilometragem
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Última Troca',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$lastMileage km',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Próxima Troca (Alvo)',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$targetMileage km',
                        style: TextStyle(
                          color: isCompleted ? Colors.white70 : theme.colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estado Vazio quando não houver manutenções
  Widget _buildEmptyState(
    ThemeData theme,
    Map<String, dynamic>? currentVehicle,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.build_circle_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhuma manutenção agendada',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre serviços como troca de óleo, freios e correias para receber alertas preditivos inteligentes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _showAddMaintenanceModal(context, currentVehicle),
                icon: const Icon(Icons.add_rounded, color: Color(0xFF121316)),
                label: const Text('Cadastrar Primeira Manutenção'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: const Color(0xFF121316),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manutenções Preventivas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refreshData(),
          color: primaryColor,
          backgroundColor: const Color(0xFF1E2028),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: primaryColor),
                );
              }

              if (snapshot.hasError) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.7,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Erro ao carregar manutenções: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final data = snapshot.data ?? {};
              final currentVehicle = data['vehicle'] as Map<String, dynamic>?;
              final currentKm =
                  (currentVehicle?['mileage'] as num?)?.toInt() ?? 0;
              final thresholdKm = (data['thresholdKm'] as num?)?.toInt() ?? 1000;
              final maintenances =
                  data['maintenances'] as List<Map<String, dynamic>>? ?? [];

              if (maintenances.isEmpty) {
                return _buildEmptyState(theme, currentVehicle);
              }

              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                itemCount: maintenances.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Header de Resumo do Odômetro Atual
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2028),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.speed_rounded,
                            color: primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Odômetro do Veículo',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$currentKm km',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${maintenances.where((m) => !(m['is_completed'] as bool? ?? false)).length} ativas',
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final item = maintenances[index - 1];
                  return _buildMaintenanceCard(
                    theme: theme,
                    item: item,
                    currentVehicleKm: currentKm,
                    thresholdKm: thresholdKm,
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final data = await _dataFuture;
          if (context.mounted) {
            _showAddMaintenanceModal(
              context,
              data['vehicle'] as Map<String, dynamic>?,
            );
          }
        },
        backgroundColor: primaryColor,
        foregroundColor: const Color(0xFF121316),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Nova Manutenção',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
