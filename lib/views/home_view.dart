import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData({bool forceRefresh = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isJarvisLoading = false;
        });
      }
      return;
    }

    final fullName = user.userMetadata?['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      userName = fullName.split(' ').first;
    } else if (user.email != null) {
      userName = user.email!.split('@').first;
    }

    try {
      // 1. Busca veículo principal
      final vehicleData = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      // 2. Busca preferências de alertas para saber a margem de antecedência (default: 1000 km)
      final alertPrefs = await Supabase.instance.client
          .from('user_alert_preferences')
          .select('mileage_threshold_km')
          .eq('user_id', user.id)
          .maybeSingle();
      final threshold =
          (alertPrefs?['mileage_threshold_km'] as num?)?.toInt() ?? 1000;

      // 3. Busca manutenções preventivas cadastradas
      final maintenancesData = await Supabase.instance.client
          .from('vehicle_maintenances')
          .select()
          .eq('user_id', user.id)
          .order('target_mileage', ascending: true);
      final mList = List<Map<String, dynamic>>.from(maintenancesData);

      // 4. Busca abastecimentos ordenados por odômetro crescente
      final refuelsData = await Supabase.instance.client
          .from('refuels')
          .select()
          .eq('user_id', user.id)
          .order('odometer', ascending: true);

      final list = List<Map<String, dynamic>>.from(refuelsData);

      // 5. Cálculos dinâmicos da telemetria
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

      // 7. Consulta o Jarvis AI Copilot com cache inteligente
      await _fetchJarvisInsight(vehicleData, mList, forceRefresh: forceRefresh);
    } catch (error) {
      debugPrint('--- ERRO AO CARREGAR DADOS DO DASHBOARD: $error ---');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isJarvisLoading = false;
        });
      }
    }
  }

  Future<void> _fetchJarvisInsight(
    Map<String, dynamic>? vehicle,
    List<Map<String, dynamic>> maintenances, {
    bool forceRefresh = false,
  }) async {
    if (mounted) {
      setState(() {
        _isJarvisLoading = true;
      });
    }

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

    if (mounted) {
      setState(() {
        jarvisInsight = insight;
        _isJarvisLoading = false;
      });
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

  Widget _buildWelcomeHeader(ThemeData theme) {
    final vehicleTitle = activeVehicle != null
        ? '${activeVehicle!['brand']} ${activeVehicle!['model']}'
        : 'Nenhum veículo selecionado';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Olá, $userName 👋',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.directions_car_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  vehicleTitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        Material(
          color: const Color(0xFF1E2028),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showNotificationsSheet(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: urgentAlertsCount > 0
                      ? Colors.amberAccent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    urgentAlertsCount > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: urgentAlertsCount > 0
                        ? theme.colorScheme.primary
                        : Colors.grey[300],
                    size: 22,
                  ),
                  if (urgentAlertsCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E2028),
                            width: 1.5,
                          ),
                        ),
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

  Widget _buildSummaryPanel(ThemeData theme) {
    final rawMileage = (activeVehicle?['mileage'] as num?)?.toInt() ?? 0;
    final mileageStr = '${_formatInteger(rawMileage)} km';

    final consumptionDisplay = averageConsumption != null
        ? averageConsumption!.toStringAsFixed(1).replaceAll('.', ',')
        : '--';

    return Container(
      padding: const EdgeInsets.all(26.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF232634),
            Color(0xFF161720),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Consumo Médio Real
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONSUMO MÉDIO ATUAL',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        consumptionDisplay,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'km/L',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: confidenceColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: confidenceColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      confidenceLabel,
                      style: TextStyle(
                        color: confidenceColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 20),

          // Gastos este Mês & Odômetro
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gastos este mês',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(monthlyExpenses),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Odômetro atual',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mileageStr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJarvisInsightCard(ThemeData theme) {
    final homeInsight = jarvisInsight.homeInsight;
    final hasAction = homeInsight.textoBotaoAcao != null &&
        homeInsight.textoBotaoAcao!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(22.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1D26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dica do Jarvis',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _isJarvisLoading
              ? Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Jarvis analisando telemetria e histórico...',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      homeInsight.mensagemInvestigativa,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    if (hasAction) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _handleJarvisAction(
                            homeInsight.rotaAcaoSugerida ?? 'maintenance_form',
                          ),
                          icon: Icon(
                            Icons.handyman_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(
                            homeInsight.textoBotaoAcao!,
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.08),
                            side: BorderSide(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildQuickShortcuts(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              showAddRefuelBottomSheet(
                context,
                vehicle: activeVehicle,
                onRefuelSaved: _fetchDashboardData,
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_gas_station_rounded,
                    color: Color(0xFF121316),
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Abastecer',
                    style: TextStyle(
                      color: Color(0xFF121316),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RefuelHistoryView(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2028),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Histórico',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  JarvisAiService.clearCache();
                  await _fetchDashboardData(forceRefresh: true);
                },
                color: theme.colorScheme.primary,
                backgroundColor: const Color(0xFF1E2028),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWelcomeHeader(theme),
                      const SizedBox(height: 28),
                      _buildSummaryPanel(theme),
                      const SizedBox(height: 24),
                      _buildJarvisInsightCard(theme),
                      const SizedBox(height: 24),
                      _buildQuickShortcuts(theme),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
