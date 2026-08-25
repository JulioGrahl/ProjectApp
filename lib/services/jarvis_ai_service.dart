import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class JarvisAiService {
  // Modelo de produção ativo e estável da API Gemini
  static const String _modelName = 'gemini-3.6-flash';

  // Chave de API lida de forma segura via variável de ambiente (--dart-define=GEMINI_API_KEY=xxx)
  static const String _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Persistência de Modo do Jarvis
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

  /// Salva o modo do Jarvis no SharedPreferences e reseta cache de insights
  static Future<void> setJarvisMode(int mode) async {
    _currentMode = mode;
    clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_jarvisModeKey, mode);
    } catch (e) {
      debugPrint('--- ERRO AO SALVAR MODO DO JARVIS: $e ---');
    }
  }

  // Cache em memória para o insight da Home para evitar chamadas repetidas e erro 429
  static JarvisInsightResult? _cachedHomeInsight;
  static String? _cachedVehicleId;

  /// Limpa o cache em memória (utilizado em Pull to Refresh ou recarga forçada)
  static void clearCache() {
    _cachedHomeInsight = null;
    _cachedVehicleId = null;
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
      final maxTokens = _currentMode == 0 ? 120 : (_currentMode == 2 ? 1000 : 500);

      final systemInstruction = Content.system('''
Você é o Jarvis, um engenheiro mecânico automotivo de elite e copiloto inteligente do motorista.
Sua missão é analisar a telemetria, o histórico de manutenções realizadas e os agendamentos futuros para orientar o motorista com inteligência híbrida preditiva.

$modeDirective

DIRETRIZES FUNDAMENTAIS DO SISTEMA:

1. LÓGICA HÍBRIDA PREDITIVA:
- Se houver registro recente de uma manutenção (ex: óleo trocado aos 50.000 km), calcule o próximo ciclo a partir dessa última execução real (ex: próxima aos 60.000 km).
- Se NÃO houver registro no banco para um componente crítico, avalie a quilometragem atual do odômetro em relação aos marcos de fábrica do modelo ($vehicleName). Exemplo: 50.000 - 60.000 km exige atenção para correia dentada, velas de ignição e fluido de freio.
- Se houver manutenções futuras cadastradas e nenhuma estiver vencida ou próxima, assuma o papel de MONITORAMENTO ATIVO, confirmando que o cronograma está sob controle.

2. NÍVEIS DE ALERTA (nivel_alerta):
- "critico": Alguma manutenção ativa ultrapassou a quilometragem limite.
- "atencao": Alguma manutenção ativa está próxima da quilometragem limite (dentro da margem de antecedência) OU a quilometragem atual atingiu um marco de fábrica sem registro de troca no banco.
- "normal": Todas as manutenções cadastradas estão em dia e não há alertas urgentes de fábrica.

3. PRECISÃO MECÂNICA E TOM CONSULTOR:
- Avalie apenas componentes que de fato existam no motor/modelo do veículo ($vehicleName).
- Seja didático, claro e direto ao ponto. Foque em prevenção de prejuízos e segurança.

4. FORMATO DE RESPOSTA (JSON ESTRITO):
{
  "home_insight": {
    "mensagem_investigativa": "Texto preditivo para a Home (máx 2 frases, focado na telemetria real/marcos de fábrica).",
    "texto_botao_acao": "Texto do botão (ex: 'Ver Alertas Críticos' ou 'Gerenciar Cronograma')",
    "rota_acao_sugerida": "maintenance_form",
    "nivel_alerta": "normal" | "atencao" | "critico"
  },
  "modal_status": {
    "diagnostico_curto": "Diagnóstico ultra-curto de status (máx 8 palavras)."
  }
}
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

      final prompt = '''
DADOS REAIS DO VEÍCULO:
- Veículo: $vehicleName
- Quilometragem Atual: $mileage km
- Consumo Médio: $consumptionStr
- Gastos no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}
- Histórico e Agendamentos no Banco de Dados:
$maintenancesSummary

Analise os dados aplicando a lógica híbrida preditiva (última execução real vs marcos de fábrica) e retorne o JSON com o nível de alerta correspondente.
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

  /// Realiza o parse robusto do JSON retornado pelo Gemini, limpando eventuais marcações markdown.
  static JarvisInsightResult? _parseJsonInsight(String rawText) {
    try {
      String cleanText = rawText.trim();
      if (cleanText.startsWith('```json')) {
        cleanText = cleanText.substring(7);
      } else if (cleanText.startsWith('```')) {
        cleanText = cleanText.substring(3);
      }
      if (cleanText.endsWith('```')) {
        cleanText = cleanText.substring(0, cleanText.length - 3);
      }
      cleanText = cleanText.trim();

      final dynamic decoded = jsonDecode(cleanText);
      if (decoded is Map<String, dynamic>) {
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
      debugPrint('--- ERRO AO FAZER PARSE DO JSON DO GEMINI: $error ---');
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
