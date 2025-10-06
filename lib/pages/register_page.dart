import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caa_test/Services/auth/auth_service.dart';
import 'package:caa_test/components/my_button.dart';
import 'package:caa_test/components/my_text_field.dart';
import 'package:flutter_signin_button/flutter_signin_button.dart';
//import 'package:device_preview/device_preview.dart';

class RegisterPage extends StatefulWidget {
  final void Function()? onTap;
  final bool isCalledFromLogin;
  final String? currentUserUid;

  const RegisterPage({
    super.key,
    this.onTap,
    this.isCalledFromLogin = false,
    this.currentUserUid,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final nameController = TextEditingController();
  final surnameController = TextEditingController();
  bool isLoading = false;
  bool isTutor = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    nameController.dispose();
    surnameController.dispose();
    super.dispose();
  }

  void signUp() async {
    if (nameController.text.isEmpty || surnameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nome e Cognome sono obbligatori")),
      );
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le password non coincidono")),
      );
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      setState(() => isLoading = true);

      User? tutorUser = FirebaseAuth.instance.currentUser;
      String? tutorEmail = tutorUser?.email;
      String? tutorPassword = passwordController.text;

      await authService.signUpWithEmailandPassword(
        emailController.text,
        passwordController.text,
      );

      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final firestore = FirebaseFirestore.instance;

        final userDoc = {
          'email': emailController.text,
          'nome': nameController.text,
          'cognome': surnameController.text,
          'Tutore': widget.isCalledFromLogin ? (isTutor == true ? true : false) : widget.currentUserUid,
          'BCC': widget.isCalledFromLogin ? false : true,
          'uid': user.uid,
          if (!widget.isCalledFromLogin && widget.currentUserUid != null)
            'allowedContacts': [widget.currentUserUid!],
        };

        if (widget.isCalledFromLogin) {
          userDoc['friendRequestCount'] = 0;
        }

        await firestore.collection('users').doc(user.uid).set(userDoc);

        if (!widget.isCalledFromLogin) {
          DocumentSnapshot tutorDoc = await firestore.collection('users').doc(widget.currentUserUid).get();
          List<String> tutorFriends = List<String>.from(tutorDoc['friends'] ?? []);
          for (String friendId in tutorFriends) {
            await firestore.collection('users').doc(friendId).update({
              'friends': FieldValue.arrayUnion([user.uid]),
            });
          }
          await firestore.collection('users').doc(widget.currentUserUid).update({
            'bccUsers': FieldValue.arrayUnion([user.uid]),
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Registrazione completata! Esegui nuovamente l'accesso.")),
        );

        if (!widget.isCalledFromLogin) {
          emailController.clear();
          passwordController.clear();
          confirmPasswordController.clear();
          nameController.clear();
          surnameController.clear();

          await FirebaseAuth.instance.signOut();
          await authService.signInWithEmailandPassword(tutorEmail!, tutorPassword);
        } else {
          await authService.signOut();
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void signUpWithGoogle() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await authService.signInWithGoogle();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[50],
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
          child: SingleChildScrollView(
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
                  Text(
                    widget.isCalledFromLogin
                        ? "Benvenuto in [nome app]! Prima di iniziare crea il tuo account"
                        : "Aggiungi Persona con BCC",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),
                  MyTextField(
                    controller: nameController,
                    hintText: 'Nome',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),
                  MyTextField(
                    controller: surnameController,
                    hintText: 'Cognome',
                    obscureText: false,
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 10),
                  MyTextField(
                    controller: confirmPasswordController,
                    hintText: 'Conferma la Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  if (widget.isCalledFromLogin)
                    Row(
                      children: [
                        Checkbox(
                          value: isTutor,
                          onChanged: (value) => setState(() => isTutor = value ?? false),
                        ),
                        const Text('Registrati come Tutore'),
                      ],
                    ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: MyButton(onTap: signUp, text: "Registrati"),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: SignInButton(Buttons.Google, onPressed: signUpWithGoogle),
                  ),
                  const SizedBox(height: 20),
                  if (widget.isCalledFromLogin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Sei già Registrato? '),
                        GestureDetector(
                          onTap: widget.onTap,
                          child: const Text(
                            'Accedi qui',
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
