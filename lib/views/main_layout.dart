import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/vehicle_service.dart';
import 'package:projectapp/views/account_view.dart';
import 'package:projectapp/views/add_refuel_view.dart';
import 'package:projectapp/views/home_view.dart';
import 'package:projectapp/views/jarvis_chat_view.dart';
import 'package:projectapp/views/vehicle_info_view.dart';
import 'package:projectapp/views/vehicle_maintenances_view.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  // Abas com preservação de estado via IndexedStack
  final List<Widget> _pages = const [
    HomeView(),
    JarvisChatView(),
    VehicleInfoView(),
    AccountView(),
  ];

  /// Abre o Hub de Ações Rápidas no estilo de apps financeiros de alta performance
  void _showQuickActionsHub(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Indicador de arrasto
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

                // Título do Hub
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.settings_suggest_rounded,
                        color: primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ações Rápidas',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'O que você deseja registrar agora?',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Card 1: ⛽ Registrar Abastecimento
                _buildActionTile(
                  icon: Icons.local_gas_station_rounded,
                  iconColor: const Color(0xFFFACC15),
                  title: 'Registrar Abastecimento',
                  subtitle: 'Adicione litros, preço e odômetro atual',
                  onTap: () async {
                    Navigator.pop(modalContext);
                    final vehicle = await _fetchActiveVehicle();
                    if (context.mounted) {
                      showAddRefuelBottomSheet(
                        context,
                        vehicle: vehicle,
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Card 2: 🔧 Adicionar Manutenção
                _buildActionTile(
                  icon: Icons.build_circle_rounded,
                  iconColor: Colors.cyanAccent,
                  title: 'Adicionar Manutenção',
                  subtitle: 'Cadastre revisões preventivas ou trocas',
                  onTap: () {
                    Navigator.pop(modalContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VehicleMaintenancesView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Card 3: ⏱️ Atualizar Odômetro
                _buildActionTile(
                  icon: Icons.speed_rounded,
                  iconColor: Colors.greenAccent,
                  title: 'Atualizar Odômetro',
                  subtitle: 'Sincronize a quilometragem atual do veículo',
                  onTap: () {
                    Navigator.pop(modalContext);
                    _showUpdateOdometerModal(context);
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF242731),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey[500],
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchActiveVehicle() async {
    final active = VehicleService.activeVehicleNotifier.value;
    if (active != null) return active;
    final list = await VehicleService.loadVehicles();
    return list.firstOrNull;
  }

  void _showUpdateOdometerModal(BuildContext parentContext) async {
    final vehicle = await _fetchActiveVehicle();
    if (!parentContext.mounted) return;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        return _UpdateOdometerBottomSheet(
          vehicle: vehicle,
          parentContext: parentContext,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121316),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
        ),
        child: BottomAppBar(
          color: Colors.transparent,
          elevation: 0,
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_rounded,
                label: 'Início',
                primaryColor: primaryColor,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Jarvis',
                primaryColor: primaryColor,
              ),
              // Botão da Turbina Integrado e Nivelado com Animação Fluida
              _TurbineNavButton(
                onTap: () => _showQuickActionsHub(context),
                primaryColor: primaryColor,
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.directions_car_rounded,
                label: 'Garagem',
                primaryColor: primaryColor,
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.person_rounded,
                label: 'Conta',
                primaryColor: primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color primaryColor,
  }) {
    final isSelected = _currentIndex == index;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  icon,
                  color: isSelected ? primaryColor : Colors.grey[500],
                  size: 22,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.grey[500],
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão da Turbina Integrado à Barra de Navegação com Animação Fluida e Blindagem Web
class _TurbineNavButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color primaryColor;

  const _TurbineNavButton({
    required this.onTap,
    required this.primaryColor,
  });

  @override
  State<_TurbineNavButton> createState() => _TurbineNavButtonState();
}

class _TurbineNavButtonState extends State<_TurbineNavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Curva segura estritamente contida no intervalo [0.0, 1.0] (sem overshoots do easeOutBack)
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(curve);
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) {
      if (mounted) {
        _controller.reverse();
      }
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Transform.rotate(
                      angle: _rotationAnimation.value * 3.14159 * 2,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/turbina-jarvis.svg',
                        width: 24,
                        height: 24,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF121316),
                          BlendMode.srcIn,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 8,
                            color: Color(0xFF121316),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ações',
                style: TextStyle(
                  color: widget.primaryColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateOdometerBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? vehicle;
  final BuildContext parentContext;

  const _UpdateOdometerBottomSheet({
    required this.vehicle,
    required this.parentContext,
  });

  @override
  State<_UpdateOdometerBottomSheet> createState() =>
      _UpdateOdometerBottomSheetState();
}

class _UpdateOdometerBottomSheetState
    extends State<_UpdateOdometerBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final currentMileage = (widget.vehicle?['mileage'] as num?)?.toInt() ?? 0;
    _controller = TextEditingController(
      text: currentMileage > 0 ? currentMileage.toString() : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.speed_rounded,
                    color: Colors.greenAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atualizar Odômetro',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Informe a quilometragem atual do painel',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              decoration: const InputDecoration(
                labelText: 'Quilometragem Atual (km)',
                suffixText: 'km',
                prefixIcon: Icon(Icons.speed_rounded),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Informe a quilometragem';
                }
                final numVal = int.tryParse(val.trim());
                if (numVal == null || numVal < 0) {
                  return 'Quilometragem inválida';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _isSaving = true);
                        final newKm = int.parse(_controller.text.trim());
                        final userId =
                            Supabase.instance.client.auth.currentUser?.id;

                        final messenger =
                            ScaffoldMessenger.of(widget.parentContext);
                        final nav = Navigator.of(context);

                        try {
                          if (userId != null && widget.vehicle != null) {
                            await Supabase.instance.client
                                .from('vehicles')
                                .update({
                              'mileage': newKm,
                              'updated_at': DateTime.now().toIso8601String(),
                            }).eq('id', widget.vehicle!['id']);

                            await VehicleService.loadVehicles(
                              preferredVehicleId:
                                  widget.vehicle!['id'].toString(),
                            );
                          }

                          nav.pop();

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Odômetro atualizado para $newKm km!',
                              ),
                              backgroundColor: Colors.green[700],
                            ),
                          );
                        } catch (err) {
                          debugPrint(
                              '--- ERRO AO ATUALIZAR ODÔMETRO: $err ---');
                          if (mounted) {
                            setState(() => _isSaving = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF121316),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF121316),
                        ),
                      )
                    : const Text('Salvar Nova Quilometragem'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
