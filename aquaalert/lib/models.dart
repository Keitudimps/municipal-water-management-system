String fmtTime(DateTime d) {
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$m ${l.hour >= 12 ? 'PM' : 'AM'}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

/// Always include the local date so incident times are unambiguous.
String fmtWhen(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}, ${fmtTime(d)}';
}

String fmtCoords(double lat, double lng) =>
    '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? 'N' : 'S'}, ${lng.abs().toStringAsFixed(4)}° ${lng >= 0 ? 'E' : 'W'}';

/// A report as the citizen sees it.
class ReportSummary {
  final String trackingId, leakType, title, address, severity, eta, status;
  final DateTime createdAt;
  const ReportSummary({
    required this.trackingId,
    required this.leakType,
    required this.title,
    required this.address,
    required this.severity,
    required this.eta,
    required this.status,
    required this.createdAt,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        trackingId: j['trackingId'] as String,
        leakType: j['leakType'] as String,
        title: j['title'] as String,
        address: j['address'] as String,
        severity: j['severity'] as String,
        eta: j['eta'] as String,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class CityReport {
  final String trackingId, leakType, title, severity, status, address, city;
  final DateTime createdAt;

  const CityReport({
    required this.trackingId,
    required this.leakType,
    required this.title,
    required this.severity,
    required this.status,
    required this.address,
    required this.city,
    required this.createdAt,
  });

  factory CityReport.fromJson(Map<String, dynamic> json) => CityReport(
        trackingId: json['trackingId'] as String,
        leakType: json['leakType'] as String,
        title: json['title'] as String,
        severity: json['severity'] as String,
        status: json['status'] as String,
        address: json['address'] as String,
        city: json['city'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// An incident as operations sees it.
class Incident {
  final String id, title, address, level, phone, team, lead, arrival;
  final String? assignedUserId, assignedUserName, assignedUserNumber;
  final String? narrative, reporter, photoUrl;
  final double lat, lng;
  final DateTime created, updated;
  final int? volumeGph;
  final double? pressurePsi;
  String status;

  Incident({
    required this.id,
    required this.title,
    required this.address,
    required this.level,
    required this.narrative,
    required this.reporter,
    required this.phone,
    required this.team,
    required this.lead,
    required this.assignedUserId,
    required this.assignedUserName,
    required this.assignedUserNumber,
    required this.arrival,
    required this.photoUrl,
    required this.lat,
    required this.lng,
    required this.created,
    required this.updated,
    required this.volumeGph,
    required this.pressurePsi,
    required this.status,
  });

  factory Incident.fromJson(Map<String, dynamic> j) => Incident(
        id: j['id'] as String,
        title: j['title'] as String,
        address: j['address'] as String,
        level: j['level'] as String,
        narrative: j['narrative'] as String?,
        reporter: j['reporter'] as String?,
        phone: (j['phone'] as String?) ?? '',
        team: (j['team'] as String?) ?? '',
        lead: (j['lead'] as String?) ?? '',
        assignedUserId: j['assignedUserId']?.toString(),
        assignedUserName: j['assignedUserName'] as String?,
        assignedUserNumber: j['assignedUserNumber'] as String?,
        arrival: (j['arrival'] as String?) ?? '',
        photoUrl: j['photoUrl'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        created: DateTime.parse(j['createdAt'] as String),
        updated: DateTime.parse(j['updatedAt'] as String),
        volumeGph: (j['volumeGph'] as num?)?.toInt(),
        pressurePsi: (j['pressurePsi'] as num?)?.toDouble(),
        status: j['status'] as String,
      );

  String get time => fmtWhen(created);
  String get coords => fmtCoords(lat, lng);
  String get volume => volumeGph == null ? 'Not recorded' : '$volumeGph gal/h';
  String get pressure =>
      pressurePsi == null ? 'Not recorded' : '${_psi(pressurePsi!)} PSI';
  String get narrativeText =>
      narrative ?? 'No notes were added to this report.';
  String get reporterText => reporter ?? 'Name not given';
  String get initial => reporter == null ? '?' : reporter![0].toUpperCase();
  String get teamLine => team.isEmpty
      ? 'Not assigned yet'
      : (lead.isEmpty ? team : '$lead · $team');
  String get arrivalText => arrival.isEmpty ? 'Awaiting dispatch' : arrival;
  String get phoneText => phone.isEmpty ? 'No phone provided' : phone;
}

String _psi(double v) {
  final t =
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return t.replaceFirst('-', '−');
}

class DashboardUser {
  final String id, userNumber, displayName, role;
  const DashboardUser({
    required this.id,
    required this.userNumber,
    required this.displayName,
    required this.role,
  });

  factory DashboardUser.fromJson(Map<String, dynamic> json) => DashboardUser(
        id: json['id'].toString(),
        userNumber: json['userNumber'] as String,
        displayName: json['displayName'] as String,
        role: json['role'] as String,
      );
}

class Team {
  final String name, lead;
  final bool busy;
  const Team({required this.name, required this.lead, required this.busy});
  factory Team.fromJson(Map<String, dynamic> j) => Team(
      name: j['name'] as String,
      lead: (j['lead'] as String?) ?? '',
      busy: j['busy'] as bool);
}

class Stats {
  final int active, unitsBusy, unitsTotal;
  final int? avgResponseMin, waterLossGph; // null = nothing recorded yet
  const Stats(
      {this.active = 0,
      this.avgResponseMin,
      this.unitsBusy = 0,
      this.unitsTotal = 0,
      this.waterLossGph});

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        active: (j['active'] as num).toInt(),
        avgResponseMin: (j['avgResponseMin'] as num?)?.toInt(),
        unitsBusy: (j['unitsBusy'] as num).toInt(),
        unitsTotal: (j['unitsTotal'] as num).toInt(),
        waterLossGph: (j['waterLossGph'] as num?)?.toInt(),
      );

  String get responseText =>
      avgResponseMin == null ? '—' : '$avgResponseMin min';
  String get unitsText => unitsTotal == 0 ? '—' : '$unitsBusy / $unitsTotal';
  String get lossText {
    final g = waterLossGph;
    if (g == null) return '—';
    return g >= 1000 ? '${(g / 1000).toStringAsFixed(1)}k gal/hr' : '$g gal/hr';
  }
}

class ActivityItem {
  final String trackingId, actor, message;
  final DateTime createdAt;
  const ActivityItem(
      {required this.trackingId,
      required this.actor,
      required this.message,
      required this.createdAt});

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        trackingId: j['trackingId'] as String,
        actor: j['actor'] as String,
        message: j['message'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
