import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeOption {
  final String name;
  final Color color;
  final String hex;

  const ThemeOption({
    required this.name,
    required this.color,
    required this.hex,
  });
}

class ThemeService {
  static const String _colorKey = 'app_accent_color_hex';

  /// Cor primária de destaque global (Padrão: Verde Neon #00FF66)
  static final ValueNotifier<Color> accentColor =
      ValueNotifier<Color>(const Color(0xFF00FF66));

  /// Paleta oficial de 5 cores de destaque do First2 / Meu Carro Inteligente
  static const List<ThemeOption> availableThemes = [
    ThemeOption(
      name: 'Verde Neon',
      color: Color(0xFF00FF66),
      hex: '#00FF66',
    ),
    ThemeOption(
      name: 'Roxo Cyber',
      color: Color(0xFFA855F7),
      hex: '#A855F7',
    ),
    ThemeOption(
      name: 'Azul Elétrico',
      color: Color(0xFF3B82F6),
      hex: '#3B82F6',
    ),
    ThemeOption(
      name: 'Rosa Choque',
      color: Color(0xFFEC4899),
      hex: '#EC4899',
    ),
    ThemeOption(
      name: 'Vermelho Pista',
      color: Color(0xFFEF4444),
      hex: '#EF4444',
    ),
  ];

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHex = prefs.getString(_colorKey);
      if (storedHex != null && storedHex.isNotEmpty) {
        accentColor.value = _colorFromHex(storedHex);
      }
    } catch (e) {
      debugPrint('--- ERRO AO CARREGAR TEMA PERSISTIDO: $e ---');
    }
  }

  static Future<void> setAccentColor(Color color) async {
    accentColor.value = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_colorKey, _colorToHex(color));
    } catch (e) {
      debugPrint('--- ERRO AO SALVAR TEMA: $e ---');
    }
  }

  static Color _colorFromHex(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  static String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}
