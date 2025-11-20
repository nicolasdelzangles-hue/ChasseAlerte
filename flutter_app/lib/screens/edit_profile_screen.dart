// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_services.dart';

class EditProfileScreen extends StatefulWidget {
  final User user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _postal;
  late final TextEditingController _city;
  late final TextEditingController _permit;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _first = TextEditingController(text: u.firstName ?? '');
    _last = TextEditingController(text: u.lastName ?? '');
    _name = TextEditingController(text: u.name ?? '');
    _phone = TextEditingController(text: u.phone ?? '');
    _address = TextEditingController(text: u.address ?? '');
    _postal = TextEditingController(text: u.postalCode ?? '');
    _city = TextEditingController(text: u.city ?? '');
    _permit = TextEditingController(text: u.permitNumber ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _postal.dispose();
    _city.dispose();
    _permit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = {
  'first_name': _first.text.trim(),
  'last_name': _last.text.trim(),
  'name': _name.text.trim(),
  'phone': _phone.text.trim(),
  'address': _address.text.trim(),
  'postal_code': _postal.text.trim(),
  'city': _city.text.trim(),
  'permit_number': _permit.text.trim(),
};
await ApiServices.updateProfile(payload);


      final updated = await ApiServices.updateProfile(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour.')),
      );
      Navigator.pop(context, true); // indique à ProfileScreen de recharger
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le profil'),
        backgroundColor: Colors.deepOrange,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _field('Prénom', _first, validator: (v) => null),
            _field('Nom', _last, validator: (v) => null),
            _field('Nom complet', _name),
            _field('Téléphone', _phone,
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Téléphone requis' : null),
            _field('Adresse', _address),
            _field('Code postal', _postal,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Code postal requis' : null),
            _field('Ville', _city),
            _field('N° permis', _permit),
            const SizedBox(height: 12),
            ElevatedButton.icon(
  onPressed: _saving ? null : _save,
  icon: Image.asset(
    'assets/image/edit.png',   // chemin vers ton icône locale
    width: 22,
    height: 22,
  ),
  label: const Text('Enregistrer'),
),

          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? Function(String?)? validator, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }
}
