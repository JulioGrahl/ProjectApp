import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/services/theme_service.dart';
import 'package:projectapp/views/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bhzfnnljawkrxycnsant.supabase.co',
    publishableKey: 'sb_publishable_Y4NMatQE7Xd_VbnSRHT4Lg_HDkIiIkg',
  );

  await ThemeService.init();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const darkBackground = Color(0xFF121316);

    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.accentColor,
      builder: (_, primaryAccent, child) {
        return MaterialApp(
          title: 'Meu Carro Inteligente',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: darkBackground,
            colorScheme: ColorScheme.dark(
              primary: primaryAccent,
              secondary: primaryAccent,
              surface: const Color(0xFF1E2028),
              onPrimary: darkBackground,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF242731),
              labelStyle: TextStyle(color: Colors.grey[400]),
              hintStyle: TextStyle(color: Colors.grey[500]),
              prefixIconColor: Colors.grey[400],
              suffixIconColor: Colors.grey[400],
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: primaryAccent, width: 2),
              ),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}
