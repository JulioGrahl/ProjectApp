import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
                        Icons.bolt_rounded,
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
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    try {
      return await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  void _showUpdateOdometerModal(BuildContext parentContext) async {
    final vehicle = await _fetchActiveVehicle();
    if (!parentContext.mounted) return;

    final currentMileage = (vehicle?['mileage'] as num?)?.toInt() ?? 0;
    final controller = TextEditingController(
      text: currentMileage > 0 ? currentMileage.toString() : '',
    );
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showModalBottomSheet(
      context: parentContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
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
              child: Form(
                key: formKey,
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
                      controller: controller,
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
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => isSaving = true);
                                final newKm = int.parse(controller.text.trim());
                                final userId =
                                    Supabase.instance.client.auth.currentUser?.id;

                                try {
                                  if (userId != null && vehicle != null) {
                                    await Supabase.instance.client
                                        .from('vehicles')
                                        .update({
                                      'mileage': newKm,
                                      'updated_at':
                                          DateTime.now().toIso8601String(),
                                    }).eq('id', vehicle['id']);
                                  }

                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }

                                  if (parentContext.mounted) {
                                    ScaffoldMessenger.of(parentContext)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Odômetro atualizado para $newKm km!',
                                        ),
                                        backgroundColor: Colors.green[700],
                                      ),
                                    );
                                  }
                                } catch (err) {
                                  debugPrint('--- ERRO AO ATUALIZAR ODÔMETRO: $err ---');
                                } finally {
                                  if (modalCtx.mounted) {
                                    setModalState(() => isSaving = false);
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
                        child: isSaving
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Stack(
      children: [
        Scaffold(
          extendBody: false,
          resizeToAvoidBottomInset: true,
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          // FAB "Fantasma" apenas para disparar a animação nativa do notch na BottomAppBar
          floatingActionButton: _currentIndex == 1
              ? null
              : const SizedBox(width: 56, height: 56),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: BottomAppBar(
            shape: const CircularNotchedRectangle(),
            notchMargin: 8.0,
            color: const Color(0xFF1E2028),
            elevation: 10,
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Esquerda: Início e Jarvis
                Row(
                  children: [
                    _buildNavItem(
                      index: 0,
                      icon: Icons.home_rounded,
                      label: 'Início',
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    _buildNavItem(
                      index: 1,
                      icon: Icons.auto_awesome_rounded,
                      label: 'Jarvis',
                      primaryColor: primaryColor,
                    ),
                  ],
                ),

                // Espaço central reservado para o botão
                const SizedBox(width: 56),

                // Direita: Veículo e Conta
                Row(
                  children: [
                    _buildNavItem(
                      index: 2,
                      icon: Icons.directions_car_rounded,
                      label: 'Veículo',
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    _buildNavItem(
                      index: 3,
                      icon: Icons.person_rounded,
                      label: 'Conta',
                      primaryColor: primaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Botão Físico Universal Animado (Morphing e Deslizamento Y)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          bottom: _currentIndex == 1 ? 16.0 : 46.0,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => _showQuickActionsHub(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                width: _currentIndex == 1 ? 46.0 : 56.0,
                height: _currentIndex == 1 ? 46.0 : 56.0,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 350),
                  scale: _currentIndex == 1 ? 0.8 : 1.0,
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFF121316),
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color primaryColor,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : Colors.grey[500],
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? primaryColor : Colors.grey[500],
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
