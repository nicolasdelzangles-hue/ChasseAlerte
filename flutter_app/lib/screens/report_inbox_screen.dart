import 'package:flutter/material.dart';
import '../services/api_services.dart';

class ReportInboxScreen extends StatefulWidget {
  const ReportInboxScreen({super.key});

  @override
  State<ReportInboxScreen> createState() => _ReportInboxScreenState();
}

class _ReportInboxScreenState extends State<ReportInboxScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiServices.getReports();
      print('=== [INBOX] payload reports ===');
      for (final r in data) {
        print(r);
      }
      if (!mounted) return;
      setState(() {
        _reports = data;
        _loading = false;
      });
    } catch (e) {
      print('=== [INBOX] ERREUR getReports === $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _fmtIncident(dynamic raw) {
    if (raw == null) return 'Non précisé';
    if (raw is String && raw.isEmpty) return 'Non précisé';
    try {
      final d = DateTime.parse(raw.toString());
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final yy = d.year.toString();
      final hh = d.hour.toString().padLeft(2, '0');
      final mi = d.minute.toString().padLeft(2, '0');
      return '$dd/$mm/$yy à $hh:$mi';
    } catch (_) {
      return raw.toString();
    }
  }

  String _yesNo(dynamic v) {
    if (v is bool) return v ? 'Oui' : 'Non';
    if (v is num) return v != 0 ? 'Oui' : 'Non';
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'true' || s == '1') return 'Oui';
      if (s == 'false' || s == '0') return 'Non';
    }
    return 'Non';
  }

  Widget _optionRow(String label, bool value) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Text(
          value ? 'Oui' : 'Non',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: value ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signalements reçus'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? const Center(child: Text('Aucun signalement reçu.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = _reports[index];
                    final reportedFirst = (r['reported_first_name'] ?? '').toString();
                    final reportedLast  = (r['reported_last_name']  ?? '').toString();
                    final fullName = '$reportedFirst $reportedLast'.trim();
                    final category = (r['category'] ?? '').toString();
                    final incident = _fmtIncident(r['incident_at']);

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.report, color: Colors.red),
                        title: Text(
                          fullName.isEmpty ? 'Utilisateur inconnu' : fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('$category • $incident'),
                        onTap: () {
                          final location = (r['location'] ?? '').toString();
                          final desc     = (r['description'] ?? '').toString();

                          final isAnon = _yesNo(r['is_anonymous']) == 'Oui';
                          final muted  = _yesNo(r['muted']) == 'Oui';
                          final blocked= _yesNo(r['blocked']) == 'Oui';

                          // champs optionnels venant du backend (si tu les ajoutes)
                          final reporterName  = (r['reporter_name']  ?? '').toString();
                          final reporterEmail = (r['reporter_email'] ?? '').toString();
                          String? reporterLine;
                          if (reporterName.isNotEmpty && reporterEmail.isNotEmpty) {
                            reporterLine = '$reporterName <$reporterEmail>';
                          } else if (reporterName.isNotEmpty) {
                            reporterLine = reporterName;
                          } else if (reporterEmail.isNotEmpty) {
                            reporterLine = reporterEmail;
                          }

                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              contentPadding: const EdgeInsets.all(20),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Signalement : ${fullName.isEmpty ? 'Utilisateur inconnu' : fullName}',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),

                                  // ======= UTILISATEUR QUI A ÉMIS LE SIGNALEMENT =======
                                  if (reporterLine != null) ...[
                                    Text(
                                      'Signalé par : $reporterLine',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],

                                  // ======= MOTIF / LIEU / DATE =======
                                  Text(
                                    'Motif : $category',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  if (location.isNotEmpty)
                                    Text('Lieu : $location'),
                                  const SizedBox(height: 4),
                                  Text('Date/heure : $incident'),
                                  const SizedBox(height: 12),

                                  // ======= OPTIONS =======
                                  Text(
                                    'Options',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _optionRow(
                                    'Rester anonyme vis-à-vis de l’utilisateur signalé',
                                    isAnon,
                                  ),
                                  const SizedBox(height: 4),
                                  _optionRow(
                                    'Mettre en sourdine cet utilisateur',
                                    muted,
                                  ),
                                  const SizedBox(height: 4),
                                  _optionRow(
                                    'Bloquer cet utilisateur',
                                    blocked,
                                  ),
                                  const SizedBox(height: 12),

                                  // ======= DESCRIPTION =======
                                  Text(
                                    'Description :',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc.isEmpty
                                        ? 'Aucune description fournie.'
                                        : desc,
                                  ),

                                  const SizedBox(height: 20),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Fermer'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
