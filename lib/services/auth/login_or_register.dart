import 'package:caa_test/pages/login_page.dart';
import 'package:caa_test/pages/register_page.dart';
import 'package:flutter/material.dart';
class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}
class _LoginOrRegisterState extends State<LoginOrRegister> {
  // inizialmente si vuole mostrare la pagina di login
  bool showLoginPage = true;
  // ora si vuole alternare tra la pagina di login e registrazione
  void togglePages() {
    setState(() {
      showLoginPage = !showLoginPage;

    });
  }
  @override
  Widget build(BuildContext context) {
    if(showLoginPage== true) {
      return LoginPage(onTap: togglePages);

    } else {
      return RegisterPage(onTap: togglePages);
    }
  }
}