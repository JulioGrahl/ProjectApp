import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlertPreferencesView extends StatefulWidget {
  const AlertPreferencesView({super.key});

  @override
  State<AlertPreferencesView> createState() => _AlertPreferencesViewState();
}

class _AlertPreferencesViewState extends State<AlertPreferencesView> {
  final _formKey = GlobalKey<FormState>();
  final _mileageThresholdController = TextEditingController(text: '1000');

  bool _isLoading = true;
  bool _isSaving = false;
  bool _enableMechanicalAlerts = true;
  bool _enableFinancialAlerts = true;

  @override
  void initState() {
    super.initState();
    _fetchAlertPreferences();
  }

  @override
  void dispose() {
    _mileageThresholdController.dispose();
    super.dispose();
  }

  /// Busca as preferências de alerta do usuário autenticado no Supabase.
  /// Se não existir registro prévio, cria um registro inicial com os valores padrão.
  Future<void> _fetchAlertPreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('user_alert_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        if (mounted) {
          setState(() {
            _enableMechanicalAlerts =
                data['enable_mechanical_alerts'] as bool? ?? true;
            _enableFinancialAlerts =
                data['enable_financial_alerts'] as bool? ?? true;
            final threshold = data['mileage_threshold_km'];
            _mileageThresholdController.text =
                threshold != null ? threshold.toString() : '1000';
            _isLoading = false;
          });
        }
      } else {
        // Se ainda não existir registro na tabela, cria um registro padrão no Supabase
        await _insertDefaultPreferences(user.id);
      }
    } catch (error) {
      debugPrint('--- ERRO AO CARREGAR PREFERÊNCIAS DE ALERTAS: $error ---');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar configurações: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Insere as preferências padrão no Supabase para novos usuários.
  Future<void> _insertDefaultPreferences(String userId) async {
    try {
      final defaultData = {
        'user_id': userId,
        'enable_mechanical_alerts': true,
        'enable_financial_alerts': true,
        'mileage_threshold_km': 1000,
      };

      await Supabase.instance.client
          .from('user_alert_preferences')
          .insert(defaultData);

      if (mounted) {
        setState(() {
          _enableMechanicalAlerts = true;
          _enableFinancialAlerts = true;
          _mileageThresholdController.text = '1000';
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('--- ERRO AO INSERIR PREFERÊNCIAS PADRÃO: $error ---');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Salva ou atualiza (UPSERT) as configurações do usuário no Supabase.
  Future<void> _saveAlertPreferences() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sua sessão expirou. Faça login novamente.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final cleanKmText =
        _mileageThresholdController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final mileageThreshold = int.tryParse(cleanKmText) ?? 1000;

    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.from('user_alert_preferences').upsert(
        {
          'user_id': user.id,
          'enable_mechanical_alerts': _enableMechanicalAlerts,
          'enable_financial_alerts': _enableFinancialAlerts,
          'mileage_threshold_km': mileageThreshold,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Preferências de alertas salvas com sucesso!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      debugPrint('--- ERRO AO SALVAR PREFERÊNCIAS: $error ---');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar preferências: ${error.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Alertas Preventivos',
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
                  color: primaryColor,
                ),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card Informativo
                      _buildInfoBanner(theme, primaryColor),
                      const SizedBox(height: 24),

                      // Seção: Tipos de Alerta
                      Text(
                        'Notificações Ativas',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildAlertTogglesCard(theme, primaryColor),
                      const SizedBox(height: 28),

                      // Seção: Margem de Antecedência
                      Text(
                        'Sensibilidade e Antecedência',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildMileageThresholdCard(theme, primaryColor),
                      const SizedBox(height: 36),

                      // Botão Salvar Preferências
                      _buildSaveButton(theme, primaryColor),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Banner com visual moderno explicando a finalidade dos alertas preditivos.
  Widget _buildInfoBanner(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF232634),
            Color(0xFF161720),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Monitoramento Inteligente',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Receba avisos automáticos antes de atingir as revisões e quando houver variações anormais de gastos.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Card contendo os controles SwitchListTile para alertas mecânicos e financeiros.
  Widget _buildAlertTogglesCard(ThemeData theme, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2028),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Switch Alertas Mecânicos
            SwitchListTile.adaptive(
              value: _enableMechanicalAlerts,
              activeThumbColor: primaryColor,
              activeTrackColor: primaryColor.withValues(alpha: 0.35),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _enableMechanicalAlerts
                      ? primaryColor.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.build_circle_outlined,
                  color: _enableMechanicalAlerts ? primaryColor : Colors.grey[400],
                  size: 24,
                ),
              ),
              title: const Text(
                'Alertas Mecânicos',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Troca de óleo, pastilhas de freio, filtros e revisões periódicas programadas.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _enableMechanicalAlerts = value;
                });
              },
            ),
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: Colors.white.withValues(alpha: 0.05),
            ),
            // Switch Alertas Financeiros
            SwitchListTile.adaptive(
              value: _enableFinancialAlerts,
              activeThumbColor: primaryColor,
              activeTrackColor: primaryColor.withValues(alpha: 0.35),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _enableFinancialAlerts
                      ? primaryColor.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.attach_money_rounded,
                  color: _enableFinancialAlerts ? primaryColor : Colors.grey[400],
                  size: 24,
                ),
              ),
              title: const Text(
                'Alertas Financeiros',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'Picos de gastos com combustível, desvios de consumo médio e projeções mensais.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _enableFinancialAlerts = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Card para configuração do campo numérico de antecedência em km.
  Widget _buildMileageThresholdCard(ThemeData theme, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2028),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.speed_rounded,
                color: primaryColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Margem de Antecedência',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Defina quantos quilômetros antes do prazo você deseja ser avisado sobre uma manutenção.',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),

          // Campo de Texto Numérico
          TextFormField(
            controller: _mileageThresholdController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              labelText: 'Antecedência (km)',
              hintText: 'Ex: 1000',
              prefixIcon: const Icon(Icons.av_timer_rounded),
              suffixText: 'km',
              suffixStyle: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Informe a antecedência em km.';
              }
              final km = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
              if (km == null || km <= 0) {
                return 'Informe um valor maior que zero.';
              }
              if (km > 50000) {
                return 'Margem máxima recomendada de 50.000 km.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Sugestões de Atalhos Rápidos
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickPresetChip('500 km', '500', primaryColor),
                const SizedBox(width: 8),
                _buildQuickPresetChip('1.000 km (Padrão)', '1000', primaryColor),
                const SizedBox(width: 8),
                _buildQuickPresetChip('2.000 km', '2000', primaryColor),
                const SizedBox(width: 8),
                _buildQuickPresetChip('5.000 km', '5000', primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Chip interativo para facilitar a escolha rápida de quilometragens comuns.
  Widget _buildQuickPresetChip(String label, String value, Color primaryColor) {
    final isSelected = _mileageThresholdController.text == value;

    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? const Color(0xFF121316) : Colors.grey[300],
      ),
      backgroundColor: isSelected
          ? primaryColor
          : const Color(0xFF242731),
      side: BorderSide(
        color: isSelected
            ? primaryColor
            : Colors.white.withValues(alpha: 0.05),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      onPressed: () {
        setState(() {
          _mileageThresholdController.text = value;
        });
      },
    );
  }

  /// Botão Moderno de Salvar Preferências no padrão StadiumBorder do app.
  Widget _buildSaveButton(ThemeData theme, Color primaryColor) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveAlertPreferences,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF121316),
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.5),
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: _isSaving
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
                  Icon(Icons.save_rounded, color: Color(0xFF121316)),
                  SizedBox(width: 8),
                  Text('Salvar Preferências'),
                ],
              ),
      ),
    );
  }
}
