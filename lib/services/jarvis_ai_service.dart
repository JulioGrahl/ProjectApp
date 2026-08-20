import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class JarvisAiService {
  // Chave de API lida de forma segura via variável de ambiente (--dart-define=GEMINI_API_KEY=xxx)
  static const String _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static Future<String> generateJarvisInsight({
    required String vehicleName,
    required int mileage,
    required double? averageConsumption,
    required double monthlyExpenses,
  }) async {
    // Verificação de segurança: se a chave estiver vazia, retorna fallback amigável sem estourar erros
    if (_apiKey.isEmpty) {
      debugPrint('--- AVISO: GEMINI_API_KEY não configurada via --dart-define ---');
      if (mileage > 0) {
        final remainingForOil = 10000 - (mileage % 10000);
        return 'Com base na sua quilometragem atual de $mileage km, a próxima troca de óleo está prevista para daqui a $remainingForOil km. Tudo sob controle!';
      }
      return 'Configure a chave GEMINI_API_KEY para ativar os insights inteligentes do Jarvis IA.';
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-3.6-flash',
        apiKey: _apiKey,
      );

      final consumptionStr = averageConsumption != null
          ? '${averageConsumption.toStringAsFixed(1)} km/L'
          : 'sem dados suficientes de abastecimento';

      final prompt = '''
Você é o Jarvis, um assistente de inteligência artificial de elite e consultor automotivo pessoal.
Analise a seguinte telemetria em tempo real do veículo do usuário e gere um conselho ou insight valioso, altamente personalizado e inteligente.

Telemetria do Veículo:
- Veículo: $vehicleName
- Quilometragem Atual: $mileage km
- Consumo Médio Atual: $consumptionStr
- Gastos no Mês Atual: R\$ ${monthlyExpenses.toStringAsFixed(2)}

Regras Estritas de Resposta:
1. Responda em no máximo 2 frases curtas e diretas.
2. Mantenha um tom profissional, altamente inteligente, prestativo e refinado (estilo assistente de elite).
3. Vá direto ao conselho preventivo, econômico ou de manutenção relevante para a quilometragem e consumo informados.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim();

      if (text != null && text.isNotEmpty) {
        return text;
      }
    } catch (error) {
      debugPrint('--- ERRO AO GERAR DICA DO JARVIS (GEMINI): $error ---');
    }

    // Fallback gracioso caso a chamada de API falhe
    if (mileage > 0) {
      final remainingForOil = 10000 - (mileage % 10000);
      return 'Com base na sua quilometragem atual de $mileage km, a próxima troca de óleo está prevista para daqui a $remainingForOil km. Tudo sob controle!';
    }
    return 'Cadastre seu veículo e abastecimentos para receber previsões e alertas inteligentes da IA.';
  }
}