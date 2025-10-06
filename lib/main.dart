import 'package:caa_test/Services/auth/auth_gate.dart';
import 'package:caa_test/Services/auth/auth_service.dart';
import 'package:caa_test/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:caa_test/pages/login_page.dart';
import 'package:caa_test/pages/home_page.dart';
import 'package:caa_test/pages/register_page.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    DevicePreview(
      enabled: !kReleaseMode, // 🔹 Attivo solo in debug
      builder: (context) => ChangeNotifierProvider(
        create: (context) => AuthService(),
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      useInheritedMediaQuery: true, // 🔹 Necessario per DevicePreview
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      initialRoute: '/', // 🔹 Pagina iniziale
      routes: {
        '/': (context) => LoginPage(onTap: () {}),
        '/home': (context) => const HomePage(),
        '/register': (context) => const RegisterPage(),
      },
    );
  }
}
