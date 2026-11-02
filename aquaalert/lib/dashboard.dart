import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

Color _levelColor(String l) => statusColors(l).$2;

class DashboardScreen extends StatefulWidget {
  final DashboardUser user;
  final VoidCallback onLogout;
  const DashboardScreen(
      {super.key, required this.user, required this.onLogout});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Incident> incidents = [];
  Stats stats = const Stats();
  List<ActivityItem> activity = [];
  List<Team> teams = [];
  List<DashboardUser> users = [];
  DateTime? refreshedAt;
  String? selId;
  String query = '';
  bool loading = true;
  String? error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer =
        Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final r = await Future.wait<Object>([
        Api.incidents(q: query),
        Api.stats(),
        Api.activity(),
        Api.teams(),
        Api.users(),
      ]);
      if (!mounted) return;
      setState(() {
        incidents = r[0] as List<Incident>;
        stats = r[1] as Stats;
        activity = r[2] as List<ActivityItem>;
        teams = r[3] as List<Team>;
        users = r[4] as List<DashboardUser>;
        refreshedAt = DateTime.now();
        loading = false;
        error = null;
        if (!incidents.any((i) => i.id == selId)) {
          selId = incidents.isEmpty ? null : incidents.first.id;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (!silent) error = e.message;
      });
    }
  }

  Future<void> _setStatus(Incident inc, String next) async {
    final old = inc.status;
    setState(() => inc.status = next);
    try {
      await Api.updateStatus(inc.id, next);
      _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => inc.status = old);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editOps(Incident inc) async {
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OpsDialog(inc: inc, teams: teams, users: users),
    );
    if (changes == null || changes.isEmpty) return;
    try {
      await Api.updateIncident(inc.id, changes);
      await _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _manageUsers() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ManageStaffDialog(users: users),
    );
    if (changed == true) await _load(silent: true);
  }

  Future<void> _manageTeams() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ManageTeamsDialog(teams: teams),
    );
    if (changed == true) await _load(silent: true);
  }

  Incident? get _selected {
    for (final i in incidents) {
      if (i.id == selId) return i;
    }
    return null;
  }

  Widget _error() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: C.muted),
          const SizedBox(height: 16),
          Text(error ?? 'Something went wrong.', style: ts(15, color: C.muted)),
          const SizedBox(height: 20),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );

  Widget _placeholder() => Container(
        height: 320,
        alignment: Alignment.center,
        decoration: cardDeco(),
        child: Text('No incident selected', style: ts(15, color: C.muted)),
      );
  static const _statuses = ['Received', 'In Progress', 'Delayed', 'Resolved'];
  static const _minWidth = 1040.0;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: ts(12, w: FontWeight.w600, color: C.muted, ls: .8)),
      );

  @override
  Widget build(BuildContext context) {
    final inc = _selected;
    return Scaffold(
      body: Column(children: [
        _TopNav(
          refreshedAt: refreshedAt,
          onRefresh: () => _load(),
          user: widget.user,
          onManageUsers: _manageUsers,
          onManageTeams: _manageTeams,
          onLogout: widget.onLogout,
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? _error()
                  : LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width:
                              c.maxWidth < _minWidth ? _minWidth : c.maxWidth,
                          child: SingleChildScrollView(
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1240),
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(children: [
                                    _Stats(stats),
                                    const SizedBox(height: 24),
                                    Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(width: 320, child: _list()),
                                          const SizedBox(width: 24),
                                          Expanded(
                                              child: inc == null
                                                  ? _placeholder()
                                                  : _detail(inc)),
                                        ]),
                                    const SizedBox(height: 24),
                                    _Feed(activity),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }

  /* ── Left: incident list ── */
  Widget _list() => Container(
        decoration: cardDeco(),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Live incidents',
                      style: ts(16, w: FontWeight.w700))),
              const SizedBox(height: 14),
              TextField(
                style: ts(14),
                onSubmitted: (v) {
                  query = v.trim();
                  _load();
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: ts(14, color: C.muted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: C.muted),
                  filled: true,
                  fillColor: C.bg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ]),
          ),
          if (incidents.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child:
                    Text('No incidents found', style: ts(14, color: C.muted))),
          for (final e in incidents) ...[
            const Divider(height: 1, color: C.line),
            InkWell(
              onTap: () => setState(() => selId = e.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(17, 16, 20, 16),
                decoration: BoxDecoration(
                  color: selId == e.id ? C.primarySoft : null,
                  border: Border(
                      left: BorderSide(
                          color: selId == e.id ? C.primary : Colors.transparent,
                          width: 3)),
                ),
                child: Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: _levelColor(e.level), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style: ts(15, w: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text('${e.address.split(',').first} · ${e.time}',
                              style: ts(13, color: C.muted),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(e.phoneText,
                              style: ts(12, color: C.muted),
                              overflow: TextOverflow.ellipsis),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Pill(e.status),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      );

  /* ── Right: incident detail ── */
  Widget _detail(Incident inc) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                            child: Text(inc.title,
                                style: ts(22, w: FontWeight.w700),
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 12),
                        Pill(inc.status),
                      ]),
                      const SizedBox(height: 6),
                      Text('${inc.id}  ·  ${inc.address}',
                          style: ts(14, color: C.muted),
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                  onPressed: () => _editOps(inc),
                  child: const Text('Update ops')),
              const SizedBox(width: 10),
              inc.status == 'Resolved'
                  ? OutlinedButton(
                      onPressed: () => _setStatus(inc, 'Received'),
                      child: const Text('Reopen'))
                  : FilledButton(
                      onPressed: () => _setStatus(inc, 'Resolved'),
                      child: const Text('Close incident')),
            ]),
          ),
          const Divider(height: 1, color: C.line),

          // Photo + summary
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 260,
                height: 210,
                child: Stack(fit: StackFit.expand, children: [
                  Photo(
                      url: inc.photoUrl,
                      icon: Icons.home_work_outlined,
                      radius: 14),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.location_on_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(inc.coords,
                            style: ts(11,
                                w: FontWeight.w500, color: Colors.white)),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Narrative'),
                      Text(inc.narrativeText,
                          style: ts(15,
                              h: 1.6,
                              color: inc.narrative == null ? C.muted : C.ink)),
                      const SizedBox(height: 20),
                      Row(children: [
                        _metric('Reported', inc.time, compact: true),
                        const SizedBox(width: 10),
                        _metric('Volume loss', inc.volume,
                            recorded: inc.volumeGph != null),
                        const SizedBox(width: 10),
                        _metric('Pressure change', inc.pressure,
                            recorded: inc.pressurePsi != null),
                      ]),
                    ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: C.line),

          // Reporter | Dispatch
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Reporter'),
                      Row(children: [
                        CircleAvatar(
                            radius: 20,
                            backgroundColor: C.primarySoft,
                            child: Text(inc.initial,
                                style: ts(15,
                                    w: FontWeight.w700, color: C.primary))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(inc.reporterText,
                                    style: ts(14,
                                        w: FontWeight.w600,
                                        color: inc.reporter == null
                                            ? C.muted
                                            : C.ink)),
                                Text(inc.phoneText,
                                    style: ts(13, color: C.muted),
                                    overflow: TextOverflow.ellipsis),
                              ]),
                        ),
                      ]),
                    ]),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Assigned team'),
                      Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                                color: C.greenSoft, shape: BoxShape.circle),
                            child: const Icon(Icons.engineering_outlined,
                                size: 20, color: C.green)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(inc.teamLine,
                                    style: ts(14, w: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                                Text(inc.arrivalText,
                                    style: ts(13, color: C.muted),
                                    overflow: TextOverflow.ellipsis),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _label('Assigned to'),
                      Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                                color: C.primarySoft, shape: BoxShape.circle),
                            child: const Icon(Icons.person_outline_rounded,
                                size: 20, color: C.primary)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            inc.assignedUserName == null
                                ? 'No person assigned'
                                : '${inc.assignedUserName} · ${inc.assignedUserNumber}',
                            style: ts(14,
                                w: FontWeight.w600,
                                color: inc.assignedUserName == null
                                    ? C.muted
                                    : C.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ]),
              ),
            ]),
          ),
          const Divider(height: 1, color: C.line),

          // Footer: status control (fits at any width)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(children: [
              Expanded(
                  child: Text('Updated ${fmtWhen(inc.updated)}',
                      style: ts(13, color: C.muted),
                      overflow: TextOverflow.ellipsis)),
              Text('Status', style: ts(13, color: C.muted)),
              const SizedBox(width: 12),
              Container(
                width: 170,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.line)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: inc.status,
                    isExpanded: true,
                    style: ts(14, w: FontWeight.w600),
                    borderRadius: BorderRadius.circular(10),
                    items: [
                      for (final s in _statuses)
                        DropdownMenuItem(value: s, child: Text(s))
                    ],
                    onChanged: (v) => _setStatus(inc, v ?? inc.status),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _metric(String l, String v,
          {bool recorded = true, bool compact = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: C.bg, borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l,
                style: ts(12, color: C.muted), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(v,
                style: ts(
                    compact
                        ? 12
                        : recorded
                            ? 15
                            : 14,
                    w: recorded ? FontWeight.w700 : FontWeight.w500,
                    color: recorded ? C.ink : C.muted),
                maxLines: compact ? 2 : 1,
                overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis),
          ]),
        ),
      );
}

/* ── Top bar ── */
class _TopNav extends StatelessWidget {
  final DateTime? refreshedAt;
  final VoidCallback onRefresh;
  final DashboardUser user;
  final VoidCallback onManageUsers, onManageTeams, onLogout;
  const _TopNav({
    required this.refreshedAt,
    required this.onRefresh,
    required this.user,
    required this.onManageUsers,
    required this.onManageTeams,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
          const Logo(),
          const SizedBox(width: 10),
          Text('AquaAlert', style: ts(18, w: FontWeight.w700)),
          const SizedBox(width: 12),
          Text('Operations', style: ts(14, color: C.muted)),
          const Spacer(),
          if (refreshedAt != null)
            Text('Updated ${fmtTime(refreshedAt!)}',
                style: ts(13, color: C.muted)),
          const SizedBox(width: 12),
          if (user.role == 'admin')
            OutlinedButton.icon(
              onPressed: onManageUsers,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Manage staff'),
            ),
          if (user.role == 'admin') ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onManageTeams,
              icon: const Icon(Icons.groups_outlined, size: 18),
              label: const Text('Manage teams'),
            ),
          ],
          const SizedBox(width: 8),
          Text(user.displayName, style: ts(13, w: FontWeight.w600)),
          IconButton(
            tooltip: 'Sign out',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: C.muted),
          ),
          const SizedBox(width: 4),
          IconButton(
              tooltip: 'Refresh now',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: C.muted)),
        ]),
      );
}

/* ── Summary stats (all calculated from the database) ── */
class _Stats extends StatelessWidget {
  final Stats stats;
  const _Stats(this.stats);
  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Active incidents',
        '${stats.active}',
        'not yet resolved',
        Icons.monitor_heart_outlined,
        C.red,
        C.redSoft
      ),
      (
        'Avg. response',
        stats.responseText,
        'last 7 days',
        Icons.schedule_rounded,
        C.primary,
        C.primarySoft
      ),
      (
        'Teams assigned',
        stats.unitsText,
        'on open incidents',
        Icons.groups_outlined,
        C.green,
        C.greenSoft
      ),
      (
        'Water loss',
        stats.lossText,
        'recorded by staff',
        Icons.water_drop_outlined,
        C.amber,
        C.amberSoft
      ),
    ];
    return Row(children: [
      for (final (i, s) in items.indexed) ...[
        if (i > 0) const SizedBox(width: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: cardDeco(),
            child: Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: s.$6, borderRadius: BorderRadius.circular(12)),
                  child: Icon(s.$4, color: s.$5)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1,
                          style: ts(13, color: C.muted),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(s.$2,
                          style: ts(24, w: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(s.$3,
                          style: ts(12, color: C.muted),
                          overflow: TextOverflow.ellipsis),
                    ]),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/* ── Activity feed ── */
class _Feed extends StatelessWidget {
  final List<ActivityItem> items;
  const _Feed(this.items);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recent activity', style: ts(16, w: FontWeight.w700)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No activity yet.', style: ts(14, color: C.muted))),
          for (final (i, e) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, color: C.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 130,
                    child: Text(fmtWhen(e.createdAt),
                        style: ts(13, color: C.muted))),
                SizedBox(
                    width: 140,
                    child: Text(e.actor,
                        style: ts(14, w: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text('${e.trackingId} · ${e.message}',
                        style: ts(14, color: C.muted, h: 1.5))),
              ]),
            ),
          ],
        ]),
      );
}

/* ── Record team, arrival note and readings ── */
class _OpsDialog extends StatefulWidget {
  final Incident inc;
  final List<Team> teams;
  final List<DashboardUser> users;
  const _OpsDialog({
    required this.inc,
    required this.teams,
    required this.users,
  });
  @override
  State<_OpsDialog> createState() => _OpsDialogState();
}

class _OpsDialogState extends State<_OpsDialog> {
  late String team = widget.inc.team;
  late String assignedUserId = widget.inc.assignedUserId ?? '';
  late final arrival = TextEditingController(text: widget.inc.arrival);
  late final volume =
      TextEditingController(text: widget.inc.volumeGph?.toString() ?? '');
  late final pressure = TextEditingController(
      text: widget.inc.pressurePsi == null
          ? ''
          : _plain(widget.inc.pressurePsi!));
  String? volumeError, pressureError;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    arrival.dispose();
    volume.dispose();
    pressure.dispose();
    super.dispose();
  }

  void _save() {
    final vText = volume.text.trim();
    final pText = pressure.text.trim().replaceAll('−', '-');
    final v = vText.isEmpty ? null : int.tryParse(vText);
    final p = pText.isEmpty ? null : double.tryParse(pText);
    final vBad = vText.isNotEmpty && (v == null || v < 0);
    final pBad = pText.isNotEmpty && p == null;
    if (vBad || pBad) {
      setState(() {
        volumeError = vBad ? 'Whole number, 0 or more' : null;
        pressureError = pBad ? 'Enter a number, e.g. -12' : null;
      });
      return;
    }
    final inc = widget.inc;
    final note = arrival.text.trim();
    final changes = <String, dynamic>{};
    if (team != inc.team) changes['team'] = team.isEmpty ? null : team;
    if (assignedUserId != (inc.assignedUserId ?? '')) {
      changes['assignedUserId'] =
          assignedUserId.isEmpty ? null : assignedUserId;
    }
    if (note != inc.arrival) {
      changes['arrivalNote'] = note.isEmpty ? null : note;
    }
    if (v != inc.volumeGph) changes['volumeGph'] = v;
    if (p != inc.pressurePsi) changes['pressurePsi'] = p;
    Navigator.pop(context, changes);
  }

  InputDecoration _deco(String label, {String? error}) => InputDecoration(
        labelText: label,
        errorText: error,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final names = [for (final t in widget.teams) t.name];
    if (team.isNotEmpty && !names.contains(team)) names.add(team);
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Update operations', style: ts(18, w: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assigned team', style: ts(13, color: C.muted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.line)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: team,
                    isExpanded: true,
                    style: ts(14, w: FontWeight.w600),
                    borderRadius: BorderRadius.circular(10),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Unassigned')),
                      for (final n in names)
                        DropdownMenuItem(value: n, child: Text(n)),
                    ],
                    onChanged: (v) => setState(() => team = v ?? ''),
                  ),
                ),
              ),
              if (widget.teams.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'No teams exist yet. Add them with the seed script or POST /api/admin/teams.',
                      style: ts(12, color: C.muted)),
                ),
              const SizedBox(height: 16),
              Text('Assign to a person', style: ts(13, color: C.muted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.line)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: assignedUserId,
                    isExpanded: true,
                    style: ts(14, w: FontWeight.w600),
                    borderRadius: BorderRadius.circular(10),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Unassigned')),
                      for (final user in widget.users)
                        DropdownMenuItem(
                          value: user.id,
                          child:
                              Text('${user.displayName} · ${user.userNumber}'),
                        ),
                      if (assignedUserId.isNotEmpty &&
                          !widget.users.any((u) => u.id == assignedUserId))
                        DropdownMenuItem(
                          value: assignedUserId,
                          child: const Text('Inactive staff member'),
                        ),
                    ],
                    onChanged: (v) => setState(() => assignedUserId = v ?? ''),
                  ),
                ),
              ),
              if (widget.users.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('No active dashboard users are available.',
                      style: ts(12, color: C.muted)),
                ),
              const SizedBox(height: 16),
              TextField(
                  controller: arrival,
                  maxLength: 100,
                  decoration: _deco('Arrival or dispatch note')
                      .copyWith(counterText: '')),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                      controller: volume,
                      keyboardType: TextInputType.number,
                      decoration:
                          _deco('Volume loss (gal/h)', error: volumeError)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: pressure,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration:
                        _deco('Pressure change (PSI)', error: pressureError),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                  'Leave a reading empty if it hasn’t been measured. The dashboard only shows what has been recorded.',
                  style: ts(12, color: C.muted, h: 1.4)),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ManageStaffDialog extends StatefulWidget {
  final List<DashboardUser> users;
  const _ManageStaffDialog({required this.users});

  @override
  State<_ManageStaffDialog> createState() => _ManageStaffDialogState();
}

class _ManageStaffDialogState extends State<_ManageStaffDialog> {
  late List<DashboardUser> users = List.of(widget.users);
  String? error;

  Future<void> _addStaff() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (added != true || !mounted) return;
    try {
      final refreshedUsers = await Api.users();
      if (!mounted) return;
      setState(() {
        users = refreshedUsers;
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Dashboard staff'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Text(error!, style: ts(13, color: C.red)),
                const SizedBox(height: 8),
              ],
              if (users.isEmpty)
                Text('No active users yet.', style: ts(14, color: C.muted))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final user in users)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: C.primarySoft,
                            child: Text(user.displayName.isEmpty
                                ? '?'
                                : user.displayName[0].toUpperCase()),
                          ),
                          title: Text(user.displayName),
                          subtitle: Text(
                              '${user.userNumber} · ${user.role == 'admin' ? 'Administrator' : 'Staff'}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
          FilledButton.icon(
            onPressed: _addStaff,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add staff'),
          ),
        ],
      );
}

class _ManageTeamsDialog extends StatefulWidget {
  final List<Team> teams;
  const _ManageTeamsDialog({required this.teams});

  @override
  State<_ManageTeamsDialog> createState() => _ManageTeamsDialogState();
}

class _ManageTeamsDialogState extends State<_ManageTeamsDialog> {
  late List<Team> teams = List.of(widget.teams);
  final _name = TextEditingController();
  final _lead = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lead.dispose();
    super.dispose();
  }

  Future<void> _addTeam() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a team name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.createTeam(
        name: name,
        lead: _lead.text.trim().isEmpty ? null : _lead.text.trim(),
      );
      final refreshedTeams = await Api.teams();
      if (!mounted) return;
      setState(() {
        teams = refreshedTeams;
        _name.clear();
        _lead.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Municipal repair teams'),
        content: SizedBox(
          width: 440,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: teams.isEmpty
                    ? Center(
                        child: Text('No active teams yet.',
                            style: ts(14, color: C.muted)))
                    : ListView(
                        children: [
                          for (final team in teams)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: C.greenSoft,
                                child: Icon(Icons.engineering_outlined,
                                    color: C.green),
                              ),
                              title: Text(team.name),
                              subtitle: Text(team.lead.isEmpty
                                  ? (team.busy
                                      ? 'Assigned to an open incident'
                                      : 'Available for assignment')
                                  : '${team.lead}${team.busy ? ' · Assigned' : ''}'),
                            ),
                        ],
                      ),
              ),
              const Divider(),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Team name'),
                onSubmitted: (_) => _saving ? null : _addTeam(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lead,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Team lead (optional)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _addTeam,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Add'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: ts(13, color: C.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done')),
        ],
      );
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _userNumber = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _userNumber.dispose();
    _name.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 12 || _password.text != _confirmPassword.text) {
      setState(() => _error = _password.text.length < 12
          ? 'Use a password with at least 12 characters.'
          : 'Passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.createStaff(
        userNumber: _userNumber.text.trim(),
        displayName: _name.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add dashboard staff'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Staff number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Minimum 12 characters'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Confirm temporary password'),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: ts(13, color: C.red)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create account'),
          ),
        ],
      );
}
