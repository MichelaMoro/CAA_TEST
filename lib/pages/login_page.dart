import 'package:caa_test/Services/auth/auth_service.dart';
import 'package:caa_test/components/my_button.dart';
import 'package:caa_test/components/my_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart'; // Assicurati di importare la RegisterPage

class LoginPage extends StatefulWidget {
  final void Function()? onTap;
  const LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  // Funzione per il login
  void signIn() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      UserCredential userCredential = await authService.signInWithEmailandPassword(
        emailController.text,
        passwordController.text,
      );

      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "L'email non è stata verificata. Controlla la tua casella di posta.",
            ),
          ),
        );
        await FirebaseAuth.instance.signOut();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Accesso avvenuto con successo!"),
          ),
        );
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // Funzione per il login con Google
  void signInWithGoogle() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await authService.signInWithGoogle();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // Naviga alla pagina di registrazione
  void navigateToRegisterPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => RegisterPage(onTap: () {
        Navigator.of(context).pop();
      }, isCalledFromLogin: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView( // previene overflow verticale
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),
                  Icon(
                    Icons.accessibility_new,
                    size: 100,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Bentornato",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 25),
                  MyTextField(
                    controller: emailController,
                    hintText: 'Email',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),
                  MyTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: MyButton(
                      onTap: signIn,
                      text: "Accedi",
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: SignInButton(
                      Buttons.Google,
                      onPressed: signInWithGoogle,
                    ),
                  ),
                  const SizedBox(height: 50),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Non Sei iscritto? Clicca qui'),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: navigateToRegisterPage,
                        child: const Text(
                          'Registrati ora',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
