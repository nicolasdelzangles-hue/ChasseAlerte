import 'dart:convert';
import 'package:chassealerte/services/api_services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _postal = TextEditingController();
  final _city = TextEditingController();
  final _permit = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;

  // 👉 Adapte l'URL si besoin (3000/3001, IP locale, etc.)
  static const String _registerUrl = '${ApiConfig.baseUrl}/api/register';

  // Normalisation simple FR
  String normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'\s+'), '');
    if (p.startsWith('0')) p = '+33${p.substring(1)}';
    if (!p.startsWith('+')) p = '+33$p';
    return p;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final payload = {
      "first_name": _first.text.trim(),
      "last_name": _last.text.trim(),
      "phone": normalizePhone(_phone.text.trim()),
      "address": _address.text.trim(),
      "postal_code": _postal.text.trim(),
      "city": _city.text.trim(),
      "permit_number": _permit.text.trim(),
      "email": _email.text.trim(),
      "password": _password.text, // (HTTPS + hash côté serveur en prod)
    };

    try {
      final r = await http.post(
        Uri.parse(_registerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(r.body) as Map<String, dynamic>?;
      } catch (_) {
        // si la réponse n'est pas un JSON, on ignore
      }

      if (r.statusCode >= 200 && r.statusCode < 300) {
        // 1) popup succès
        await showDialog(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('Inscription réussie'),
            content: Text('Votre compte a été créé.'),
          ),
        );
        if (!mounted) return;

        // 2) redirection vers la page login (route à déclarer dans MaterialApp)
        Navigator.of(context).pushReplacementNamed('/login');

        // (optionnel) petit message une fois sur /login :
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   ScaffoldMessenger.of(context)
        //       .showSnackBar(const SnackBar(content: Text('Connectez-vous.')));
        // });
      } else {
        final msg = body?['errors'] is List
            ? (body!['errors'] as List).join('\n')
            : (body?['error'] ?? 'Erreur');
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Erreur'),
            content: Text('$msg'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Erreur réseau'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _address.dispose();
    _postal.dispose();
    _city.dispose();
    _permit.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validatePostal(String? v) {
    if (v == null || v.trim().isEmpty) return 'Code postal requis';
    if (!RegExp(r'^\d{5}$').hasMatch(v.trim())) return 'Code postal invalide';
    return null;
  }

  String? _validatePermit(String? v) {
    if (v == null || v.trim().isEmpty) return 'Numéro de permis requis';
    if (!RegExp(r'^[0-9]{14}$').hasMatch(v.trim())) {
      return 'Numéro de permis invalide (14 chiffres attendu)';
    }
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Téléphone requis';
    final p = v.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^(\+33|0)[1-9]\d{8}$').hasMatch(p)) {
      return 'Téléphone français attendu';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inscription')),
      
      body: Padding(
        
        padding: const EdgeInsets.all(16),
      
        child: Form(
          
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Prénom requis' : null,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.givenName],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _last,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nom requis' : null,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.familyName],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                    labelText: 'Téléphone (ex: 0612345678)'),
                keyboardType: TextInputType.phone,
                validator: _validatePhone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Adresse postale'),
                maxLines: 2,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.streetAddressLine1],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _postal,
                      decoration:
                          const InputDecoration(labelText: 'Code postal'),
                      keyboardType: TextInputType.number,
                      validator: _validatePostal,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'Ville'),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.addressCity],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _permit,
                decoration: const InputDecoration(
                    labelText: 'Numéro de permis (14 chiffres)'),
                keyboardType: TextInputType.number,
                validator: _validatePermit,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                decoration:
                    const InputDecoration(labelText: 'Email (optionnel)'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(
                    labelText: 'Mot de passe (optionnel)'),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                
                onPressed: _loading ? null : _submit,
                child: _loading
                
                    ? const SizedBox(
                      
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("S'inscrire"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
