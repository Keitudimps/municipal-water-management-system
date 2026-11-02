import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'draft.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

final ValueNotifier<int> _tab = ValueNotifier(0);

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// The citizen reporting site. On a wide browser it is centred as a phone-width column.
class MobileSite extends StatelessWidget {
  const MobileSite({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFE9EDF3),
        body: LayoutBuilder(
          builder: (context, c) => Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: c.maxWidth < 430 ? c.maxWidth : 430,
              height: c.maxHeight,
              decoration: const BoxDecoration(
                  color: C.bg,
                  border:
                      Border.symmetric(vertical: BorderSide(color: C.line))),
              // Nested navigator keeps pushed pages inside the phone column.
              child: Navigator(
                  onGenerateRoute: (_) =>
                      MaterialPageRoute(builder: (_) => const _Home())),
            ),
          ),
        ),
      );
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _tabReady = false;

  @override
  void initState() {
    super.initState();
    _restoreTab();
  }

  Future<void> _restoreTab() async {
    try {
      final tab = await Api.savedCitizenTab();
      if (mounted) {
        setState(() {
          _tab.value = tab;
          _tabReady = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tabReady = true);
        _snack(context, 'Could not restore your last page: $e');
      }
    }
  }

  Future<void> _selectTab(int tab) async {
    _tab.value = tab;
    try {
      await Api.saveCitizenTab(tab);
    } catch (e) {
      if (mounted) _snack(context, 'Could not save your selected page: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: _tab,
            builder: (_, index, __) => !_tabReady
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    Expanded(
                        child: switch (index) {
                      0 => const CaptureScreen(),
                      1 => const MyReportsScreen(),
                      _ =>
                        const CityReportsScreen(key: ValueKey('city-reports')),
                    }),
                    _BottomNav(index: index, onTap: _selectTab),
                  ]),
          ),
        ),
      );
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final color = index == i ? C.primary : C.muted;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(label, style: ts(12, w: FontWeight.w600, color: color)),
            ]),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: C.line))),
      child: Row(children: [
        item(0, Icons.photo_camera_outlined, 'Report'),
        item(1, Icons.history_rounded, 'My reports'),
        item(2, Icons.location_city_outlined, 'By city'),
      ]),
    );
  }
}

/* ───────────── 1. Capture ───────────── */

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  @override
  void initState() {
    super.initState();
    draft.locate();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (f == null) return;
      draft.setPhoto(await f.readAsBytes(), f.name);
    } catch (_) {
      if (mounted) {
        _snack(
            context, 'Couldn’t open the camera. Try choosing a photo instead.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: draft,
        builder: (context, _) {
          final locSub = draft.hasFix
              ? 'Location found · ±${draft.accuracy?.round() ?? '?'} m'
              : (draft.locating
                  ? 'Finding your location…'
                  : 'Using a default location');
          return Column(children: [
            const TopBar('AquaAlert'),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Text('STEP 1 OF 3',
                    style: ts(12, w: FontWeight.w600, color: C.muted, ls: 1)),
                const SizedBox(height: 8),
                Row(children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                        child: Container(
                            height: 4,
                            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                            decoration: BoxDecoration(
                                color: i == 0 ? C.primary : C.line,
                                borderRadius: BorderRadius.circular(4)))),
                ]),
                const SizedBox(height: 24),
                Text('Capture the leak', style: ts(26, w: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    'Take a clear photo of the water issue. We’ll tag your location for the city crew.',
                    style: ts(15, color: C.muted, h: 1.5)),
                const SizedBox(height: 24),
                _Camera(
                    photo: draft.photo,
                    onShutter: () => _pick(ImageSource.camera),
                    onGallery: () => _pick(ImageSource.gallery)),
                const SizedBox(height: 20),
                Container(
                  decoration: cardDeco(),
                  child: Column(children: [
                    _ReadyRow(
                        Icons.photo_camera_outlined,
                        'Photo',
                        draft.photo != null
                            ? 'Photo ready'
                            : 'Tap the shutter to take a photo',
                        draft.photo != null),
                    const Divider(height: 1, color: C.line),
                    _ReadyRow(Icons.my_location_rounded, 'Location', locSub,
                        draft.hasFix),
                  ]),
                ),
                const SizedBox(height: 28),
                PrimaryButton('Confirm location & photo',
                    icon: Icons.arrow_forward_rounded,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DetailsScreen()))),
                const SizedBox(height: 14),
                Text(
                    'Your photo and location are shared only with city utility services.',
                    textAlign: TextAlign.center,
                    style: ts(12, color: C.muted, h: 1.5)),
              ]),
            ),
          ]);
        },
      );
}

class _Camera extends StatelessWidget {
  final Uint8List? photo;
  final VoidCallback onShutter, onGallery;
  const _Camera(
      {required this.photo, required this.onShutter, required this.onGallery});

  Widget _circle(IconData i, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
                color: Colors.black38, shape: BoxShape.circle),
            child: Icon(i, color: Colors.white, size: 20)),
      );
  Widget _chip(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black45, borderRadius: BorderRadius.circular(20)),
      child: child);
  Widget _dot(Color c) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 340,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(fit: StackFit.expand, children: [
            if (photo != null)
              Image.memory(photo!, fit: BoxFit.cover)
            else
              const Photo(
                  icon: Icons.photo_camera_outlined,
                  colors: [Color(0xFF3B4650), Color(0xFF1F262D)]),
            Positioned(
              top: 16,
              left: 16,
              child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                _dot(
                    photo != null ? const Color(0xFF4ADE80) : Colors.redAccent),
                const SizedBox(width: 6),
                Text(photo != null ? 'Captured' : 'Live',
                    style: ts(12, w: FontWeight.w600, color: Colors.white)),
              ])),
            ),
            if (photo == null)
              Positioned(
                  left: 50,
                  right: 50,
                  top: 80,
                  bottom: 100,
                  child: CustomPaint(painter: _Brackets())),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _circle(Icons.image_outlined, onGallery),
                    GestureDetector(
                      onTap: onShutter,
                      child: Container(
                          width: 68,
                          height: 68,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 3)),
                          child: Container(
                              decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle))),
                    ),
                    _circle(
                        photo != null
                            ? Icons.refresh_rounded
                            : Icons.flip_camera_android_outlined,
                        photo != null ? onShutter : null),
                  ]),
            ),
          ]),
        ),
      );
}

class _Brackets extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const l = 22.0;
    canvas.drawPath(
        Path()
          ..moveTo(0, l)
          ..lineTo(0, 0)
          ..lineTo(l, 0),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(s.width - l, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, l),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(0, s.height - l)
          ..lineTo(0, s.height)
          ..lineTo(l, s.height),
        p);
    canvas.drawPath(
        Path()
          ..moveTo(s.width - l, s.height)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width, s.height - l),
        p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ReadyRow extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final bool ok;
  const _ReadyRow(this.icon, this.title, this.sub, this.ok);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: C.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, color: C.primary, size: 20)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: ts(15, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: ts(13, color: C.muted)),
              ])),
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: ok ? C.green : C.line, size: 22),
        ]),
      );
}

/* ───────────── 2. Details ───────────── */

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  int type = 0, sev = 1;
  bool busy = false;
  String? phoneError;
  final name = TextEditingController(),
      phone = TextEditingController(),
      notes = TextEditingController();

  static const types = [
    (Icons.plumbing_rounded, 'Burst pipe', 'burst_pipe'),
    (Icons.water_drop_outlined, 'Visible leak', 'visible_leak'),
    (Icons.waves_rounded, 'Running water', 'running_water'),
    (Icons.construction_rounded, 'Equipment', 'equipment'),
  ];
  static const levels = [
    ('Minor', '24–48 hours', 'minor'),
    ('Major', '2–4 hours', 'major'),
    ('Emergency', 'under 1 hour', 'emergency')
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill the number used before, so people don't retype it for every report.
    Api.savedPhone().then((p) {
      if (p != null && mounted && phone.text.isEmpty) phone.text = p;
    });
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      setState(() => phoneError =
          'Enter a valid phone number. We use it to link all your reports.');
      return;
    }
    setState(() {
      busy = true;
      phoneError = null;
    });
    try {
      final r = await Api.createReport(
        leakType: types[type].$3,
        severity: levels[sev].$3,
        lat: draft.lat,
        lng: draft.lng,
        phone: phone.text.trim(),
        name: name.text.trim(),
        notes: notes.text.trim(),
        photo: draft.photo,
        photoName: draft.photoName,
      );
      draft.reset();
      await Api.savePhone(phone.text.trim());
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => SuccessScreen(report: r)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      _snack(context, e.message);
    }
  }

  Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 28),
      child: Text(t, style: ts(15, w: FontWeight.w700)));

  OutlineInputBorder _b(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c));

  Widget _field(TextEditingController c, String hint,
          {IconData? icon,
          int lines = 1,
          TextInputType? type,
          String? error}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines,
          keyboardType: type,
          style: ts(15),
          onChanged:
              error == null ? null : (_) => setState(() => phoneError = null),
          decoration: InputDecoration(
            errorText: error,
            errorMaxLines: 2,
            errorBorder: _b(C.red),
            focusedErrorBorder: _b(C.red),
            hintText: hint,
            hintStyle: ts(15, color: C.muted),
            filled: true,
            fillColor: Colors.white,
            prefixIcon:
                icon == null ? null : Icon(icon, size: 20, color: C.muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: _b(C.line),
            enabledBorder: _b(C.line),
            focusedBorder: _b(C.primary),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const TopBar('Report details', back: true),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: cardDeco(),
                    child: Column(children: [
                      SizedBox(
                        height: 150,
                        width: double.infinity,
                        child: draft.photo != null
                            ? Image.memory(draft.photo!, fit: BoxFit.cover)
                            : const Photo(
                                icon: Icons.water,
                                colors: [Color(0xFF9AA8B5), Color(0xFF55616D)]),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(Icons.location_on_rounded,
                              color: C.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Your location',
                                    style: ts(14, w: FontWeight.w600)),
                                Text(fmtCoords(draft.lat, draft.lng),
                                    style: ts(12, color: C.muted)),
                              ])),
                          const Pill('Just now',
                              bg: C.primarySoft, fg: C.primary),
                        ]),
                      ),
                    ]),
                  ),
                  _label('Type of leak'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.7,
                    children: [
                      for (final (i, t) in types.indexed)
                        GestureDetector(
                          onTap: () => setState(() => type = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: type == i ? C.primarySoft : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: type == i ? C.primary : C.line,
                                  width: type == i ? 1.5 : 1),
                            ),
                            child: Row(children: [
                              Icon(t.$1,
                                  size: 20,
                                  color: type == i ? C.primary : C.muted),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(t.$2,
                                      style: ts(14, w: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                  _label('Severity'),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEBEEF2),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      for (final (i, l) in levels.indexed)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => sev = i),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: sev == i
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9)),
                              child: Text(l.$1,
                                  style: ts(14,
                                      w: sev == i
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: sev == i ? C.ink : C.muted)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  _label('Your details'),
                  _field(name, 'Name (optional)',
                      icon: Icons.person_outline_rounded),
                  _field(phone, 'Phone number (required)',
                      icon: Icons.phone_outlined,
                      type: TextInputType.phone,
                      error: phoneError),
                  _field(notes, 'Notes or nearby landmarks', lines: 3),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 14, color: C.muted),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            'Your number lets you find all your reports later. Shared only with City Water Services.',
                            style: ts(12, color: C.muted, h: 1.4))),
                  ]),
                ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: C.line))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  'Priority: ${levels[sev].$1}  ·  Response in ${levels[sev].$2}',
                  style: ts(13, color: C.muted)),
              const SizedBox(height: 12),
              PrimaryButton('Submit report', loading: busy, onTap: _submit),
            ]),
          ),
        ]),
      ),
    );
  }
}

/* ───────────── 3. Success ───────────── */

class SuccessScreen extends StatelessWidget {
  final ReportSummary report;
  const SuccessScreen({super.key, required this.report});

  Widget _row(String l, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: ts(14, color: C.muted)),
          const SizedBox(width: 16),
          Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
        ]),
      );

  Text _val(String t) =>
      Text(t, textAlign: TextAlign.right, style: ts(14, w: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                children: [
                  Center(
                      child: Container(
                          width: 76,
                          height: 76,
                          decoration: const BoxDecoration(
                              color: C.greenSoft, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: C.green, size: 40))),
                  const SizedBox(height: 24),
                  Text('Report submitted',
                      textAlign: TextAlign.center,
                      style: ts(26, w: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                      'Thank you. City officials have received your report and will review it shortly.',
                      textAlign: TextAlign.center,
                      style: ts(15, color: C.muted, h: 1.5)),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: cardDeco(),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Tracking ID',
                                  style: ts(13, color: C.muted)),
                              const SizedBox(height: 4),
                              Text(r.trackingId,
                                  style: ts(22, w: FontWeight.w700, ls: .5)),
                            ])),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded,
                              size: 20, color: C.primary),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: r.trackingId));
                            _snack(context, 'Tracking ID copied');
                          },
                        ),
                      ]),
                      const Divider(height: 28, color: C.line),
                      _row('Issue', _val(r.title)),
                      _row('Location', _val(r.address)),
                      _row('Submitted', _val(fmtWhen(r.createdAt))),
                      _row('Priority', Pill(r.severity)),
                      _row('Expected response', _val(r.eta)),
                    ]),
                  ),
                ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(children: [
              PrimaryButton('Track status', icon: Icons.arrow_forward_rounded,
                  onTap: () {
                _tab.value = 1;
                Navigator.of(context).popUntil((r) => r.isFirst);
              }),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  _tab.value = 0;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Text('Report another leak'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/* ───────────── 4. My reports ───────────── */

IconData _iconFor(String leakType) => switch (leakType) {
      'burst_pipe' => Icons.plumbing_rounded,
      'visible_leak' => Icons.water_drop_outlined,
      'running_water' => Icons.waves_rounded,
      _ => Icons.construction_rounded,
    };

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});
  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class CityReportsScreen extends StatefulWidget {
  const CityReportsScreen({super.key});
  @override
  State<CityReportsScreen> createState() => _CityReportsScreenState();
}

class _CityReportsScreenState extends State<CityReportsScreen> {
  final _city = TextEditingController();
  Future<List<CityReport>>? _results;
  String? _searchedCity;

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  void _search() {
    final city = _city.text.trim();
    if (city.length < 2) {
      _snack(context, 'Enter at least 2 characters for the city.');
      return;
    }
    setState(() {
      _searchedCity = city;
      _results = Api.searchCityReports(city);
    });
  }

  Widget _content(List<CityReport> reports) {
    if (reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Text(
          'No reports have been logged for $_searchedCity yet.',
          textAlign: TextAlign.center,
          style: ts(14, color: C.muted, h: 1.5),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            reports.length == 100
                ? 'Showing the 100 most recent reports in $_searchedCity'
                : '${reports.length} reports in $_searchedCity',
            style: ts(14, w: FontWeight.w600, color: C.muted),
          ),
        ),
        for (final report in reports)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColors(report.severity).$1,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconFor(report.leakType),
                      color: statusColors(report.severity).$2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(report.trackingId,
                              style: ts(12, color: C.muted)),
                        ),
                        Pill(report.status),
                      ]),
                      const SizedBox(height: 4),
                      Text(report.title, style: ts(15, w: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(report.address,
                          style: ts(13, color: C.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(fmtWhen(report.createdAt),
                          style: ts(12, color: C.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Street names are shown for area awareness. Reporter contact details and house numbers are private.',
          style: ts(12, color: C.muted, h: 1.4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const TopBar('Reports by city'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('See reports in your area', style: ts(19, w: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Search by city to see reported leaks and their status.',
                style: ts(13, color: C.muted)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'City name',
                    isDense: true,
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _search,
                tooltip: 'Search city',
                icon: const Icon(Icons.search_rounded),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: _results == null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    const SizedBox(height: 32),
                    const Icon(Icons.map_outlined, size: 44, color: C.muted),
                    const SizedBox(height: 14),
                    Text(
                      'Search a city to see reports logged nearby.',
                      textAlign: TextAlign.center,
                      style: ts(14, color: C.muted),
                    ),
                  ],
                )
              : FutureBuilder<List<CityReport>>(
                  future: _results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text('${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: ts(14, color: C.red)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: _search,
                              child: const Text('Try again')),
                        ],
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [_content(snapshot.data!)],
                    );
                  },
                ),
        ),
      ]);
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  String filter = 'All';
  String? phone; // the number being used; null until the person enters one
  bool ready = false; // finished reading the saved number
  Future<List<ReportSummary>>? _future;
  final input = TextEditingController();
  String? inputError;

  @override
  void initState() {
    super.initState();
    Api.savedPhone().then((p) {
      if (!mounted) return;
      setState(() {
        ready = true;
        phone = p;
        if (p != null) _future = Api.myReports(p);
      });
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _reload() {
    final p = phone;
    if (p != null) setState(() => _future = Api.myReports(p));
  }

  Future<void> _find() async {
    final digits = input.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      setState(
          () => inputError = 'Enter the phone number you used when reporting.');
      return;
    }
    final p = input.text.trim();
    await Api.savePhone(p);
    if (!mounted) return;
    setState(() {
      phone = p;
      inputError = null;
      filter = 'All';
      _future = Api.myReports(p);
    });
  }

  Future<void> _change() async {
    await Api.clearPhone();
    if (!mounted) return;
    setState(() {
      phone = null;
      _future = null;
      filter = 'All';
      input.clear();
    });
  }

  OutlineInputBorder _b(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c));

  Widget _centered(List<Widget> children) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [const SizedBox(height: 80), ...children],
      );

  /// Shown until the report lookup number is entered.
  Widget _gate() => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        Center(
            child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: C.primarySoft, shape: BoxShape.circle),
                child: const Icon(Icons.phone_iphone_rounded,
                    color: C.primary, size: 30))),
        const SizedBox(height: 20),
        Text('Find your reports',
            textAlign: TextAlign.center, style: ts(24, w: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
            'Enter the phone number you reported with. We’ll show every report linked to it, including ones sent from other devices.',
            textAlign: TextAlign.center,
            style: ts(15, color: C.muted, h: 1.5)),
        const SizedBox(height: 24),
        TextField(
          controller: input,
          keyboardType: TextInputType.phone,
          style: ts(15),
          onSubmitted: (_) => _find(),
          onChanged: (_) {
            if (inputError != null) setState(() => inputError = null);
          },
          decoration: InputDecoration(
            hintText: 'Phone number',
            hintStyle: ts(15, color: C.muted),
            filled: true,
            fillColor: Colors.white,
            prefixIcon:
                const Icon(Icons.phone_outlined, size: 20, color: C.muted),
            errorText: inputError,
            errorMaxLines: 2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: _b(C.line),
            enabledBorder: _b(C.line),
            focusedBorder: _b(C.primary),
            errorBorder: _b(C.red),
            focusedErrorBorder: _b(C.red),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton('Show my reports', onTap: _find),
        const SizedBox(height: 14),
        Text(
            'Use your own number. Anyone who knows a number can look up its reports.',
            textAlign: TextAlign.center,
            style: ts(12, color: C.muted, h: 1.5)),
      ]);

  Widget _list(List<ReportSummary> all) {
    final counts = <String, int>{};
    for (final r in all) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }
    if (filter != 'All' && !counts.containsKey(filter)) filter = 'All';
    final rows =
        all.where((r) => filter == 'All' || r.status == filter).toList();
    final chips = ['All', ...counts.keys];

    return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: C.muted),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Reports linked to your saved number',
                    style: ts(13, w: FontWeight.w600, color: C.muted),
                    overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: _change, child: const Text('Change number')),
          ]),
          const SizedBox(height: 4),
          Text('${all.length} ${all.length == 1 ? 'report' : 'reports'}',
              style: ts(22, w: FontWeight.w700)),
          const SizedBox(height: 14),
          if (all.length > 1)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in chips)
                ChoiceChip(
                  label: Text(
                      f == 'All' ? 'All (${all.length})' : '$f (${counts[f]})'),
                  selected: filter == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => filter = f),
                  labelStyle: ts(13,
                      w: FontWeight.w600,
                      color: filter == f ? Colors.white : C.muted),
                  selectedColor: C.primary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: filter == f ? C.primary : C.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
            ]),
          const SizedBox(height: 16),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  'No reports are linked to this number yet. Check the number, or start a new report.',
                  textAlign: TextAlign.center,
                  style: ts(14, color: C.muted, h: 1.5)),
            ),
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: C.primarySoft,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(_iconFor(r.leakType), color: C.primary)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(r.trackingId, style: ts(12, color: C.muted)),
                        const Spacer(),
                        Pill(r.status)
                      ]),
                      const SizedBox(height: 4),
                      Text(r.title, style: ts(16, w: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(r.address,
                          style: ts(13, color: C.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(fmtWhen(r.createdAt), style: ts(12, color: C.muted)),
                    ])),
              ]),
            ),
          const SizedBox(height: 20),
          PrimaryButton('Start new report',
              icon: Icons.add_rounded, onTap: () => _tab.value = 0),
        ]);
  }

  Widget _reports() => RefreshIndicator(
        onRefresh: () async {
          _reload();
          try {
            await _future;
          } catch (_) {}
        },
        child: FutureBuilder<List<ReportSummary>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _centered(
                  const [Center(child: CircularProgressIndicator())]);
            }
            if (snap.hasError) {
              return _centered([
                const Icon(Icons.cloud_off_rounded, size: 40, color: C.muted),
                const SizedBox(height: 16),
                Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: ts(14, color: C.muted, h: 1.5)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton(
                      onPressed: _reload, child: const Text('Try again')),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: _change, child: const Text('Change number')),
                ]),
              ]);
            }
            return _list(snap.data!);
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        const TopBar('My reports'),
        Expanded(
          child: !ready
              ? const Center(child: CircularProgressIndicator())
              : phone == null
                  ? _gate()
                  : _reports(),
        ),
      ]);
}
