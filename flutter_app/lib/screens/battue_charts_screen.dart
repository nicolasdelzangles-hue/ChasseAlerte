import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_services.dart';
import '../models/battue.dart';

class BattueChartsScreen extends StatefulWidget {
  final Battue battue;
  const BattueChartsScreen({super.key, required this.battue});

  @override
  State<BattueChartsScreen> createState() => _BattueChartsScreenState();
}

class _BattueChartsScreenState extends State<BattueChartsScreen> {
  String granularity = 'day'; // 'day' ou 'month'
  late Future<Map<String, dynamic>> _future;

  // ---- Controllers legacy (conservés) ----
  final _shotsCtrl = TextEditingController();
  final _seenCtrl = TextEditingController();
  final _hitsCtrl = TextEditingController();
  final _peopleCtrl = TextEditingController();
  final _durCtrl = TextEditingController();
  DateTime _statDate = DateTime.now();

  // ====== Espèce chassée + mini-graph pour la sheet ======
  final List<String> _speciesOptions = [
    'Sanglier', 'Chevreuil', 'Cerf', 'Renard',
    'Lièvre', 'Perdrix', 'Faisan', 'Canard',
    'Oie', 'Bécasse', 'Pigeon', 'Autre',
  ];
  String _species = 'Sanglier';

  // série la plus récente (pour sparkline dans la sheet)
  List<FlSpot> _lastShotsSpots = [];
  Map<int, String> _lastXLabels = {}; // ex: 8 -> "8/11"

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _shotsCtrl.dispose();
    _seenCtrl.dispose();
    _hitsCtrl.dispose();
    _peopleCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  double _numFrom(dynamic v) {
    if (v is num) return v.toDouble();
    final p = num.tryParse(v?.toString() ?? '');
    return (p ?? 0).toDouble();
  }

  double _xFromBucket(dynamic bucket, String gran) {
    if (bucket is num) return bucket.toDouble();
    final s = bucket?.toString() ?? '';
    final d = DateTime.tryParse(s);
    if (d != null) {
      return gran == 'month' ? d.month.toDouble() : d.day.toDouble();
    }
    final p = num.tryParse(s);
    return (p ?? 0).toDouble();
  }

  Future<Map<String, dynamic>> _load() async {
    return ApiServices.getBattueSeries(
      battueId: widget.battue.id!,
      granularity: granularity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(
            tooltip: 'Modifier les stats',
            icon: const Icon(Icons.edit),
            onPressed: _openEditSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          ToggleButtons(
            isSelected: [granularity == 'day', granularity == 'month'],
            onPressed: (i) => setState(() {
              granularity = i == 0 ? 'day' : 'month';
              _future = _load();
            }),
            borderRadius: BorderRadius.circular(20),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Jour')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Mois')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Erreur : ${snap.error}'));
                }

                final data = snap.data ?? {};
                final gran = (data['granularity'] as String?) ?? granularity;

                final List shots = (data['shots'] as List?) ?? const [];
                final List seenHits = (data['seenHits'] as List?) ?? const [];

                // ---------- Courbe "Coups de feu" (points + labels X) ----------
                final shotsSpots = <FlSpot>[];
                final Map<int, String> xLabels = {}; // ex: 8 -> "8/11"

                for (final row in shots) {
                  final bucket = row['bucket'];
                  final s = bucket?.toString() ?? '';
                  final d = DateTime.tryParse(s);

                  late final double x;
                  late final String label;

                  if (d != null) {
                    if (gran == 'month') {
                      x = d.month.toDouble();
                      label = '${d.month}/${d.year % 100}';
                    } else {
                      x = d.day.toDouble();
                      label = '${d.day}/${d.month}';
                    }
                  } else {
                    x = _xFromBucket(bucket, gran);
                    label = s;
                  }

                  xLabels[x.round()] = label;
                  shotsSpots.add(FlSpot(x, _numFrom(row['shots'])));
                }

                shotsSpots.sort((a, b) => a.x.compareTo(b.x));

                // mémorise pour la sheet (sparkline)
                _lastShotsSpots = List<FlSpot>.from(shotsSpots);
                _lastXLabels = Map<int, String>.from(xLabels);

                final minX = shotsSpots.isEmpty
                    ? 0.0
                    : shotsSpots.map((e) => e.x).reduce((a, b) => a < b ? a : b);
                final maxX = shotsSpots.isEmpty
                    ? 0.0
                    : shotsSpots.map((e) => e.x).reduce((a, b) => a > b ? a : b);

                // ---------- Bar chart ----------
                final barGroups = <BarChartGroupData>[];
                for (var i = 0; i < seenHits.length; i++) {
                  final row = seenHits[i];
                  final seen = _numFrom(row['seen']);
                  final hits = _numFrom(row['hits']);
                  barGroups.add(
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: seen,
                          rodStackItems: [
                            BarChartRodStackItem(0, hits, Theme.of(context).colorScheme.primary),
                            BarChartRodStackItem(
                              hits,
                              seen,
                              Theme.of(context).colorScheme.primary.withOpacity(0.35),
                            ),
                          ],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card(
                      'Coups de feu',
                      SizedBox(
                        height: 220,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            minX: minX.floorToDouble(),
                            maxX: maxX.ceilToDouble(),
                            gridData: const FlGridData(show: true),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 36,
                                  getTitlesWidget: (v, _) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 1,
                                  reservedSize: 28,
                                  getTitlesWidget: (value, meta) {
                                    final label = xLabels[value.round()];
                                    if (label == null) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(label, style: const TextStyle(fontSize: 10)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                color: Theme.of(context).colorScheme.primary,
                                spots: shotsSpots,
                                dotData: const FlDotData(show: true),
                                barWidth: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      'Aperçus vs Abattus',
                      SizedBox(
                        height: 240,
                        child: Builder(
                          builder: (context) {
                            final hitColor = Theme.of(context).colorScheme.primary; // abattus
                            final seenColor = hitColor.withOpacity(0.35); // aperçus
                            return BarChart(
                              BarChartData(
                                gridData: const FlGridData(show: true),
                                borderData: FlBorderData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                barGroups: barGroups,
                                barTouchData: BarTouchData(
                                  enabled: true,
                                  touchTooltipData: BarTouchTooltipData(
                                    tooltipBgColor: Colors.black87,
                                    tooltipPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                      final row = seenHits[groupIndex];
                                      final seenV = _numFrom(row['seen']);
                                      final hitsV = _numFrom(row['hits']);
                                      String title = '';
                                      final b = row['bucket']?.toString() ?? '';
                                      final d = DateTime.tryParse(b);
                                      if (d != null) title = '${d.day}/${d.month}\n';

                                      return BarTooltipItem(
                                        title,
                                        const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.w700),
                                        children: [
                                          TextSpan(text: ' \u25CF ',
                                              style: TextStyle(color: hitColor)),
                                          const TextSpan(
                                              text: 'Abattus: ',
                                              style: TextStyle(color: Colors.white)),
                                          TextSpan(
                                              text: '${hitsV.toStringAsFixed(0)}\n',
                                              style: const TextStyle(
                                                  color: Colors.white, fontWeight: FontWeight.w600)),
                                          TextSpan(text: ' \u25CF ',
                                              style: TextStyle(color: seenColor)),
                                          const TextSpan(
                                              text: 'Aperçus: ',
                                              style: TextStyle(color: Colors.white)),
                                          TextSpan(
                                              text: seenV.toStringAsFixed(0),
                                              style: const TextStyle(
                                                  color: Colors.white, fontWeight: FontWeight.w600)),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  // ================== EDIT SHEET ==================

  static const _kTile = Color(0xFF104334);
  static const Color _kAccent = Color(0xFFFD7A1C);

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        DateTime date = _statDate;
        int shots = 0, seen = 0, hits = 0, people = 0;
        double duration = 0;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final sheet = Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 16,
              ),
              child: Material(
                color: const Color(0xFFF6F0F6).withOpacity(.94),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('Mettre à jour les stats',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6D4AFF),
                              side: const BorderSide(color: Color(0xFF6D4AFF)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(date.toLocal().toString().split(' ').first),
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) setLocal(() => date = d);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // --- Espèce chassée ---
                      DropdownButtonFormField<String>(
                        value: _species,
                        decoration: InputDecoration(
                          labelText: 'Type de battue (espèce)',
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: const Color(0xFFEFEAF8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _speciesOptions
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _species = v);
                        },
                      ),
                      const SizedBox(height: 12),

                      // --- Mini graph tendance ---
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F0F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tendance des coups de feu',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Expanded(
                              child: LineChart(
                                LineChartData(
                                  minY: 0,
                                  gridData: const FlGridData(show: true),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        interval: 1,
                                        reservedSize: 20,
                                        getTitlesWidget: (value, meta) {
                                          final lbl = _lastXLabels[value.round()];
                                          return lbl == null
                                              ? const SizedBox.shrink()
                                              : Text(lbl, style: const TextStyle(fontSize: 9));
                                        },
                                      ),
                                    ),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      isCurved: true,
                                      barWidth: 2,
                                      color: Theme.of(context).colorScheme.primary,
                                      dotData: const FlDotData(show: false),
                                      spots: _lastShotsSpots,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ---- Tuiles Compteurs ----
                      _counterTile(
                        title: 'Coups de feu',
                        valueBuilder: () => shots.toString(),
                        onDec: () => setLocal(() => shots = (shots > 0) ? shots - 1 : 0),
                        onInc: () => setLocal(() => shots += 1),
                      ),
                      const SizedBox(height: 10),
                      _counterTile(
                        title: 'Animaux aperçus',
                        valueBuilder: () => seen.toString(),
                        onDec: () => setLocal(() => seen = (seen > 0) ? seen - 1 : 0),
                        onInc: () => setLocal(() => seen += 1),
                      ),
                      const SizedBox(height: 10),
                      _counterTile(
                        title: 'Animaux abattus',
                        valueBuilder: () => hits.toString(),
                        onDec: () => setLocal(() => hits = (hits > 0) ? hits - 1 : 0),
                        onInc: () => setLocal(() => hits += 1),
                      ),
                      const SizedBox(height: 10),
                      _counterTile(
                        title: 'Participants',
                        valueBuilder: () => people.toString(),
                        onDec: () => setLocal(() => people = (people > 0) ? people - 1 : 0),
                        onInc: () => setLocal(() => people += 1),
                      ),
                      const SizedBox(height: 10),
                      _counterTile(
                        title: 'Durée (h)',
                        valueBuilder: () => duration.toStringAsFixed(1),
                        onDec: () => setLocal(
                            () => duration = (duration - 0.5).clamp(0, 999).toDouble()),
                        onInc: () => setLocal(() => duration = (duration + 0.5)),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            ),
                            icon: const Icon(Icons.save),
                            label: const Text('Enregistrer'),
                            onPressed: () async {
                              await _saveStatsFromSheet(
                                date: date,
                                shots: shots,
                                seen: seen,
                                hits: hits,
                                people: people,
                                durationHours: duration,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );

            // Anti-overflow: scroll + hauteur max
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              child: SingleChildScrollView(child: sheet),
            );
          },
        );
      },
    );
  }

  Future<void> _saveStatsFromSheet({
    required DateTime date,
    required int shots,
    required int seen,
    required int hits,
    required int people,
    required double durationHours,
  }) async {
    final payload = {
      'date': date.toIso8601String(),
      'shots': shots,
      'animals_seen': seen,
      'hits': hits,
      'participants': people,
      'duration_hours': durationHours,
      'species': _species, // <— on envoie l’espèce
    };

    try {
      await ApiServices.saveBattueStat(widget.battue.id!, payload);
      if (!mounted) return;
      Navigator.pop(context);
      setState(() {
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stats enregistrées')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  // ---------- UI helpers ----------
  Widget _counterTile({
    required String title,
    required String Function() valueBuilder,
    required VoidCallback onDec,
    required VoidCallback onInc,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kTile,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          _roundIcon(onPressed: onDec, icon: Icons.remove),
          const SizedBox(width: 14),
          Text(valueBuilder(),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(width: 14),
          _roundIcon(onPressed: onInc, icon: Icons.add),
        ],
      ),
    );
  }

  Widget _roundIcon({required VoidCallback onPressed, required IconData icon}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: _kAccent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  // ---------- Ancienne sauvegarde par champs texte (conservée) ----------
  num _parseNum(String? s) => num.tryParse((s ?? '').trim()) ?? 0;

  Future<void> _saveStats() async {
    final payload = {
      'date': _statDate.toIso8601String(),
      'shots': _parseNum(_shotsCtrl.text),
      'animals_seen': _parseNum(_seenCtrl.text),
      'hits': _parseNum(_hitsCtrl.text),
      'participants': _parseNum(_peopleCtrl.text),
      'duration_hours': num.tryParse((_durCtrl.text).trim()) ?? 0,
    };

    try {
      await ApiServices.saveBattueStat(widget.battue.id!, payload);
      if (!mounted) return;
      Navigator.pop(context);
      setState(() {
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stats enregistrées')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }
}
