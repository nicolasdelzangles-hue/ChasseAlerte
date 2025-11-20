import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import 'RegisterScreen.dart'; 
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await auth.login(_emailCtrl.text.trim(), _passCtrl.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _error = "Email ou mot de passe incorrect.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Logo à la place du texte ---
              Semantics(
                label: 'ChasseAlerte',
                child: Image.asset(
                  'assets/image/Logo_ChasseAlerte.png', // mets ton fichier ici
                  height: 330,
                  fit: BoxFit.contain,
                  // Si l’image manque, on retombe sur le texte
                  errorBuilder: (_, __, ___) => const Text(
                    'ChasseAlerte',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
  onPressed: () => setState(() => _obscure = !_obscure),
  tooltip: 'Afficher/masquer',
  icon: Image.asset(
    'assets/image/afficher.png', // ← ton image (PNG/SVG* avec fond transparent)
    width: 22,
    height: 22,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
  ),
),
suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),

                ),
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],

              _loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleLogin,
                        child: const Text('Se connecter'),
                      ),
                      
                    ),
                   // import 'register_screen.dart';

// ... là où tu as le bouton "S'inscrire"
TextButton(
  onPressed: () async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte créé, connecte-toi')),
      );
    }
  },
  child: const Text("S'inscrire"),
),

            ],
          ),
        ),
      ),
    );
  }
}
