import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void showAddRefuelBottomSheet(
  BuildContext context, {
  Map<String, dynamic>? vehicle,
  VoidCallback? onRefuelSaved,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1B22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (modalContext) {
      return AddRefuelBottomSheet(
        vehicle: vehicle,
        onRefuelSaved: onRefuelSaved,
      );
    },
  );
}

class AddRefuelBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? vehicle;
  final VoidCallback? onRefuelSaved;

  const AddRefuelBottomSheet({
    super.key,
    this.vehicle,
    this.onRefuelSaved,
  });

  @override
  State<AddRefuelBottomSheet> createState() => _AddRefuelBottomSheetState();
}

class _AddRefuelBottomSheetState extends State<AddRefuelBottomSheet> {
  final _odometerController = TextEditingController();
  final _litersController = TextEditingController();
  final _totalPriceController = TextEditingController();
  bool _fullTank = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.vehicle != null && widget.vehicle!['mileage'] != null) {
      _odometerController.text = widget.vehicle!['mileage'].toString();
    }
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _litersController.dispose();
    _totalPriceController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveRefuel() async {
    final kmText = _odometerController.text.trim();
    final litersText = _litersController.text.trim();
    final priceText = _totalPriceController.text.trim();

    if (kmText.isEmpty || litersText.isEmpty || priceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, preencha a quilometragem, litros e valor total.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Limpa pontuação do odômetro antes do parse
    final cleanKmText = kmText.replaceAll(RegExp(r'[^0-9]'), '');
    final odometer = int.tryParse(cleanKmText) ?? 0;
    final liters = double.tryParse(litersText.replaceAll(',', '.')) ?? 0.0;
    final totalPrice = double.tryParse(priceText.replaceAll(',', '.')) ?? 0.0;

    if (odometer <= 0 || liters <= 0 || totalPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, informe valores numéricos válidos.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sua sessão expirou. Por favor, faça login novamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Busca o veículo ativo do usuário se não tiver sido passado
      Map<String, dynamic>? activeVehicle = widget.vehicle;
      activeVehicle ??= await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (activeVehicle == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cadastre um veículo antes de registrar um abastecimento.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final vehicleId = activeVehicle['id'];
      final pricePerLiter = liters > 0 ? (totalPrice / liters) : 0.0;

      // 1. Inserir na tabela refuels do Supabase incluindo user_id e vehicle_id
      await Supabase.instance.client.from('refuels').insert({
        'user_id': userId,
        'vehicle_id': vehicleId,
        'odometer': odometer,
        'liters': liters,
        'total_price': totalPrice,
        'price_per_liter': double.parse(pricePerLiter.toStringAsFixed(2)),
        'full_tank': _fullTank,
        'date': DateTime.now().toIso8601String(),
      });

      // 2. Atualização Inteligente da quilometragem no veículo
      final currentMileage = activeVehicle['mileage'] as int? ?? 0;
      if (odometer > currentMileage) {
        await Supabase.instance.client
            .from('vehicles')
            .update({'mileage': odometer})
            .eq('id', vehicleId);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abastecimento registrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onRefuelSaved?.call();
      }
    } catch (error) {
      debugPrint('--- ERRO AO SALVAR ABASTECIMENTO: $error ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar abastecimento: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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

            // Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_gas_station_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'Registrar Abastecimento',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quilometragem Atual (Apenas inteiros / formato estrito)
            TextField(
              controller: _odometerController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Quilometragem Atual (km)',
                prefixIcon: Icon(Icons.speed_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // Litros Abastecidos
            TextField(
              controller: _litersController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Litros Abastecidos (ex: 45.5)',
                prefixIcon: Icon(Icons.opacity_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // Valor Total Pago
            TextField(
              controller: _totalPriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Valor Total Pago (R\$ ex: 250.00)',
                prefixIcon: Icon(Icons.attach_money_rounded),
              ),
            ),
            const SizedBox(height: 20),

            // Switch Tanque Cheio
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2028),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.invert_colors_rounded,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Tanque Cheio?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: _fullTank,
                    activeThumbColor: theme.colorScheme.primary,
                    activeTrackColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                    onChanged: (value) {
                      setState(() {
                        _fullTank = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Botão Salvar Abastecimento
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSaveRefuel,
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
                          Text('Salvar Abastecimento'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
