import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/views/add_refuel_view.dart';
import 'package:projectapp/views/refuel_history_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Map<String, dynamic>? activeVehicle;
  List<Map<String, dynamic>> refuelsList = [];
  String userName = 'Motorista';
  bool _isLoading = true;

  double? averageConsumption;
  double monthlyExpenses = 0.0;
  String confidenceLabel = 'Dados Insuficientes';
  Color confidenceColor = Colors.grey;

  String jarvisInsight = 'Jarvis analisando telemetria...';
  bool _isJarvisLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
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

      // 2. Busca abastecimentos ordenados por odômetro crescente
      final refuelsData = await Supabase.instance.client
          .from('refuels')
          .select()
          .eq('user_id', user.id)
          .order('odometer', ascending: true);

      final list = List<Map<String, dynamic>>.from(refuelsData);

      // 3. Cálculos dinâmicos da telemetria
      _calculateMetrics(list);

      if (mounted) {
        setState(() {
          activeVehicle = vehicleData;
          refuelsList = list;
          _isLoading = false;
        });
      }

      // 4. Consulta a IA do Google Gemini em segundo plano
      await _fetchJarvisInsight(vehicleData);
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

  Future<void> _fetchJarvisInsight(Map<String, dynamic>? vehicle) async {
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2028),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Icon(
            Icons.notifications_none_rounded,
            color: Colors.grey[300],
            size: 22,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              Text(
                'Dica do Jarvis',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
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
                    Text(
                      'Jarvis analisando telemetria...',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              : Text(
                  jarvisInsight,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                    height: 1.45,
                  ),
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
                onRefresh: _fetchDashboardData,
                color: theme.colorScheme.primary,
                backgroundColor: const Color(0xFF1E2028),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
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
