import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JarvisHomeInsight {
  final String mensagemInvestigativa;
  final String? textoBotaoAcao;
  final String? rotaAcaoSugerida;
  final String nivelAlerta; // 'normal', 'atencao', 'critico'

  const JarvisHomeInsight({
    required this.mensagemInvestigativa,
    this.textoBotaoAcao,
    this.rotaAcaoSugerida,
    this.nivelAlerta = 'normal',
  });

  factory JarvisHomeInsight.fromJson(Map<String, dynamic> json) {
    final botao = json['texto_botao_acao']?.toString().trim();
    final rota = json['rota_acao_sugerida']?.toString().trim();
    final alerta = json['nivel_alerta']?.toString().trim().toLowerCase();

    return JarvisHomeInsight(
      mensagemInvestigativa:
          json['mensagem_investigativa']?.toString().trim() ?? '',
      textoBotaoAcao: (botao != null && botao.isNotEmpty) ? botao : null,
      rotaAcaoSugerida: (rota != null && rota.isNotEmpty) ? rota : null,
      nivelAlerta: (alerta == 'critico' || alerta == 'atencao') ? alerta! : 'normal',
    );
  }

  Map<String, dynamic> toJson() => {
    'mensagem_investigativa': mensagemInvestigativa,
    'nivel_alerta': nivelAlerta,
    if (textoBotaoAcao != null) 'texto_botao_acao': textoBotaoAcao,
    if (rotaAcaoSugerida != null) 'rota_acao_sugerida': rotaAcaoSugerida,
  };
}

class JarvisModalStatus {
  final String diagnosticoCurto;

  const JarvisModalStatus({
    required this.diagnosticoCurto,
  });

  factory JarvisModalStatus.fromJson(Map<String, dynamic> json) {
    return JarvisModalStatus(
      diagnosticoCurto:
          json['diagnostico_curto']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'diagnostico_curto': diagnosticoCurto,
  };
}

class JarvisInsightResult {
  final JarvisHomeInsight homeInsight;
  final JarvisModalStatus modalStatus;

  const JarvisInsightResult({
    required this.homeInsight,
    required this.modalStatus,
  });

  factory JarvisInsightResult.fromJson(Map<String, dynamic> json) {
    final homeJson = json['home_insight'] as Map<String, dynamic>? ?? {};
    final modalJson = json['modal_status'] as Map<String, dynamic>? ?? {};

    return JarvisInsightResult(
      homeInsight: JarvisHomeInsight.fromJson(homeJson),
      modalStatus: JarvisModalStatus.fromJson(modalJson),
    );
  }

  Map<String, dynamic> toJson() => {
    'home_insight': homeInsight.toJson(),
    'modal_status': modalStatus.toJson(),
  };
}

/// Representa a avaliação do interceptador lógico de eventos do Jarvis (FinOps)
class JarvisTriggerEvaluation {
  final bool shouldTrigger;
  final String? triggerReason;

  const JarvisTriggerEvaluation({
    required this.shouldTrigger,
    this.triggerReason,
  });
}

class JarvisAiService {
  // Modelo de produção ativo e estável da API Gemini
  static const String _modelName = 'gemini-3.6-flash';

  // Chave de API lida de forma segura via variável de ambiente (--dart-define=GEMINI_API_KEY=xxx)
  static const String _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Preferência local de tom do Jarvis
  static const String _jarvisModeKey = 'jarvis_copilot_mode';

  static int _currentMode = 1; // Default: Padrão (1). 0 = Silencioso, 2 = Agressivo

  /// Retorna o modo ativo em memória do Jarvis (0 = Silencioso, 1 = Padrão, 2 = Agressivo)
  static int get currentJarvisMode => _currentMode;

  /// Carrega o modo do Jarvis salvo no SharedPreferences
  static Future<int> loadJarvisMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentMode = prefs.getInt(_jarvisModeKey) ?? 1;
    } catch (e) {
      debugPrint('--- ERRO AO CARREGAR MODO DO JARVIS: $e ---');
    }
    return _currentMode;
  }

  /// Salva o modo do Jarvis no SharedPreferences e reseta cache em memória
  static Future<void> setJarvisMode(int mode) async {
    _currentMode = mode;
    await clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_jarvisModeKey, mode);
    } catch (e) {
      debugPrint('--- ERRO AO SALVAR MODO DO JARVIS: $e ---');
    }
  }

  // Cache volátil em memória RAM para transições instantâneas entre abas
  static JarvisInsightResult? _cachedHomeInsight;
  static String? _cachedVehicleId;

  /// Limpa o cache volátil em memória RAM
  static Future<void> clearCache({String? vehicleId}) async {
    _cachedHomeInsight = null;
    _cachedVehicleId = null;
  }

  /// Cria um JarvisInsightResult a partir dos dados persistidos no Supabase (colunas jarvis_last_insight e jarvis_insight_status)
  static JarvisInsightResult createResultFromDb({
    required String insight,
    String? status,
  }) {
    final cleanStatus = (status ?? 'normal').trim().toLowerCase();
    String alertLevel = 'normal';
    if (cleanStatus == 'alert' || cleanStatus == 'critico' || cleanStatus == 'negative') {
      alertLevel = 'critico';
    } else if (cleanStatus == 'atencao' || cleanStatus == 'warning') {
      alertLevel = 'atencao';
    }

    String diagnostico = 'Telemetria em monitoramento ativo.';
    if (alertLevel == 'critico') {
      diagnostico = 'Alerta crítico de revisão.';
    } else if (alertLevel == 'atencao') {
      diagnostico = 'Atenção aos prazos de revisão.';
    } else if (cleanStatus == 'positive') {
      diagnostico = 'Sistema operacional normal.';
    }

    return JarvisInsightResult(
      homeInsight: JarvisHomeInsight(
        mensagemInvestigativa: insight,
        textoBotaoAcao: 'Ver Alertas Críticos',
        rotaAcaoSugerida: 'maintenance_form',
        nivelAlerta: alertLevel,
      ),
      modalStatus: JarvisModalStatus(
        diagnosticoCurto: diagnostico,
      ),
    );
  }

  /// Avaliador lógico determinístico (FinOps para LLMs).
  /// Avalia se houve eventos ou variações de telemetria que justifiquem acionar a API do Gemini.
  static Future<JarvisTriggerEvaluation> shouldTriggerJarvisInsight({
    required String vehicleId,
    required int currentMileage,
    required double? currentConsumption,
    required int currentRefuelsCount,
    required List<Map<String, dynamic>> maintenances,
    String? lastInsight,
    String? lastInsightStatus,
    bool forceRefresh = false,
  }) async {
    // 0. Recarga manual solicitada pelo usuário (Pull to refresh)
    if (forceRefresh) {
      return const JarvisTriggerEvaluation(
        shouldTrigger: true,
        triggerReason: 'Recarga forçada solicitada manualmente pelo usuário.',
      );
    }

    if (vehicleId.isEmpty) {
      return const JarvisTriggerEvaluation(
        shouldTrigger: false,
        triggerReason: 'Nenhum veículo ativo selecionado.',
      );
    }

    // 1. Ausência de insight prévio no Supabase (Primeiro login / veículo sem insight)
    if (lastInsight == null || lastInsight.trim().isEmpty) {
      return const JarvisTriggerEvaluation(
        shouldTrigger: true,
        triggerReason: 'Primeira análise de telemetria (sem insight no banco de dados).',
      );
    }

    // 2. GATILHO DE REVISÕES: Odômetro atingiu 90% ou ultrapassou a meta de manutenção pendente
    final pendingMaintenances = maintenances
        .where((m) => !(m['is_completed'] as bool? ?? false))
        .toList();

    for (final m in pendingMaintenances) {
      final title = m['title'] ?? 'Revisão';
      final targetMileage = (m['target_mileage'] as num?)?.toInt() ?? 0;

      if (targetMileage > 0) {
        final ninetyPercent = (targetMileage * 0.90).floor();

        if (currentMileage >= ninetyPercent) {
          final isAlreadyAlert = lastInsightStatus == 'alert' ||
              lastInsightStatus == 'critico' ||
              lastInsightStatus == 'atencao';

          if (!isAlreadyAlert) {
            final remaining = targetMileage - currentMileage;
            return JarvisTriggerEvaluation(
              shouldTrigger: true,
              triggerReason: currentMileage >= targetMileage
                  ? 'Manutenção $title atingiu a meta de $targetMileage km.'
                  : 'Odômetro atingiu 90%+ da meta de $title (faltam $remaining km).',
            );
          }
        }
      }
    }

    // 3. Telemetria estável e sem eventos críticos: reutiliza o insight persistido no Supabase
    return const JarvisTriggerEvaluation(
      shouldTrigger: false,
      triggerReason: 'Telemetria estável. Reutilizando insight persistido no banco de dados.',
    );
  }

  /// Ponto de entrada de alto nível para a Home:
  /// Avalia gatilhos com lógica local antes de decidir chamar o Gemini.
  static Future<JarvisInsightResult> getOrGenerateJarvisInsight({
    required String vehicleId,
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    required int refuelsCount,
    List<Map<String, dynamic>> maintenances = const [],
    String? lastInsight,
    String? lastInsightStatus,
    bool forceRefresh = false,
  }) async {
    // 1. Interceptador lógico determinístico
    final evaluation = await shouldTriggerJarvisInsight(
      vehicleId: vehicleId,
      currentMileage: mileage,
      currentConsumption: averageConsumption,
      currentRefuelsCount: refuelsCount,
      maintenances: maintenances,
      lastInsight: lastInsight,
      lastInsightStatus: lastInsightStatus,
      forceRefresh: forceRefresh,
    );

    debugPrint(
        '--- [FINOPS JARVIS GATE] shouldTrigger: ${evaluation.shouldTrigger} | Razão: ${evaluation.triggerReason} ---');

    // 2. Se NÃO houver gatilho e houver insight prévio no Supabase, reutiliza imediatamente com 0 tokens
    if (!evaluation.shouldTrigger && lastInsight != null && lastInsight.trim().isNotEmpty) {
      final dbResult = createResultFromDb(
        insight: lastInsight,
        status: lastInsightStatus,
      );
      _cachedHomeInsight = dbResult;
      _cachedVehicleId = vehicleName;
      return dbResult;
    }

    // 3. Se houver gatilho (ou falta de insight no banco), executa a geração via Gemini
    final result = await generateJarvisInsight(
      vehicleName: vehicleName,
      mileage: mileage,
      averageConsumption: averageConsumption,
      monthlyExpenses: monthlyExpenses,
      maintenances: maintenances,
      forceRefresh: forceRefresh,
      triggerReason: evaluation.triggerReason,
    );

    // 4. Salva o novo insight no Supabase na tabela de veículos (jarvis_last_insight e jarvis_insight_status)
    if (vehicleId.isNotEmpty) {
      try {
        final insightText = result.homeInsight.mensagemInvestigativa;
        final statusText = result.homeInsight.nivelAlerta;

        await Supabase.instance.client
            .from('vehicles')
            .update({
              'jarvis_last_insight': insightText,
              'jarvis_insight_status': statusText,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', vehicleId);

        debugPrint('--- [SUPABASE SYNC] Insight do Jarvis persistido com sucesso para o veículo $vehicleId ---');
      } catch (e) {
        debugPrint('--- ERRO AO SALVAR INSIGHT DO JARVIS NO SUPABASE: $e ---');
      }
    }

    return result;
  }

  /// Retorna a diretiva de personalização e conduta do system prompt baseando-se no modo ativo
  static String _getModePromptDirective(int mode) {
    switch (mode) {
      case 0: // MODO SILENCIOSO (Foco em extrema concisão e economia de cota)
        return '''
[MODO DE OPERAÇÃO: SILENCIOSO]
DIRETRIZES ESTRITAS DE MODO SILENCIOSO:
- Seja ultra-conciso. Sua resposta NUNCA deve ultrapassar 2 LINHAS curtas (máximo 35 palavras).
- Responda EXCLUSIVAMENTE com dados técnicos e mecânicos essenciais solicitados.
- NUNCA inclua saudações, desculpas, apresentações, amenidades ou conversas fiadas. Vá direto ao diagnóstico.
''';
      case 2: // MODO AGRESSIVO / PRO (Foco em diagnóstico minucioso de engenharia e proatividade)
        return '''
[MODO DE OPERAÇÃO: AGRESSIVO (PRO DIAGNÓSTICO DE ELITE)]
DIRETRIZES ESTRITAS DE MODO AGRESSIVO (PRO):
- Aja como um chefe de equipe de corrida e engenheiro mecânico sênior de alta performance.
- Forneça análises mecânicas profundas, listas de verificação (checklists) de inspeção e detalhamento de componentes envolvidos.
- Seja altamente proativo: alerte criticamente sobre riscos ocultos de quebra, fadiga de peças, impactos financeiros de adiar o reparo e orientações técnicas arrojadas.
''';
      case 1: // MODO PADRÃO
      default:
        return '''
[MODO DE OPERAÇÃO: PADRÃO]
DIRETRIZES DE MODO PADRÃO:
- Aja como um copiloto mecânico especialista, prático e consultor amigável.
- Entregue diagnósticos diretos, focando em segurança, prevenção de gastos desnecessários e manutenção preditiva.
''';
    }
  }

  /// Cria uma sessão de chat multi-turno contextualizada com streaming em tempo real
  static ChatSession? createChatSession({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    List<Map<String, dynamic>> maintenances = const [],
    int? customMode,
  }) {
    if (_apiKey.isEmpty) {
      return null;
    }

    final activeMode = customMode ?? _currentMode;
    final modeDirective = _getModePromptDirective(activeMode);

    // Otimização de Tokens: Modo Silencioso restringe maxOutputTokens para 120
    final maxTokens = activeMode == 0 ? 120 : (activeMode == 2 ? 1000 : 500);

    final consumptionStr = averageConsumption != null
        ? '${averageConsumption.toStringAsFixed(1)} km/L'
        : 'sem dados suficientes de abastecimento';

    final maintenancesSummary = maintenances.isEmpty
        ? 'NENHUMA manutenção ou revisão foi cadastrada pelo usuário até o momento no banco de dados.'
        : maintenances.map((m) {
            final title = m['title'] ?? 'Serviço';
            final last = m['last_mileage'] ?? 'N/I';
            final target = m['target_mileage'] ?? 'N/I';
            final completed = m['is_completed'] == true ? 'Concluída' : 'Pendente';
            return '- $title (Última: $last km, Meta: $target km, Status: $completed)';
          }).join('\n');

    final systemInstruction = Content.system('''
Você é o Jarvis, um engenheiro mecânico automotivo de elite e copiloto inteligente do motorista.
Você está em uma conversa direta via chat instantâneo com o proprietário do veículo.

$modeDirective

CONTEXTO REAL DO VEÍCULO DO USUÁRIO:
- Veículo: $vehicleName
- Quilometragem Atual no Odômetro: $mileage km
- Consumo Médio Registrado: $consumptionStr
- Gastos Totais no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}
- Histórico e Agendamentos no Banco de Dados:
$maintenancesSummary

DIRETRIZES OBRIGATÓRIAS DE COMPORTAMENTO:
1. DIRETIVA DE FORMATO: Responda apenas em texto puro. Não use formatação JSON.
2. DIRETIVA DE CHAT ÁGIL: Você está em um chat instantâneo. NUNCA gere introduções, saudações ou repita quem você é. Vá direto ao ponto.
3. DIRETIVA DE TAMANHO E TOKENS: Respeite rigorosamente o limite de extensão do modo ativo.
4. NÃO crie monólogos ou simule raciocínio na resposta final. Entregue apenas o diagnóstico final.
5. REGRA ZERO (ANTI-ALUCINAÇÃO): NUNCA invente datas ou prazos se a lista de manutenções fornecida estiver vazia. Se o usuário já cadastrou uma troca recente de uma peça, calcule o próximo ciclo com base no intervalo real da peça a partir dessa última troca. Se não houver registro, recorra aos marcos de fábrica para o modelo ($vehicleName).
6. DIRETIVA DE PRECISÃO MECÂNICA: Ao cruzar a quilometragem atual com o modelo do veículo, consulte sua base de conhecimento interna para garantir que as peças mencionadas existem de fato naquele motor específico.
''');

    final model = GenerativeModel(
      model: _modelName,
      apiKey: _apiKey,
      systemInstruction: systemInstruction,
      generationConfig: GenerationConfig(
        maxOutputTokens: maxTokens,
      ),
    );

    return model.startChat();
  }

  /// Transmite a resposta do chat em tempo real token a token em texto puro (sem JSON)
  static Stream<String> streamChatMessage({
    required ChatSession chatSession,
    required String message,
  }) async* {
    try {
      final responseStream =
          chatSession.sendMessageStream(Content.text(message));
      await for (final chunk in responseStream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) {
          yield text;
        }
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('429') ||
          errStr.contains('too many requests') ||
          errStr.contains('quota') ||
          errStr.contains('resource_exhausted')) {
        yield '🤖 [Modo Desenvolvedor]: Layout de chat acoplado com sucesso. Aguarde 1 minuto para a cota da API Google resetar.';
        return;
      }
      rethrow;
    }
  }

  /// Gera insights investigativos e ações inteligentes cruzando a telemetria com a base mecânica do modelo.
  static Future<JarvisInsightResult> generateJarvisInsight({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    List<Map<String, dynamic>> maintenances = const [],
    bool forceRefresh = false,
    String? triggerReason,
  }) async {
    // 1. Trava de Cache em Memória: evita chamadas repetidas e protege a cota da API (429)
    if (!forceRefresh && _cachedHomeInsight != null && _cachedVehicleId == vehicleName) {
      return _cachedHomeInsight!;
    }

    // Verificação de segurança: se a chave estiver vazia, retorna fallback contextual mecânico
    if (_apiKey.isEmpty) {
      debugPrint(
        '--- AVISO: GEMINI_API_KEY não configurada via --dart-define. Utilizando fallback local. ---',
      );
      final fallback = _generateLocalFallback(
        vehicleName: vehicleName,
        mileage: mileage,
        averageConsumption: averageConsumption,
        monthlyExpenses: monthlyExpenses,
        maintenances: maintenances,
      );
      _cachedHomeInsight = fallback;
      return fallback;
    }

    try {
      final modeDirective = _getModePromptDirective(_currentMode);
      // Margem mínima de 350 tokens no Silencioso para garantir fechamento correto do JSON
      final maxTokens = _currentMode == 0 ? 350 : (_currentMode == 2 ? 1000 : 500);

      final systemInstruction = Content.system('''
Você é o Jarvis, um engenheiro mecânico automotivo de elite e copiloto inteligente do motorista.
Sua missão é analisar a telemetria, o histórico de manutenções realizadas e os agendamentos futuros para orientar o motorista com inteligência híbrida preditiva.

$modeDirective

DIRETRIZES FUNDAMENTAIS DO SISTEMA:

1. LÓGICA HÍBRIDA PREDITIVA:
- Se houver registro recente de uma manutenção (ex: óleo trocado aos 50.000 km), calcule o próximo ciclo a partir dessa última execução real (ex: próxima aos 60.000 km).
- Se NÃO houver registro no banco para um componente crítico, avalie a quilometragem atual do odômetro em relação aos marcos de fábrica do modelo ($vehicleName). Exemplo: 50.000 - 60.000 km exige atenção para correia dentada, velas de ignição e fluido de freio.
- Se houver manutenções futuras cadastradas e nenhuma estiver vencida ou próxima, assuma o papel de MONITORAMENTO ATIVO, confirmando que o cronograma está sob controle.

2. PRECISÃO MECÂNICA E TOM CONSULTOR:
- Avalie apenas componentes que de fato existam no motor/modelo do veículo ($vehicleName).
- Seja didático, claro e direto ao ponto. Foque em prevenção de prejuízos e segurança (máximo 2 frases objetivas no campo insight).

3. FORMATO DE RESPOSTA (JSON NATIVO OBRIGATÓRIO):
Retorne exclusivamente um objeto JSON neste formato:
{
  "insight": "sua mensagem preditiva aqui (máx 2 frases, focada na telemetria real e marcos mecânicos)",
  "status": "positive" | "neutral" | "negative" | "alert"
}

⚠️ DIRETIVA DE FORMATO INEGOCIÁVEL: Você deve responder ESTRITA e EXCLUSIVAMENTE com o objeto JSON acima. Nunca inclua textos introdutórios, saudações, explicações externas ao JSON ou blocos de formatação markdown como ```json. A primeira e última caractere da sua resposta devem ser, respectivamente, '{' e '}'.
''');

      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        systemInstruction: systemInstruction,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          maxOutputTokens: maxTokens,
        ),
      );

      final consumptionStr = averageConsumption != null
          ? '${averageConsumption.toStringAsFixed(1)} km/L'
          : 'sem dados suficientes de abastecimento';

      final maintenancesSummary = maintenances.isEmpty
          ? 'NENHUMA manutenção ou revisão foi cadastrada pelo usuário até o momento no banco de dados.'
          : maintenances.map((m) {
              final title = m['title'] ?? 'Serviço';
              final last = m['last_mileage'] ?? 'N/I';
              final target = m['target_mileage'] ?? 'N/I';
              final completed = m['is_completed'] == true ? 'Concluída' : 'Pendente';
              return '- $title (Última: $last km, Meta: $target km, Status: $completed)';
            }).join('\n');

      final triggerContext = (triggerReason != null && triggerReason.isNotEmpty)
          ? '\n- GATILHO RECENTE DETECTADO PELA TELEMETRIA: $triggerReason\n'
          : '';

      final prompt = '''
DADOS REAIS DO VEÍCULO:
- Veículo: $vehicleName
- Quilometragem Atual: $mileage km
- Consumo Médio: $consumptionStr
- Gastos no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}
$triggerContext- Histórico e Agendamentos no Banco de Dados:
$maintenancesSummary

Analise os dados aplicando a lógica híbrida preditiva (última execução real vs marcos de fábrica) e retorne o JSON com o insight e o status ("positive", "neutral", "negative" ou "alert").
''';

      final response = await model.generateContent([
        Content.text(prompt),
      ]).timeout(const Duration(seconds: 20));

      final rawText = response.text?.trim();

      if (rawText != null && rawText.isNotEmpty) {
        final parsedResult = _parseJsonInsight(rawText);
        if (parsedResult != null) {
          _cachedHomeInsight = parsedResult;
          _cachedVehicleId = vehicleName;
          return parsedResult;
        }
      }
    } on TimeoutException {
      debugPrint(
        '--- TIMEOUT: A API Gemini demorou mais de 20s para responder. Ativando fallback local. ---',
      );
    } catch (error) {
      debugPrint(
        '--- ERRO AO CONSULTAR GEMINI API ($_modelName): $error. Ativando fallback local. ---',
      );
    }

    // Fallback contextual mecânico caso a chamada falhe por rede, timeout ou oscilação da API
    final fallback = _generateLocalFallback(
      vehicleName: vehicleName,
      mileage: mileage,
      averageConsumption: averageConsumption,
      monthlyExpenses: monthlyExpenses,
      maintenances: maintenances,
    );
    _cachedHomeInsight = fallback;
    _cachedVehicleId = vehicleName;
    return fallback;
  }

  /// Sanitiza e faz o parse robusto do JSON retornado pelo Gemini.
  ///
  /// Aplica múltiplas camadas de limpeza antes de decodificar para blindar contra:
  /// - Blocos de markdown (```json ... ```) em qualquer posição da string
  /// - Texto introdutório antes do objeto JSON
  /// - Respostas truncadas por limite de tokens
  /// - Aspas não escapadas causando SyntaxError no jsonDecode
  static JarvisInsightResult? _parseJsonInsight(String rawText) {
    // ── ETAPA 1: Sanitização Global (Limpeza de String) ──────────────────────
    // Usa replaceAll global para remover TODOS os blocos de markdown, mesmo que
    // estejam embutidos no meio da resposta (não apenas no início/fim).
    String cleanText = rawText
        .replaceAll(RegExp(r'```json', caseSensitive: false), '')
        .replaceAll(RegExp(r'```'), '')
        .trim();

    // ── ETAPA 2: Extração Cirúrgica do Objeto JSON ────────────────────────────
    // Localiza o primeiro '{' e o último '}' para isolar o objeto JSON
    // independentemente de qualquer texto introdutório ou de encerramento da IA.
    final firstBrace = cleanText.indexOf('{');
    final lastBrace = cleanText.lastIndexOf('}');

    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleanText = cleanText.substring(firstBrace, lastBrace + 1);
    }

    // ── ETAPA 3: Decodificação com Try/Catch e Fallback Gracioso ─────────────
    try {
      final dynamic decoded = jsonDecode(cleanText);
      if (decoded is Map<String, dynamic>) {
        // Formato Direto Obrigatório: { "insight": "...", "status": "positive/neutral/negative/alert" }
        if (decoded.containsKey('insight')) {
          final insightText = decoded['insight']?.toString().trim() ?? '';
          final rawStatus = decoded['status']?.toString().trim().toLowerCase() ?? 'normal';

          if (insightText.isNotEmpty) {
            return createResultFromDb(
              insight: insightText,
              status: rawStatus,
            );
          }
        }

        // Formato Estruturado Alternativo: { "home_insight": { ... }, "modal_status": { ... } }
        final homeMap = decoded['home_insight'] as Map<String, dynamic>?;
        final modalMap = decoded['modal_status'] as Map<String, dynamic>?;

        final mensagem = homeMap?['mensagem_investigativa']?.toString().trim();
        final diagnostico = modalMap?['diagnostico_curto']?.toString().trim();

        if (mensagem != null && mensagem.isNotEmpty) {
          final botao = homeMap?['texto_botao_acao']?.toString().trim();
          final rota = homeMap?['rota_acao_sugerida']?.toString().trim();
          final alerta = homeMap?['nivel_alerta']?.toString().trim().toLowerCase();

          return JarvisInsightResult(
            homeInsight: JarvisHomeInsight(
              mensagemInvestigativa: mensagem,
              textoBotaoAcao: (botao != null && botao.isNotEmpty) ? botao : null,
              rotaAcaoSugerida: (rota != null && rota.isNotEmpty) ? rota : 'maintenance_form',
              nivelAlerta: (alerta == 'critico' || alerta == 'atencao') ? alerta! : 'normal',
            ),
            modalStatus: JarvisModalStatus(
              diagnosticoCurto: (diagnostico != null && diagnostico.isNotEmpty)
                  ? diagnostico
                  : 'Telemetria em análise contínua.',
            ),
          );
        }
      }
    } catch (error) {
      // ── DEBUG: Loga o erro e o payload bruto que causou a falha ──────────
      debugPrint('--- [JARVIS PARSE ERROR] FormatException ao decodificar JSON do Gemini ---');
      debugPrint('--- Erro: $error ---');
      debugPrint('--- Payload falho (cleanText): $cleanText ---');
      // NÃO propaga o erro para a UI: retorna null para acionar o fallback local gracioso.
    }
    return null;
  }

  /// Gera uma resposta padrão inteligente e contextualizada baseada nos dados reais e regras de engenharia mecânica.
  static JarvisInsightResult _generateLocalFallback({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    required List<Map<String, dynamic>> maintenances,
  }) {
    if (mileage > 0) {
      final pending = maintenances
          .where((m) => !(m['is_completed'] as bool? ?? false))
          .toList();

      // 1. Verificação de pendências cadastradas (Prioridade Preditiva)
      if (pending.isNotEmpty) {
        Map<String, dynamic>? criticalItem;
        Map<String, dynamic>? warningItem;
        Map<String, dynamic>? nextItem;

        for (final m in pending) {
          final target = (m['target_mileage'] as num?)?.toInt() ?? 0;
          final remaining = target - mileage;
          if (remaining <= 0) {
            criticalItem ??= m;
          } else if (remaining <= 1000) {
            warningItem ??= m;
          } else {
            nextItem ??= m;
          }
        }

        if (criticalItem != null) {
          final title = criticalItem['title'] ?? 'Revisão';
          final target = (criticalItem['target_mileage'] as num?)?.toInt() ?? 0;
          final overdue = (mileage - target).abs();

          return JarvisInsightResult(
            homeInsight: JarvisHomeInsight(
              mensagemInvestigativa: overdue == 0
                  ? 'ALERTA CRÍTICO para seu $vehicleName: o serviço de $title atingiu o limite exato de $target km. Recomendada revisão imediata.'
                  : 'ALERTA CRÍTICO para seu $vehicleName: o serviço de $title ultrapassou $overdue km da meta de $target km. Risco imediato de avaria.',
              textoBotaoAcao: 'RESOLVER REVISÃO URGENTE',
              rotaAcaoSugerida: 'maintenance_form',
              nivelAlerta: 'critico',
            ),
            modalStatus: JarvisModalStatus(
              diagnosticoCurto: 'URGENTE: $title com limite ultrapassado.',
            ),
          );
        }

        if (warningItem != null) {
          final title = warningItem['title'] ?? 'Revisão';
          final target = (warningItem['target_mileage'] as num?)?.toInt() ?? 0;
          final remaining = target - mileage;

          return JarvisInsightResult(
            homeInsight: JarvisHomeInsight(
              mensagemInvestigativa:
                  'Atenção necessária no $vehicleName: $title está a apenas $remaining km da quilometragem limite ($target km).',
              textoBotaoAcao: 'Planejar Manutenção',
              rotaAcaoSugerida: 'maintenance_form',
              nivelAlerta: 'atencao',
            ),
            modalStatus: JarvisModalStatus(
              diagnosticoCurto: 'Atenção: $title próximo da meta ($remaining km).',
            ),
          );
        }

        if (nextItem != null) {
          final title = nextItem['title'] ?? 'Revisão';
          final target = (nextItem['target_mileage'] as num?)?.toInt() ?? 0;
          final remaining = target - mileage;

          return JarvisInsightResult(
            homeInsight: JarvisHomeInsight(
              mensagemInvestigativa:
                  'SISTEMA EM MONITORAMENTO ATIVO: Cronograma do $vehicleName sob controle aos $mileage km. Próxima revisão: $title em $remaining km ($target km).',
              textoBotaoAcao: 'Ver Cronograma Completo',
              rotaAcaoSugerida: 'maintenance_form',
              nivelAlerta: 'normal',
            ),
            modalStatus: JarvisModalStatus(
              diagnosticoCurto: 'Cronograma sob controle. Próxima em $remaining km.',
            ),
          );
        }
      }

      // 2. Sem pendências cadastradas: Avaliação por Marcos de Fábrica do Odômetro
      String itensCriticos = 'óleo do motor, filtro e fluido de freio';
      String nivel = 'normal';

      if (mileage >= 50000 && mileage <= 75000) {
        itensCriticos = 'correia dentada, velas de ignição e fluido de freio';
        nivel = 'atencao';
      } else if (mileage > 75000) {
        itensCriticos = 'sistema de arrefecimento, suspensão e correias de acessórios';
        nivel = 'atencao';
      } else if (mileage >= 30000 && mileage < 50000) {
        itensCriticos = 'pastilhas de freio, velas e filtros de ar/combustível';
      }

      return JarvisInsightResult(
        homeInsight: JarvisHomeInsight(
          mensagemInvestigativa:
              'Aos $mileage km do seu $vehicleName, itens como $itensCriticos exigem inspeção de fábrica. Como está o seu histórico?',
          textoBotaoAcao: 'Cadastrar Histórico de Manutenções',
          rotaAcaoSugerida: 'maintenance_form',
          nivelAlerta: nivel,
        ),
        modalStatus: const JarvisModalStatus(
          diagnosticoCurto:
              'Aguardando agendamento para monitoramento preditivo.',
        ),
      );
    }

    return const JarvisInsightResult(
      homeInsight: JarvisHomeInsight(
        mensagemInvestigativa:
            'Cadastre as manutenções do seu veículo para que o Jarvis acompanhe os desgastes de fábrica com inteligência preditiva.',
        textoBotaoAcao: 'Cadastrar Manutenção',
        rotaAcaoSugerida: 'maintenance_form',
        nivelAlerta: 'normal',
      ),
      modalStatus: JarvisModalStatus(
        diagnosticoCurto: 'Aguardando telemetria para diagnóstico.',
      ),
    );
  }
}
