import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final _yearController = TextEditingController();
  final _odometerController = TextEditingController();

  Map<String, dynamic>? currentVehicle;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    fetchVehicle();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  Future<void> fetchVehicle() async {
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
      final data = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          currentVehicle = data;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('--- ERRO AO BUSCAR VEÍCULO: $error ---');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearControllers() {
    _brandController.clear();
    _modelController.clear();
    _yearController.clear();
    _odometerController.clear();
  }

  Future<void> _saveVehicle(BuildContext modalContext, StateSetter setModalState) async {
    debugPrint('--- BOTÃO CLICADO ---');

    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final yearText = _yearController.text.trim();
    final kmText = _odometerController.text.trim();

    if (brand.isEmpty || model.isEmpty || yearText.isEmpty || kmText.isEmpty) {
      debugPrint('--- VALIDAÇÃO FALHOU: CAMPOS VAZIOS ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, preencha todos os campos.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('--- ERRO: USUÁRIO NÃO AUTENTICADO ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuário não autenticado. Faça login novamente.'),
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
      final year = int.tryParse(cleanYear) ?? 0;
      final mileage = int.tryParse(cleanKm) ?? 0;

      debugPrint('--- INSERINDO VEÍCULO NO SUPABASE ---');
      await Supabase.instance.client.from('vehicles').insert({
        'user_id': user.id,
        'brand': brand,
        'model': model,
        'year': year,
        'mileage': mileage,
      });

      debugPrint('--- VEÍCULO SALVO COM SUCESSO! ---');

      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }

      _clearControllers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veículo salvo com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        await fetchVehicle();
      }
    } catch (error) {
      debugPrint('--- ERRO AO SALVAR: $error ---');
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
    final theme = Theme.of(context);

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
                    // Handle Bar
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

                    // Title
                    Text(
                      'Novo Veículo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preencha as informações básicas do seu carro',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Marca
                    TextField(
                      controller: _brandController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Marca (ex: Honda)',
                        prefixIcon: Icon(Icons.branding_watermark_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Modelo
                    TextField(
                      controller: _modelController,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Modelo (ex: Civic)',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ano
                    TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Ano',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quilometragem
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

                    // Button Salvar
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => _saveVehicle(modalContext, setModalState),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: const Color(0xFF121316),
                          disabledBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.5),
                          elevation: 0,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: _isSubmitting
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
                                  Icon(Icons.check_rounded, color: Color(0xFF121316)),
                                  SizedBox(width: 8),
                                  Text('Salvar Veículo'),
                                ],
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
    );
  }

  Widget _buildEmptyStateCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF222530),
            Color(0xFF161820),
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
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhum veículo cadastrado',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Cadastre seu carro para acompanhar abastecimentos, consumo real, alertas de manutenção e estatísticas inteligentes.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[400],
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
              icon: const Icon(Icons.add_rounded, color: Color(0xFF121316)),
              label: const Text('Adicionar meu primeiro veículo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: const Color(0xFF121316),
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetailsView(ThemeData theme, Map<String, dynamic> vehicle) {
    final brand = vehicle['brand'] as String? ?? '';
    final model = vehicle['model'] as String? ?? '';
    final year = vehicle['year']?.toString() ?? 'N/I';
    final mileage = vehicle['mileage']?.toString() ?? '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Harmonized Hero Vehicle Card
        Container(
          padding: const EdgeInsets.all(28.0),
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
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Tag & Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'VEÍCULO PRINCIPAL',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      size: 26,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Title (Brand & Model)
              Text(
                '$brand $model',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Divider Line
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              const SizedBox(height: 20),

              // Grid of Stats (Ano & Quilometragem)
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      theme: theme,
                      icon: Icons.calendar_today_rounded,
                      label: 'Ano',
                      value: year,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(
                      theme: theme,
                      icon: Icons.speed_rounded,
                      label: 'Quilometragem',
                      value: '$mileage km',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),

        // Quick Actions Section (Com bastante respiro)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ações Rápidas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Cards de Ação Rápidas leves e sem redundância
        Row(
          children: [
            Expanded(
              child: _buildQuickActionButton(
                theme: theme,
                icon: Icons.local_gas_station_rounded,
                label: 'Abastecer',
                subtitle: 'Registrar consumo',
                onTap: () {
                  showAddRefuelBottomSheet(
                    context,
                    vehicle: currentVehicle,
                    onRefuelSaved: fetchVehicle,
                  );
                },
                isHighlight: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildQuickActionButton(
                theme: theme,
                icon: Icons.history_rounded,
                label: 'Histórico',
                subtitle: 'Ver registros',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RefuelHistoryView(),
                    ),
                  );
                },
                isHighlight: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    required bool isHighlight,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1C24),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isHighlight
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isHighlight
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isHighlight ? theme.colorScheme.primary : Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Meu Veículo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (currentVehicle == null)
                      _buildEmptyStateCard(theme)
                    else
                      _buildVehicleDetailsView(theme, currentVehicle!),
                  ],
                ),
              ),
      ),
    );
  }
}
