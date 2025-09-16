import 'package:caa_test/services/auth/login_or_register.dart';
import 'package:caa_test/pages/home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
class AuthGate extends StatelessWidget{
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
        body:StreamBuilder(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context,snapshot){
              //l'utente è loggato
              if(snapshot.hasData)
              {
                return const HomePage();
              }
              //l'utente non è loggato
              else{
                return const LoginOrRegister();
              }
            }

        )
    );
  }
}