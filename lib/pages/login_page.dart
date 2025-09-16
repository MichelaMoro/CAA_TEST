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
      // Effettua il login
      UserCredential userCredential = await authService.signInWithEmailandPassword(
        emailController.text,
        passwordController.text,
      );

      // Verifica se l'email è stata confermata
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        // Mostra un messaggio e fai il logout dell'utente
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "L'email non è stata verificata. Controlla la tua casella di posta.",
            ),
          ),
        );

        // Logout immediato
        await FirebaseAuth.instance.signOut();
      } else {
        // Se l'email è verificata, procedi
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Accesso avvenuto con successo!"),
          ),
        );
        // Naviga alla pagina successiva o esegui altre operazioni
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
        // Se vuoi gestire l'eventuale callback per tornare alla login
        Navigator.of(context).pop();
      }, isCalledFromLogin: true)), // Passa true qui
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50], // Colore di sfondo personalizzato
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 50),
                // Icona personalizzata per il login
                Icon(
                  Icons.accessibility_new, // Usa un'icona generica
                  size: 100,
                  color: Colors.blueAccent, // Colore iconica
                ),
                const SizedBox(height: 10),
                const Text(
                  "Bentornato", // Testo del benvenuto
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 25),
                // Campi di input per l'email e la password
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
                // Pulsante per accedere
                MyButton(onTap: signIn, text: "Accedi"),
                const SizedBox(height: 20),
                // Pulsante per accedere con Google
                SignInButton(
                  Buttons.Google,
                  onPressed: signInWithGoogle,
                ),
                const SizedBox(height: 50),
                // Righe per passare alla registrazione
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Non Sei iscritto? Clicca qui'),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: navigateToRegisterPage, // Naviga alla RegisterPage
                      child: const Text(
                        'Registrati ora',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent, // Colore link
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
