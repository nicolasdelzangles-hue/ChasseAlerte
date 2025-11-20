import 'package:flutter/material.dart';
import '../services/api_services.dart'; // <-- ajout

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();

  // --- Champs de la personne signalée ---
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _locationCtrl  = TextEditingController();
  DateTime _incidentAt = DateTime.now();

  String _category = 'Comportement dangereux';
  bool _isAnonymous = true;
  bool _mute = false;
  bool _block = false;

  final _categories = const [
    'Comportement dangereux',
    'Harcèlement / insultes',
    'Contenu inapproprié',
    'Usurpation d’identité',
    'Spam / fraude',
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signaler un comportement'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ==== INFORMATIONS DE L’UTILISATEUR SIGNALÉ ====
              Text(
                'Utilisateur à signaler',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Prénom de l’utilisateur signalé',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Le prénom est obligatoire';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom de l’utilisateur signalé',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Le nom est obligatoire';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ==== CATÉGORIES ====
              Text('Motif du signalement', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((c) {
                  final selected = _category == c;
                  return ChoiceChip(
                    label: Text(c),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ==== INFOS INCIDENT ====
              Text("Informations de l'incident",
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),

              // Lieu / Battue (optionnel)
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Lieu / Battue (optionnel)',
                  hintText: 'Ex. Bois de Monfavet, poste 7',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Date (optionnelle)
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _incidentAt,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) {
                    setState(() {
                      _incidentAt = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        _incidentAt.hour,
                        _incidentAt.minute,
                      );
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Date de l'incident (optionnelle)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event),
                  ),
                  child: Text(_fmtDate(_incidentAt)),
                ),
              ),
              const SizedBox(height: 12),

              // Heure (optionnelle)
              InkWell(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_incidentAt),
                  );
                  if (t != null) {
                    setState(() {
                      _incidentAt = DateTime(
                        _incidentAt.year,
                        _incidentAt.month,
                        _incidentAt.day,
                        t.hour,
                        t.minute,
                      );
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Heure de l'incident (optionnelle)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  child: Text(_fmtTime(_incidentAt)),
                ),
              ),
              const SizedBox(height: 24),

              // ==== CONTEXTE ====
              Text('Contexte', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Décrivez ce qu’il s’est passé',
                  hintText:
                      'Expliquez calmement et avec précision la situation.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 30) {
                    return 'Merci d’écrire au moins 30 caractères.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ==== OPTIONS ====
              Text('Options', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                title: const Text(
                    'Rester anonyme vis-à-vis de l’utilisateur signalé'),
              ),
              SwitchListTile(
                value: _mute,
                onChanged: (v) => setState(() => _mute = v),
                title: const Text('Mettre en sourdine cet utilisateur'),
              ),
              SwitchListTile(
                value: _block,
                onChanged: (v) => setState(() => _block = v),
                title: const Text('Bloquer cet utilisateur'),
              ),
              const SizedBox(height: 24),

              // ==== ENVOI ====
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Envoyer la réclamation'),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;

                  try {
                    await ApiServices.postReport(
                      reportedFirstName: _firstNameCtrl.text.trim(),
                      reportedLastName: _lastNameCtrl.text.trim(),
                      category: _category,
                      description: _descCtrl.text.trim(),
                      location: _locationCtrl.text.trim().isEmpty
                          ? null
                          : _locationCtrl.text.trim(),
                      incidentAt: _incidentAt.toIso8601String(),
                      isAnonymous: _isAnonymous,
                      muted: _mute,
                      blocked: _block,
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Réclamation envoyée avec succès.'),
                      ),
                    );
                    Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Erreur lors de l’envoi de la réclamation : $e'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
