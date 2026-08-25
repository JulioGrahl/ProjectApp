import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/services/vehicle_service.dart';
import 'package:projectapp/views/add_refuel_view.dart';
import 'package:projectapp/views/refuel_history_view.dart';
import 'package:projectapp/views/vehicle_maintenances_view.dart';
import 'package:projectapp/views/alert_preferences_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Map<String, dynamic>? activeVehicle;
  List<Map<String, dynamic>> refuelsList = [];
  List<Map<String, dynamic>> maintenancesList = [];
  int thresholdKm = 1000;
  int urgentAlertsCount = 0;
  String userName = 'Motorista';
  bool _isLoading = true;

  double? averageConsumption;
  double monthlyExpenses = 0.0;
  String confidenceLabel = 'Dados Insuficientes';
  Color confidenceColor = Colors.grey;

  JarvisInsightResult jarvisInsight = const JarvisInsightResult(
    homeInsight: JarvisHomeInsight(
      mensagemInvestigativa: 'Jarvis analisando telemetria e histórico...',
    ),
    modalStatus: JarvisModalStatus(
      diagnosticoCurto: 'Analisando telemetria...',
    ),
  );
  bool _isJarvisLoading = true;

  // Trava anti-loop infinito e controle de chamadas
  bool _isFetchingDashboard = false;
  bool _isFetchingJarvis = false;
  String? _currentVehicleId;
  String? _lastEvaluatedVehicleId;

  @override
  void initState() {
    super.initState();
    VehicleService.activeVehicleNotifier.addListener(_onActiveVehicleChanged);
    _initDashboard();
  }

  @override
  void dispose() {
    VehicleService.activeVehicleNotifier.removeListener(_onActiveVehicleChanged);
    super.dispose();
  }

  Future<void> _initDashboard() async {
    await VehicleService.loadVehicles();
    final active = VehicleService.activeVehicleNotifier.value;
    _currentVehicleId = active?['id']?.toString();
    await _fetchDashboardData(forceRefresh: false);
  }

  void _onActiveVehicleChanged() {
    final newVehicle = VehicleService.activeVehicleNotifier.value;
    final newId = newVehicle?['id']?.toString();
    if (newId != _currentVehicleId) {
      _currentVehicleId = newId;
      if (mounted) {
        _fetchDashboardData(forceRefresh: true);
      }
    }
  }

  Future<void> _fetchDashboardData({bool forceRefresh = false}) async {
    if (_isFetchingDashboard) {
      debugPrint('--- [DASHBOARD LOCK] _fetchDashboardData ja em andamento. Ignorando. ---');
      return;
    }

    _isFetchingDashboard = true;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isJarvisLoading = false;
        });
      }
      _isFetchingDashboard = false;
      return;
    }

    final fullName = user.userMetadata?['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      userName = fullName.split(' ').first;
    } else if (user.email != null) {
      userName = user.email!.split('@').first;
    }

    try {
      // 1. Obtém o veículo ativo sem relançar VehicleService.loadVehicles() em loop
      final vehicleData = VehicleService.activeVehicleNotifier.value;
      final vehicleId = vehicleData?['id']?.toString();
      _currentVehicleId = vehicleId;

      // 2. Busca preferências de alertas para saber a margem de antecedência (default: 1000 km)
      final alertPrefs = await Supabase.instance.client
          .from('user_alert_preferences')
          .select('mileage_threshold_km')
          .eq('user_id', user.id)
          .maybeSingle();
      final threshold =
          (alertPrefs?['mileage_threshold_km'] as num?)?.toInt() ?? 1000;

      List<Map<String, dynamic>> mList = [];
      List<Map<String, dynamic>> list = [];

      if (vehicleId != null && vehicleId.isNotEmpty) {
        // 3. Busca manutenções preventivas cadastradas ESTRITAMENTE para este veículo
        final maintenancesData = await Supabase.instance.client
            .from('vehicle_maintenances')
            .select()
            .eq('user_id', user.id)
            .eq('vehicle_id', vehicleId)
            .order('target_mileage', ascending: true);
        mList = List<Map<String, dynamic>>.from(maintenancesData);

        // 4. Busca abastecimentos ESTRITAMENTE para este veículo
        final refuelsData = await Supabase.instance.client
            .from('refuels')
            .select()
            .eq('user_id', user.id)
            .eq('vehicle_id', vehicleId)
            .order('odometer', ascending: true);
        list = List<Map<String, dynamic>>.from(refuelsData);
      }

      // 5. Cálculos dinâmicos e determinísticos da telemetria
      _calculateMetrics(list);

      // 6. Contabiliza alertas de manutenção pendentes/urgentes
      final currentKm = (vehicleData?['mileage'] as num?)?.toInt() ?? 0;
      int alertsCount = 0;
      for (final m in mList) {
        final isCompleted = m['is_completed'] as bool? ?? false;
        if (!isCompleted) {
          final targetKm = (m['target_mileage'] as num?)?.toInt() ?? 0;
          final remainingKm = targetKm - currentKm;
          if (remainingKm <= threshold) {
            alertsCount++;
          }
        }
      }

      if (mounted) {
        setState(() {
          activeVehicle = vehicleData;
          refuelsList = list;
          maintenancesList = mList;
          thresholdKm = threshold;
          urgentAlertsCount = alertsCount;
          _isLoading = false;
        });
      }

      // 7. Consulta o Jarvis AI Copilot com travamento anti-duplicação
      await _fetchJarvisInsight(vehicleData, mList, forceRefresh: forceRefresh);
    } catch (error) {
      debugPrint('--- ERRO AO CARREGAR DADOS DO DASHBOARD: $error ---');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isJarvisLoading = false;
        });
      }
    } finally {
      _isFetchingDashboard = false;
    }
  }

  Future<void> _fetchJarvisInsight(
    Map<String, dynamic>? vehicle,
    List<Map<String, dynamic>> maintenances, {
    bool forceRefresh = false,
  }) async {
    final vehicleId = vehicle?['id']?.toString();

    // Trava de segurança anti-duplicação: Impede rajadas de chamadas repetidas ao Gemini
    if (_isFetchingJarvis) {
      debugPrint('--- [JARVIS LOCK] Requisicao ao Jarvis ja em andamento. Bloqueado. ---');
      return;
    }

    if (!forceRefresh && _lastEvaluatedVehicleId == vehicleId && !_isJarvisLoading) {
      debugPrint('--- [JARVIS CACHE] Reutilizando insight carregado para o veiculo $vehicleId. ---');
      return;
    }

    _isFetchingJarvis = true;

    if (mounted) {
      setState(() {
        _isJarvisLoading = true;
      });
    }

    try {
      final vehicleName = vehicle != null
          ? '${vehicle['brand']} ${vehicle['model']}'
          : 'Veículo';
      final mileage = (vehicle?['mileage'] as num?)?.toInt() ?? 0;

      final insight = await JarvisAiService.generateJarvisInsight(
        vehicleName: vehicleName,
        mileage: mileage,
        averageConsumption: averageConsumption,
        monthlyExpenses: monthlyExpenses,
        maintenances: maintenances,
        forceRefresh: forceRefresh,
      );

      _lastEvaluatedVehicleId = vehicleId;

      if (mounted) {
        setState(() {
          jarvisInsight = insight;
          _isJarvisLoading = false;
        });
      }
    } catch (e) {
      debugPrint('--- ERRO AO BUSCAR INSIGHT DO JARVIS: $e ---');
      if (mounted) {
        setState(() {
          _isJarvisLoading = false;
        });
      }
    } finally {
      _isFetchingJarvis = false;
    }
  }

  void _calculateMetrics(List<Map<String, dynamic>> list) {
    // Cálculo do Consumo Médio Real
    if (list.length >= 2) {
      final firstRefuel = list.first;
      final lastRefuel = list.last;

      final firstOdometer = (firstRefuel['odometer'] as num?)?.toInt() ?? 0;
      final lastOdometer = (lastRefuel['odometer'] as num?)?.toInt() ?? 0;
      final deltaKm = lastOdometer - firstOdometer;

      // Soma dos litros consumidos a partir do segundo abastecimento
      double totalLiters = 0.0;
      for (int i = 1; i < list.length; i++) {
        totalLiters += (list[i]['liters'] as num?)?.toDouble() ?? 0.0;
      }

      if (deltaKm > 0 && totalLiters > 0) {
        averageConsumption = deltaKm / totalLiters;
      } else {
        averageConsumption = null;
      }

      if (list.length >= 3) {
        confidenceLabel = 'Alta Confiança';
        confidenceColor = Colors.greenAccent;
      } else {
        confidenceLabel = 'Média Confiança';
        confidenceColor = Colors.amberAccent;
      }
    } else {
      averageConsumption = null;
      confidenceLabel = 'Dados Insuficientes';
      confidenceColor = Colors.grey;
    }

    // Cálculo dos Gastos do Mês Atual
    final now = DateTime.now();
    double totalMonth = 0.0;

    for (final item in list) {
      final dateStr = item['date'] as String? ?? item['created_at'] as String?;
      if (dateStr != null) {
        final dt = DateTime.tryParse(dateStr);
        if (dt != null && dt.month == now.month && dt.year == now.year) {
          totalMonth += (item['total_price'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    monthlyExpenses = totalMonth;
  }

  String _formatCurrency(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return 'R\$ $integerPart,${parts[1]}';
  }

  String _formatInteger(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  void _handleJarvisAction(String route) {
    switch (route) {
      case 'maintenance_form':
      case 'maintenances':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const VehicleMaintenancesView(),
          ),
        ).then((_) => _fetchDashboardData());
        break;
      case 'refuel_form':
      case 'refuel':
        showAddRefuelBottomSheet(
          context,
          vehicle: activeVehicle,
          onRefuelSaved: _fetchDashboardData,
        );
        break;
      case 'alert_preferences':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AlertPreferencesView(),
          ),
        ).then((_) => _fetchDashboardData());
        break;
      default:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const VehicleMaintenancesView(),
          ),
        ).then((_) => _fetchDashboardData());
    }
  }

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
    } else if (lower.contains('pneu') ||
        lower.contains('alinhamento') ||
        lower.contains('balanceamento')) {
      return Icons.tire_repair_rounded;
    } else if (lower.contains('vela')) {
      return Icons.flash_on_rounded;
    }
    return Icons.build_circle_outlined;
  }

  void _showNotificationsSheet(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final currentKm = (activeVehicle?['mileage'] as num?)?.toInt() ?? 0;

    final pendingMaintenances = maintenancesList
        .where((item) => !(item['is_completed'] as bool? ?? false))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (scrollContext, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),

                // Cabeçalho
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Central de Alertas',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              urgentAlertsCount > 0
                                  ? '$urgentAlertsCount aviso(s) requerem atenção'
                                  : 'Tudo em dia com seu veículo',
                              style: TextStyle(
                                color: urgentAlertsCount > 0
                                    ? Colors.amberAccent
                                    : Colors.grey[400],
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.grey[400],
                          size: 22,
                        ),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),

                // Lista rolável
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 20.0,
                    ),
                    children: [
                      // Status dos Sistemas (Jarvis - Leitura Rápida e Direta)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2028),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'STATUS DOS SISTEMAS (JARVIS)',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  _isJarvisLoading
                                      ? Row(
                                          children: [
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: primaryColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Verificando telemetria...',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 13,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Text(
                                          jarvisInsight.modalStatus.diagnosticoCurto,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Cabeçalho da Seção de Manutenções
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Alertas Mecânicos & Revisões',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (pendingMaintenances.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: urgentAlertsCount > 0
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${pendingMaintenances.length} ativa(s)',
                                style: TextStyle(
                                  color: urgentAlertsCount > 0
                                      ? Colors.amberAccent
                                      : Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (pendingMaintenances.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2028),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.greenAccent.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: Colors.greenAccent,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Nenhuma revisão pendente',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Todas as manutenções cadastradas estão em dia ou concluídas.',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...pendingMaintenances.map((item) {
                          final title =
                              item['title'] as String? ?? 'Manutenção';
                          final targetMileage =
                              (item['target_mileage'] as num?)?.toInt() ?? 0;
                          final remainingKm = targetMileage - currentKm;

                          Color statusColor;
                          String statusLabel;
                          String detailLabel;
                          IconData statusIcon;

                          if (remainingKm <= 0) {
                            statusColor = Colors.redAccent;
                            statusLabel = 'Vencida';
                            final overdueKm = remainingKm.abs();
                            detailLabel = overdueKm == 0
                                ? 'Limite de km atingido!'
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

                          return InkWell(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const VehicleMaintenancesView(),
                                ),
                              ).then((_) => _fetchDashboardData());
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2028),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      serviceIcon,
                                      size: 22,
                                      color: statusColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    statusIcon,
                                                    size: 11,
                                                    color: statusColor,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    statusLabel,
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                  color: Colors.grey[400],
                                                  fontSize: 11.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey[500],
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                      const SizedBox(height: 20),

                      // Botão Principal: Ver Manutenções Preventivas
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const VehicleMaintenancesView(),
                              ),
                            ).then((_) => _fetchDashboardData());
                          },
                          icon: const Icon(
                            Icons.build_circle_rounded,
                            color: Color(0xFF121316),
                            size: 20,
                          ),
                          label: const Text('Ver Manutenções Preventivas'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: const Color(0xFF121316),
                            elevation: 0,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Botão Secundário: Preferências de Alertas
                      SizedBox(
                        height: 48,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AlertPreferencesView(),
                              ),
                            ).then((_) => _fetchDashboardData());
                          },
                          icon: Icon(
                            Icons.tune_rounded,
                            color: Colors.grey[300],
                            size: 18,
                          ),
                          label: const Text(
                            'Configurar Preferências de Alertas',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER: DRIVER // NOME — sem saudação genérica, foco em status
  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // HEADER: DRIVER // NOME — sem saudação genérica, foco em status
  // ─────────────────────────────────────────────────────────────
  Widget _buildWelcomeHeader(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    final user = Supabase.instance.client.auth.currentUser;
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final vehicleTitle = activeVehicle != null
        ? '${activeVehicle!['brand']} ${activeVehicle!['model']}'.toUpperCase()
        : 'SEM VEÍCULO';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Foto de Perfil Dinâmica com CircleAvatar e Fallback para Icons.person
        CircleAvatar(
          radius: 21,
          backgroundColor: const Color(0xFF121316),
          child: (avatarUrl != null && avatarUrl.trim().isNotEmpty)
              ? ClipOval(
                  child: Image.network(
                    avatarUrl,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                )
              : const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 22,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'DRIVER // ',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                    TextSpan(
                      text: userName.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                vehicleTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Sino de alertas — mantido integralmente
        GestureDetector(
          onTap: () => _showNotificationsSheet(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF121316),
              shape: BoxShape.circle,
              border: Border.all(
                color: urgentAlertsCount > 0
                    ? Colors.amberAccent.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  urgentAlertsCount > 0
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: urgentAlertsCount > 0 ? accent : Colors.grey,
                  size: 22,
                ),
                if (urgentAlertsCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PAINEL DE TELEMETRIA — dados brutos, tipografia brutal
  // ─────────────────────────────────────────────────────────────
  Widget _buildSummaryPanel(ThemeData theme) {
    final accent = theme.colorScheme.primary;
    final rawMileage = (activeVehicle?['mileage'] as num?)?.toInt() ?? 0;
    final mileageStr = _formatInteger(rawMileage);
    final consumptionDisplay = averageConsumption != null
        ? averageConsumption!.toStringAsFixed(1).replaceAll('.', ',')
        : '--';

    return Container(
      color: const Color(0xFF000000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha de separação topo — régua de dados
          Container(height: 1, color: accent.withValues(alpha: 0.5)),
          const SizedBox(height: 20),

          // Métrica Hero: Consumo
          _telemetryLabel('CONSUMO MÉDIO REAL', accent),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                consumptionDisplay,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -3,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'KM/L',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              // Badge de confiança — sem arredondamento
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.12),
                  border: Border.all(
                    color: confidenceColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  confidenceLabel.toUpperCase(),
                  style: TextStyle(
                    color: confidenceColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 20),

          // Linha de dados secundários: Gastos | Odômetro
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _telemetryLabel('GASTOS DO MÊS', accent),
                      const SizedBox(height: 6),
                      Text(
                        _formatCurrency(monthlyExpenses),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _telemetryLabel('ODÔMETRO', accent),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: mileageStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const TextSpan(
                            text: ' KM',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF555566),
                              letterSpacing: 1,
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Container(height: 1, color: accent.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  Widget _telemetryLabel(String text, Color accent) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: accent.withValues(alpha: 0.7),
        letterSpacing: 2.0,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // JARVIS LOG — output de sistema, estética de terminal de dados
  // ─────────────────────────────────────────────────────────────
  Widget _buildJarvisInsightCard(ThemeData theme) {
    final defaultAccent = theme.colorScheme.primary;
    final homeInsight = jarvisInsight.homeInsight;
    final hasAction = homeInsight.textoBotaoAcao != null &&
        homeInsight.textoBotaoAcao!.trim().isNotEmpty;

    // Definição dinâmica do estado de alerta (Crítico, Atenção ou Normal)
    Color statusColor;
    String headerLabel;
    String statusBadgeText;
    Color containerBg;
    Color borderColor;

    switch (homeInsight.nivelAlerta) {
      case 'critico':
        statusColor = Colors.redAccent;
        headerLabel = 'ALERTA CRÍTICO DE TELEMETRIA';
        statusBadgeText = 'REVISÃO URGENTE';
        containerBg = const Color(0xFF160909);
        borderColor = Colors.redAccent;
        break;
      case 'atencao':
        statusColor = Colors.amberAccent;
        headerLabel = 'ATENÇÃO · REVISÃO PRÓXIMA';
        statusBadgeText = 'ATENÇÃO';
        containerBg = const Color(0xFF141109);
        borderColor = Colors.amberAccent.withValues(alpha: 0.7);
        break;
      default:
        statusColor = defaultAccent;
        headerLabel = 'JARVIS · LOG DE TELEMETRIA';
        statusBadgeText = 'MONITORAMENTO ATIVO';
        containerBg = const Color(0xFF0A0A0A);
        borderColor = defaultAccent.withValues(alpha: 0.25);
    }

    return Container(
      color: const Color(0xFF000000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do log de sistema com indicador de estado
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: statusColor,
                margin: const EdgeInsets.only(right: 10),
              ),
              Text(
                headerLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                  letterSpacing: 2.0,
                ),
              ),
              const Spacer(),
              if (_isJarvisLoading)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: statusColor,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                _isJarvisLoading ? 'PROCESSANDO' : statusBadgeText,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _isJarvisLoading ? Colors.grey : statusColor,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Corpo — bloco de terminal com borda e fundo dinâmicos conforme nivelAlerta
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: containerBg,
              border: Border.all(
                color: borderColor,
                width: homeInsight.nivelAlerta == 'critico' ? 1.5 : 1.0,
              ),
            ),
            child: _isJarvisLoading
                ? Row(
                    children: [
                      Text(
                        '> ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Analisando histórico de telemetria...',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '> ',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: statusColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              homeInsight.mensagemInvestigativa,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: homeInsight.nivelAlerta == 'critico'
                                    ? Colors.white
                                    : const Color(0xFFCCCCCC),
                                fontSize: 13,
                                fontWeight: homeInsight.nivelAlerta == 'critico'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (hasAction) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => _handleJarvisAction(
                            homeInsight.rotaAcaoSugerida ?? 'maintenance_form',
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 13, horizontal: 20),
                            decoration: BoxDecoration(
                              color: homeInsight.nivelAlerta == 'critico'
                                  ? statusColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: statusColor,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(
                                      homeInsight.textoBotaoAcao!.toUpperCase(),
                                      style: TextStyle(
                                        color: homeInsight.nivelAlerta == 'critico'
                                            ? const Color(0xFF121316)
                                            : statusColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward,
                                  color: homeInsight.nivelAlerta == 'critico'
                                      ? const Color(0xFF121316)
                                      : statusColor,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BOTÕES DE AÇÃO — estilo pílula (StadiumBorder / BorderRadius.circular 100)
  // ─────────────────────────────────────────────────────────────
  Widget _buildQuickShortcuts(ThemeData theme) {
    final accent = theme.colorScheme.primary;

    return Row(
      children: [
        // ABASTECER — pílula neon sólido
        Expanded(
          child: GestureDetector(
            onTap: () {
              showAddRefuelBottomSheet(
                context,
                vehicle: activeVehicle,
                onRefuelSaved: _fetchDashboardData,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_gas_station_rounded,
                    color: Color(0xFF090A0D),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'ABASTECER',
                    style: TextStyle(
                      color: Color(0xFF090A0D),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // HISTÓRICO — pílula borda branca
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RefuelHistoryView(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.5,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'HISTÓRICO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: accent),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  JarvisAiService.clearCache();
                  await _fetchDashboardData(forceRefresh: true);
                },
                color: accent,
                backgroundColor: const Color(0xFF121316),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWelcomeHeader(theme),
                      const SizedBox(height: 32),
                      _buildSummaryPanel(theme),
                      const SizedBox(height: 28),
                      _buildJarvisInsightCard(theme),
                      const SizedBox(height: 28),
                      _buildQuickShortcuts(theme),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
