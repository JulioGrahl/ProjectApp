import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/jarvis_ai_service.dart';
import 'package:projectapp/services/vehicle_service.dart';

class _ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;
  bool isTyping;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isTyping = false,
  });
}

class JarvisChatView extends StatefulWidget {
  const JarvisChatView({super.key});

  @override
  State<JarvisChatView> createState() => _JarvisChatViewState();
}

class _JarvisChatViewState extends State<JarvisChatView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  ChatSession? _chatSession;
  Map<String, dynamic>? _vehicle;
  List<Map<String, dynamic>> _maintenances = [];
  double? _averageConsumption;
  double _monthlyExpenses = 0.0;

  bool _isInitLoading = true;
  bool _isGenerating = false;
  StreamSubscription<String>? _streamSubscription;

  final List<String> _quickSuggestions = [
    '🔍 O que inspecionar na km atual?',
    '⛽ Dicas para melhorar o consumo',
    '🔧 Quando trocar a correia dentada?',
    '⚠️ Sintomas de desgaste na embreagem',
    '🛞 Calibragem e rodízio de pneus',
  ];

  @override
  void initState() {
    super.initState();
    VehicleService.activeVehicleNotifier.addListener(_onActiveVehicleChanged);
    _loadVehicleAndInitChat();
  }

  @override
  void dispose() {
    VehicleService.activeVehicleNotifier.removeListener(_onActiveVehicleChanged);
    _streamSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isInitializing = false;
  String? _loadedVehicleId;

  void _onActiveVehicleChanged() {
    final newVehicle = VehicleService.activeVehicleNotifier.value;
    final newId = newVehicle?['id']?.toString();
    if (newId != _loadedVehicleId && mounted) {
      _loadVehicleAndInitChat();
    }
  }

  Future<void> _loadVehicleAndInitChat() async {
    if (_isInitializing) return;
    _isInitializing = true;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isInitLoading = false;
        });
      }
      _isInitializing = false;
      return;
    }

    try {
      // 1. Obtém o veículo ativo da memória local sem relançar VehicleService.loadVehicles() em loop
      final vehicleData = VehicleService.activeVehicleNotifier.value;
      final vehicleId = vehicleData?['id']?.toString();
      _loadedVehicleId = vehicleId;

      List<Map<String, dynamic>> maintenancesData = [];
      List<Map<String, dynamic>> refuelsData = [];

      if (vehicleId != null && vehicleId.isNotEmpty) {
        // 2. Manutenções ESTRITAMENTE do veículo ativo
        final mRes = await Supabase.instance.client
            .from('vehicle_maintenances')
            .select()
            .eq('user_id', user.id)
            .eq('vehicle_id', vehicleId)
            .order('target_mileage', ascending: true);
        maintenancesData = List<Map<String, dynamic>>.from(mRes);

        // 3. Abastecimentos ESTRITAMENTE do veículo ativo
        final rRes = await Supabase.instance.client
            .from('refuels')
            .select()
            .eq('user_id', user.id)
            .eq('vehicle_id', vehicleId)
            .order('odometer', ascending: true);
        refuelsData = List<Map<String, dynamic>>.from(rRes);
      }

      final rList = List<Map<String, dynamic>>.from(refuelsData);
      _calculateMetrics(rList);

      _vehicle = vehicleData;
      _maintenances = List<Map<String, dynamic>>.from(maintenancesData);

      final vehicleName = vehicleData != null
          ? '${vehicleData['brand']} ${vehicleData['model']}'
          : 'Veículo';
      final mileage = (vehicleData?['mileage'] as num?)?.toInt() ?? 0;

      // Cria a sessão de chat contextualizada com o Gemini
      _chatSession = JarvisAiService.createChatSession(
        vehicleName: vehicleName,
        mileage: mileage,
        averageConsumption: _averageConsumption,
        monthlyExpenses: _monthlyExpenses,
        maintenances: _maintenances,
      );

      // Mensagem de boas-vindas inicial do Jarvis (Limpa o histórico anterior para evitar mensagens duplicadas)
      final kmFormatted = mileage > 0 ? '$mileage km' : 'sem km informada';
      final welcomeText = vehicleData != null
          ? 'Olá! Sou o **Jarvis**, seu copiloto mecânico de elite. Estou conectado à telemetria do seu **$vehicleName** ($kmFormatted). Como posso te ajudar hoje?'
          : 'Olá! Sou o **Jarvis**, seu copiloto automotivo. Cadastre seu veículo para que eu possa monitorar a telemetria e auxiliar você em tempo real!';

      _messages.clear();
      _messages.add(
        _ChatMessage(
          text: welcomeText,
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('--- ERRO AO INICIALIZAR CHAT JARVIS: $e ---');
    } finally {
      _isInitializing = false;
      if (mounted) {
        setState(() {
          _isInitLoading = false;
        });
      }
    }
  }

  void _calculateMetrics(List<Map<String, dynamic>> list) {
    if (list.length >= 2) {
      final firstOdometer = (list.first['odometer'] as num?)?.toInt() ?? 0;
      final lastOdometer = (list.last['odometer'] as num?)?.toInt() ?? 0;
      final deltaKm = lastOdometer - firstOdometer;

      double totalLiters = 0.0;
      for (int i = 1; i < list.length; i++) {
        totalLiters += (list[i]['liters'] as num?)?.toDouble() ?? 0.0;
      }

      if (deltaKm > 0 && totalLiters > 0) {
        _averageConsumption = deltaKm / totalLiters;
      }
    }

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
    _monthlyExpenses = totalMonth;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isGenerating) return;

    _streamSubscription?.cancel();
    _textController.clear();

    final userMsg = _ChatMessage(
      text: query,
      isUser: true,
      timestamp: DateTime.now(),
    );

    final jarvisMsg = _ChatMessage(
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      isTyping: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(jarvisMsg);
      _isGenerating = true;
    });

    _scrollToBottom();

    // Se o chat session não estiver disponível (ex: sem API key ou offline), usa fallback local
    if (_chatSession == null) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          jarvisMsg.isTyping = false;
          jarvisMsg.text = _getLocalChatFallback(query);
          _isGenerating = false;
        });
        _scrollToBottom();
      }
      return;
    }

    // Streaming em tempo real com timeout de 20s para o primeiro token
    bool firstChunkReceived = false;
    final timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!firstChunkReceived && mounted && _isGenerating) {
        _streamSubscription?.cancel();
        setState(() {
          jarvisMsg.isTyping = false;
          jarvisMsg.text =
              'Tempo de resposta excedido. A rede ou os servidores do Gemini estão com alta demanda no momento. Por favor, tente perguntar novamente.';
          _isGenerating = false;
        });
        _scrollToBottom();
      }
    });

    try {
      final stream = JarvisAiService.streamChatMessage(
        chatSession: _chatSession!,
        message: query,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          firstChunkReceived = true;
          timeoutTimer.cancel();

          if (mounted) {
            setState(() {
              jarvisMsg.isTyping = false;
              jarvisMsg.text += chunk;
            });
            _scrollToBottom();
          }
        },
        onDone: () {
          timeoutTimer.cancel();
          if (mounted) {
            setState(() {
              jarvisMsg.isTyping = false;
              _isGenerating = false;
            });
            _scrollToBottom();
          }
        },
        onError: (error) {
          timeoutTimer.cancel();
          debugPrint('--- ERRO NO STREAMING DO JARVIS CHAT: $error ---');
          final errStr = error.toString().toLowerCase();
          final isQuota = errStr.contains('429') ||
              errStr.contains('too many requests') ||
              errStr.contains('quota') ||
              errStr.contains('resource_exhausted');

          if (mounted) {
            setState(() {
              jarvisMsg.isTyping = false;
              if (jarvisMsg.text.isEmpty) {
                jarvisMsg.text = isQuota
                    ? '🤖 [Modo Desenvolvedor]: Layout de chat acoplado com sucesso. Aguarde 1 minuto para a cota da API Google resetar.'
                    : 'Houve uma instabilidade temporária na telemetria. Aqui está o conselho de segurança: consulte o manual do proprietário e verifique os fluidos essenciais.';
              }
              _isGenerating = false;
            });
            _scrollToBottom();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      timeoutTimer.cancel();
      debugPrint('--- ERRO AO INICIAR STREAMING: $e ---');
      final errStr = e.toString().toLowerCase();
      final isQuota = errStr.contains('429') ||
          errStr.contains('too many requests') ||
          errStr.contains('quota') ||
          errStr.contains('resource_exhausted');

      if (mounted) {
        setState(() {
          jarvisMsg.isTyping = false;
          if (jarvisMsg.text.isEmpty) {
            jarvisMsg.text = isQuota
                ? '🤖 [Modo Desenvolvedor]: Layout de chat acoplado com sucesso. Aguarde 1 minuto para a cota da API Google resetar.'
                : 'Desculpe, ocorreu um erro ao processar a resposta. Tente novamente em instantes.';
          }
          _isGenerating = false;
        });
        _scrollToBottom();
      }
    }
  }

  String _getLocalChatFallback(String query) {
    final lower = query.toLowerCase();
    final vehicleName = _vehicle != null
        ? '${_vehicle!['brand']} ${_vehicle!['model']}'
        : 'seu veículo';
    final mileage = (_vehicle?['mileage'] as num?)?.toInt() ?? 0;

    if (lower.contains('correia')) {
      return 'Para o **$vehicleName**, a correia dentada deve ser inspecionada a cada 40.000 km e trocada preventivamente antes dos 60.000 km para evitar danos graves ao motor.';
    } else if (lower.contains('consumo') || lower.contains('economizar')) {
      return 'Para otimizar o consumo do **$vehicleName**:\n\n1. Mantenha os pneus calibrados semanalmente.\n2. Troque os filtros de ar e combustível no prazo.\n3. Evite acelerações bruscas e troque as marchas no regime de torque ideal.';
    } else if (lower.contains('embreagem')) {
      return 'Sinais de desgaste na embreagem do **$vehicleName** incluem pedal rígido, dificuldade para engatar a ré ou primeira marcha e trepidação ao arrancar.';
    }

    return 'Com base no odômetro de **$mileage km** do seu **$vehicleName**, mantenha a manutenção preventiva em dia e registre todos os serviços no app para diagnósticos precisos!';
  }

  void _restartChat() {
    setState(() {
      _messages.clear();
      _loadVehicleAndInitChat();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final vehicleTitle = _vehicle != null
        ? '${_vehicle!['brand']} ${_vehicle!['model']}'
        : 'Veículo Conectado';
    final mileage = (_vehicle?['mileage'] as num?)?.toInt() ?? 0;

    return Scaffold(
      extendBody: false,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2028),
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Jarvis • Copiloto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mileage > 0
                            ? '$vehicleTitle • $mileage km'
                            : vehicleTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reiniciar conversa',
            icon: Icon(
              Icons.refresh_rounded,
              color: Colors.grey[400],
              size: 22,
            ),
            onPressed: _isGenerating ? null : _restartChat,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _isInitLoading
            ? Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
            : Column(
                children: [
                  // Lista de Mensagens
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _buildMessageBubble(msg, primaryColor);
                      },
                    ),
                  ),

                  // Chips de sugestão rápida
                  if (!_isGenerating && _messages.length <= 2)
                    Container(
                      height: 42,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _quickSuggestions.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final suggestion = _quickSuggestions[index];
                          return InkWell(
                            onTap: () => _sendMessage(suggestion),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2028),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Text(
                                suggestion,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // Barra de input inferior com margem para flutuar acima do FAB
                  _buildInputBar(primaryColor),
                ],
              ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, Color primaryColor) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: primaryColor,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF2E2B1C)
                    : const Color(0xFF1E2028),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: Border.all(
                  color: isUser
                      ? primaryColor.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: msg.isTyping
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Jarvis analisando...',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  : _formatMessageText(msg.text, isUser),
            ),
          ),
          if (isUser) const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _formatMessageText(String text, bool isUser) {
    // Processamento simples e fluido de Markdown básico (*bold*, bullet points)
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().startsWith('- ') || line.trim().startsWith('• ')) {
          final content = line.trim().substring(2);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(
                    color: Color(0xFFFACC15),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: _parseInlineBold(
                    content,
                    isUser ? Colors.white : Colors.grey[200]!,
                  ),
                ),
              ],
            ),
          );
        }

        if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 3.0),
          child: _parseInlineBold(
            line,
            isUser ? Colors.white : Colors.grey[200]!,
          ),
        );
      }).toList(),
    );
  }

  Widget _parseInlineBold(String text, Color defaultColor) {
    final spans = <TextSpan>[];
    final parts = text.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      final isBold = i % 2 == 1;
      spans.add(
        TextSpan(
          text: parts[i],
          style: TextStyle(
            color: defaultColor,
            fontSize: 14.5,
            height: 1.4,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildInputBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textInputAction: TextInputAction.send,
              onSubmitted: _sendMessage,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF2A2D39),
                hintText: 'Pergunte ao Jarvis sobre seu carro...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(
                    color: primaryColor.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _isGenerating ? Colors.grey[800] : primaryColor,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              onTap: _isGenerating
                  ? null
                  : () => _sendMessage(_textController.text),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(13.0),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: _isGenerating
                      ? Colors.grey[500]
                      : const Color(0xFF121316),
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
