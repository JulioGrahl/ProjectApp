import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:projectapp/views/login_view.dart';
import 'package:projectapp/views/main_layout.dart';
import 'package:projectapp/views/vehicle_info_view.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://bhzfnnljawkrxycnsant.supabase.co',
      publishableKey: 'sb_publishable_Y4NMatQE7Xd_VbnSRHT4Lg_HDkIiIkg',
    );
  });

  testWidgets('LoginView initial render test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginView(),
      ),
    );

    expect(find.text('Meu Carro Inteligente'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Acessar meu veículo'), findsOneWidget);
    expect(find.textContaining('Cadastre-se'), findsOneWidget);
  });

  testWidgets('Navigation from LoginView to RegisterView and back', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginView(),
      ),
    );

    // Tap Cadastre-se link
    await tester.tap(find.textContaining('Cadastre-se'));
    await tester.pumpAndSettle();

    // Verify RegisterView is rendered
    expect(find.text('Criar minha conta'), findsOneWidget);
    expect(find.text('Nome'), findsOneWidget);
    expect(find.text('Confirmar Senha'), findsOneWidget);
    expect(find.text('Cadastrar'), findsOneWidget);

    final facaLoginFinder = find.textContaining('Faça login');
    expect(facaLoginFinder, findsOneWidget);

    // Scroll to link and tap it to return
    await tester.ensureVisible(facaLoginFinder);
    await tester.tap(facaLoginFinder);
    await tester.pumpAndSettle();

    // Verify back on LoginView
    expect(find.text('Meu Carro Inteligente'), findsOneWidget);
  });

  testWidgets('MainLayout tabs navigation test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainLayout(),
      ),
    );

    // HomeView initially visible
    expect(find.textContaining('Olá'), findsOneWidget);

    // Tap Veículo tab
    await tester.tap(find.text('Veículo'));
    await tester.pumpAndSettle();
    expect(find.text('Meu Veículo'), findsOneWidget);

    // Tap Conta tab
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    expect(find.text('Minha Conta'), findsOneWidget);
    expect(find.text('Sair da conta'), findsOneWidget);
  });

  testWidgets('VehicleInfoView bottom sheet modal test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VehicleInfoView(),
      ),
    );

    expect(find.text('Adicionar meu primeiro veículo'), findsOneWidget);

    // Tap button to open bottom sheet
    await tester.tap(find.text('Adicionar meu primeiro veículo'));
    await tester.pumpAndSettle();

    // Verify modal fields
    expect(find.text('Novo Veículo'), findsOneWidget);
    expect(find.text('Marca (ex: Honda)'), findsOneWidget);
    expect(find.text('Modelo (ex: Civic)'), findsOneWidget);
    expect(find.text('Ano'), findsOneWidget);
    expect(find.text('Quilometragem Atual (km)'), findsOneWidget);
    expect(find.text('Salvar Veículo'), findsOneWidget);

    // Dismiss bottom sheet via barrier tap
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Novo Veículo'), findsNothing);
  });
}
