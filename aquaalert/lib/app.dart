import 'package:flutter/material.dart';
import 'dashboard_auth.dart';
import 'mobile.dart';
import 'theme.dart';

enum Site { both, mobile, dashboard }

/// site == both      → one app, two pages:  /#/  (mobile)   and  /#/dashboard (desktop)
/// site == mobile    → mobile site only      (lib/main_mobile.dart)
/// site == dashboard → dashboard only        (lib/main_dashboard.dart)
class AquaAlertApp extends StatelessWidget {
  final Site site;
  const AquaAlertApp({super.key, this.site = Site.both});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: switch (site) {
        Site.dashboard => 'AquaAlert Operations',
        Site.mobile => 'AquaAlert',
        Site.both => 'AquaAlert'
      },
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: switch (site) {
        Site.mobile => const MobileSite(),
        Site.dashboard => const DashboardGate(),
        Site.both => null
      },
      onGenerateRoute: site == Site.both
          ? (s) => MaterialPageRoute(
                settings: s,
                builder: (_) => s.name == '/dashboard'
                    ? const DashboardGate()
                    : const MobileSite(),
              )
          : null,
    );
  }
}
