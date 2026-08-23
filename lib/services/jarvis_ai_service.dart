import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class JarvisHomeInsight {
  final String mensagemInvestigativa;
  final String? textoBotaoAcao;
  final String? rotaAcaoSugerida;

  const JarvisHomeInsight({
    required this.mensagemInvestigativa,
    this.textoBotaoAcao,
    this.rotaAcaoSugerida,
  });

  factory JarvisHomeInsight.fromJson(Map<String, dynamic> json) {
    final botao = json['texto_botao_acao']?.toString().trim();
    final rota = json['rota_acao_sugerida']?.toString().trim();

    return JarvisHomeInsight(
      mensagemInvestigativa:
          json['mensagem_investigativa']?.toString().trim() ?? '',
      textoBotaoAcao: (botao != null && botao.isNotEmpty) ? botao : null,
      rotaAcaoSugerida: (rota != null && rota.isNotEmpty) ? rota : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'mensagem_investigativa': mensagemInvestigativa,
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

  /// Cria uma sessão de chat multi-turno contextualizada com streaming em tempo real
  static ChatSession? createChatSession({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    List<Map<String, dynamic>> maintenances = const [],
  }) {
    if (_apiKey.isEmpty) {
      return null;
    }

    final consumptionStr = averageConsumption != null
        ? '${averageConsumption.toStringAsFixed(1)} km/L'
        : 'sem dados suficientes de abastecimento';

    final maintenancesSummary = maintenances.isEmpty
        ? 'NENHUMA manutenção ou revisão foi cadastrada pelo usuário até o momento no banco de dados.'
        : maintenances.map((m) {
            final title = m['title'] ?? 'Serviço';
            final target = m['target_mileage'] ?? 'N/I';
            final completed = m['is_completed'] == true ? 'Concluída' : 'Pendente';
            return '- $title (Quilometragem Alvo: $target km, Status: $completed)';
          }).join('\n');

    final systemInstruction = Content.system('''
Você é o Jarvis, um engenheiro mecânico automotivo de elite e copiloto inteligente do motorista.
Você está em uma conversa direta via chat com o proprietário do veículo.

CONTEXTO REAL DO VEÍCULO DO USUÁRIO:
- Veículo: $vehicleName
- Quilometragem Atual no Odômetro: $mileage km
- Consumo Médio Registrado: $consumptionStr
- Gastos Totais no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}
- Histórico de Manutenções no Banco de Dados:
$maintenancesSummary

DIRETRIZES FUNDAMENTAIS DO COPILOTO:
1. REGRA ZERO (ANTI-ALUCINAÇÃO):
- NUNCA invente datas, prazos ou manutenções se a lista de manutenções fornecida estiver vazia ou se não houver registro para aquele item.
- Se o usuário perguntar sobre o histórico e não houver registros, informe com clareza e pergunte se ele gostaria de registrar.

2. DIRETIVA DE PRECISÃO MECÂNICA:
- Você é um especialista automotivo rigoroso. Ao cruzar a quilometragem atual com o modelo do veículo, você deve consultar sua base de conhecimento interna para garantir que as peças mencionadas existem de fato naquele motor/modelo específico ($vehicleName).
- NUNCA sugira problemas de tecnologias que o carro não possui (ex: não alerte sobre correia banhada a óleo em um VW Gol).
- Se houver dúvida sobre a motorização exata, limite-se a manutenções universais aplicáveis àquela km.

3. DIRETIVA DE LINGUAGEM E TOM:
- O usuário final pode não ser um especialista em carros. Sua comunicação deve ser acessível, didática, envolvente e com autoridade profissional.
- Aja como um mecânico consultor premium: se precisar usar um termo técnico (ex: corpo de borboleta, pastilha cerâmica, fluido DOT4), traduza o impacto disso para o dia a dia do usuário de forma rápida e prática, focando em segurança, performance e prevenção de gastos.
- Utilize formatação em markdown limpa (parágrafos curtos, bullet points, negrito) para garantir ótima legibilidade no celular.
''');

    final model = GenerativeModel(
      model: _modelName,
      apiKey: _apiKey,
      systemInstruction: systemInstruction,
    );

    return model.startChat();
  }

  /// Transmite a resposta do chat em tempo real token a token
  static Stream<String> streamChatMessage({
    required ChatSession chatSession,
    required String message,
  }) async* {
    final responseStream = chatSession.sendMessageStream(Content.text(message));
    await for (final chunk in responseStream) {
      if (chunk.text != null && chunk.text!.isNotEmpty) {
        yield chunk.text!;
      }
    }
  }

  /// Gera insights investigativos e ações inteligentes cruzando a telemetria com a base mecânica do modelo.
  static Future<JarvisInsightResult> generateJarvisInsight({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
    List<Map<String, dynamic>> maintenances = const [],
  }) async {
    // Verificação de segurança: se a chave estiver vazia, retorna fallback contextual mecânico
    if (_apiKey.isEmpty) {
      debugPrint(
        '--- AVISO: GEMINI_API_KEY não configurada via --dart-define. Utilizando fallback local. ---',
      );
      return _generateLocalFallback(
        vehicleName: vehicleName,
        mileage: mileage,
        averageConsumption: averageConsumption,
        monthlyExpenses: monthlyExpenses,
        maintenances: maintenances,
      );
    }

    try {
      final systemInstruction = Content.system('''
Você é o Jarvis, um engenheiro mecânico automotivo de elite e copiloto inteligente do motorista.
Sua missão é analisar a telemetria e o estado real do banco de dados para orientar o motorista com precisão de fábrica e ações claras.

DIRETRIZES FUNDAMENTAIS DO SISTEMA:

1. REGRA ZERO (ANTI-ALUCINAÇÃO):
- NUNCA invente datas, prazos ou quilometragens para manutenções se a lista de manutenções fornecida estiver vazia ou se não houver registro para aquele item.
- Não invente previsões matemáticas arbitrárias (ex: não diga "troca de óleo em 629 km" apenas para arredondar km se o usuário não cadastrou a última troca).

2. DIRETIVA DE PRECISÃO MECÂNICA:
- Você é um especialista automotivo rigoroso. Ao cruzar a quilometragem atual com o modelo do veículo, você deve consultar sua base de conhecimento interna para garantir que as peças mencionadas existem de fato naquele motor/modelo específico.
- NUNCA sugira problemas de tecnologias que o carro não possui (ex: não alerte sobre correia banhada a óleo em um VW Gol, pois ele não utiliza esse sistema).
- Se houver dúvida sobre a motorização, limite-se a manutenções universais aplicáveis àquela km.

3. DIRETIVA DE LINGUAGEM E TOM:
- O usuário final pode não ser um especialista em carros. Sua comunicação deve ser acessível, didática e envolvente, mas sem perder a autoridade profissional.
- Não infantilize a resposta.
- Aja como um mecânico consultor premium: se precisar usar um termo técnico (ex: corpo de borboleta), traduza o impacto disso para o dia a dia do usuário de forma rápida e prática, focando em segurança, performance e prevenção de gastos.

4. INTERATIVIDADE E CALL-TO-ACTION:
- Sempre sugira uma ação clara no botão para o usuário atualizar o sistema e preencher lacunas de dados no banco (ex: "Informar Manutenção Realizada").

5. FORMATO DE RESPOSTA (JSON ESTRITO):
- Responda OBRIGATORIAMENTE em JSON válido seguindo exatamente o schema abaixo:
{
  "home_insight": {
    "mensagem_investigativa": "Texto investigativo para a Home (máx 2 frases, didático, focado na engenharia do modelo e km).",
    "texto_botao_acao": "Texto conciso para o botão de ação (ex: 'Informar Manutenção Realizada')",
    "rota_acao_sugerida": "maintenance_form"
  },
  "modal_status": {
    "diagnostico_curto": "Diagnóstico ultra-curto focado na prontidão dos dados e saúde do sistema (máx 8 a 10 palavras)."
  }
}
''');

      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        systemInstruction: systemInstruction,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      final consumptionStr = averageConsumption != null
          ? '${averageConsumption.toStringAsFixed(1)} km/L'
          : 'sem dados suficientes de abastecimento';

      final maintenancesSummary = maintenances.isEmpty
          ? 'NENHUMA manutenção ou revisão foi cadastrada pelo usuário até o momento no banco de dados.'
          : maintenances.map((m) {
              final title = m['title'] ?? 'Serviço';
              final target = m['target_mileage'] ?? 'N/I';
              final completed = m['is_completed'] == true ? 'Concluída' : 'Pendente';
              return '- $title (Quilometragem Alvo: $target km, Status: $completed)';
            }).join('\n');

      final prompt = '''
DADOS REAIS DO VEÍCULO:
- Veículo: $vehicleName
- Quilometragem Atual: $mileage km
- Consumo Médio: $consumptionStr
- Gastos no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}
- Histórico de Manutenções Cadastradas no Banco de Dados:
$maintenancesSummary

Analise a telemetria acima aplicando as diretrizes de precisão mecânica, tom acessível de consultor premium e o formato JSON exigido.
''';

      final response = await model.generateContent([
        Content.text(prompt),
      ]).timeout(const Duration(seconds: 20));

      final rawText = response.text?.trim();

      if (rawText != null && rawText.isNotEmpty) {
        final parsedResult = _parseJsonInsight(rawText);
        if (parsedResult != null) {
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
    return _generateLocalFallback(
      vehicleName: vehicleName,
      mileage: mileage,
      averageConsumption: averageConsumption,
      monthlyExpenses: monthlyExpenses,
      maintenances: maintenances,
    );
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

          return JarvisInsightResult(
            homeInsight: JarvisHomeInsight(
              mensagemInvestigativa: mensagem,
              textoBotaoAcao: (botao != null && botao.isNotEmpty) ? botao : null,
              rotaAcaoSugerida: (rota != null && rota.isNotEmpty) ? rota : 'maintenance_form',
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
      if (maintenances.isEmpty) {
        String itensCriticos = 'correia dentada, embreagem e fluido de freio';
        if (mileage >= 50000 && mileage <= 75000) {
          itensCriticos = 'correia dentada, velas de ignição e o conjunto de embreagem';
        } else if (mileage < 30000) {
          itensCriticos = 'óleo sintético, filtros e alinhamento de suspensão';
        } else if (mileage > 80000) {
          itensCriticos = 'sistema de arrefecimento, bomba d\'água e amortecedores';
        }

        return JarvisInsightResult(
          homeInsight: JarvisHomeInsight(
            mensagemInvestigativa:
                'Com o seu $vehicleName aos $mileage km, itens como $itensCriticos exigem inspeção de fábrica. Como está o seu histórico?',
            textoBotaoAcao: 'Informar Manutenção Realizada',
            rotaAcaoSugerida: 'maintenance_form',
          ),
          modalStatus: const JarvisModalStatus(
            diagnosticoCurto:
                'Aguardando alimentação de dados para diagnóstico mecânico preciso.',
          ),
        );
      } else {
        final pending = maintenances
            .where((m) => !(m['is_completed'] as bool? ?? false))
            .toList();

        if (pending.isNotEmpty) {
          final next = pending.first;
          final title = next['title'] ?? 'Revisão';
          final target = (next['target_mileage'] as num?)?.toInt() ?? 0;
          final remaining = target - mileage;

          if (remaining <= 0) {
            return JarvisInsightResult(
              homeInsight: JarvisHomeInsight(
                mensagemInvestigativa:
                    'Alerta para seu $vehicleName: o serviço de $title atingiu o limite de $target km. Recomendamos a revisão imediata.',
                textoBotaoAcao: 'Ver Manutenções',
                rotaAcaoSugerida: 'maintenance_form',
              ),
              modalStatus: JarvisModalStatus(
                diagnosticoCurto: 'Atenção: $title com prazo atingido.',
              ),
            );
          } else {
            return JarvisInsightResult(
              homeInsight: JarvisHomeInsight(
                mensagemInvestigativa:
                    'Telemetria do $vehicleName aos $mileage km. Próximo serviço registrado: $title com meta em $target km ($remaining km restantes).',
                textoBotaoAcao: 'Gerenciar Manutenções',
                rotaAcaoSugerida: 'maintenance_form',
              ),
              modalStatus: JarvisModalStatus(
                diagnosticoCurto: 'Sistemas monitorados. Próximo serviço em $remaining km.',
              ),
            );
          }
        }
      }
    }

    return const JarvisInsightResult(
      homeInsight: JarvisHomeInsight(
        mensagemInvestigativa:
            'Cadastre as manutenções e abastecimentos do seu veículo para que o Jarvis acompanhe os desgastes de fábrica com precisão.',
        textoBotaoAcao: 'Cadastrar Manutenção',
        rotaAcaoSugerida: 'maintenance_form',
      ),
      modalStatus: JarvisModalStatus(
        diagnosticoCurto: 'Aguardando telemetria para diagnóstico.',
      ),
    );
  }
}