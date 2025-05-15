
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:menu_web/menu_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDSiavVpnQEFsFa01A0G-4G8tcW10f6Yg0",
      authDomain: "bixmo-5404c.firebaseapp.com",
      projectId: "bixmo-5404c",
      storageBucket: "bixmo-5404c.firebasestorage.app",
      messagingSenderId: "239563696837",
      appId: "1:239563696837:web:137bdcb1021d2a08879eac",
      measurementId: "G-502XDV75ZC",
    ),
  ); 
  runApp(const MenuApp());
}

class MenuApp extends StatelessWidget {
  const MenuApp({super.key});

  @override
  Widget build(BuildContext context) {
    const managerCode = 'MGRYRM'; // Hardcoded managerCode
    debugPrint('Using hardcoded managerCode: $managerCode');
    
    return MaterialApp(
      title: 'Bixmo HMS Menu',
      theme: ThemeData(primarySwatch: Colors.orange),
      debugShowCheckedModeBanner: false,
      home: MenuPage(managerCode: managerCode),
    );
  }
}