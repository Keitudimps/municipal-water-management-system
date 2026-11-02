import 'package:flutter/material.dart';
import 'theme.dart';

BoxDecoration cardDeco({double r = 16, Color color = Colors.white}) =>
    BoxDecoration(color: color, borderRadius: BorderRadius.circular(r), border: Border.all(color: C.line));

(Color, Color) statusColors(String s) => switch (s) {
      'In Progress' => (C.primarySoft, C.primary),
      'Resolved' || 'Minor' => (C.greenSoft, C.green),
      'Delayed' || 'Moderate' || 'Major' => (C.amberSoft, C.amber),
      'Urgent' || 'Critical' || 'Emergency' => (C.redSoft, C.red),
      _ => (const Color(0xFFEEF0F3), C.muted),
    };

class Pill extends StatelessWidget {
  final String text;
  final Color? bg, fg;
  const Pill(this.text, {super.key, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final c = statusColors(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg ?? c.$1, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: ts(12, w: FontWeight.w600, color: fg ?? c.$2)),
    );
  }
}

/// Shows an image from the network or assets, falling back to a soft gradient with an icon.
class Photo extends StatelessWidget {
  final String? asset, url;
  final IconData icon;
  final List<Color> colors;
  final double radius;
  const Photo({super.key, this.asset, this.url, this.icon = Icons.image_outlined, this.colors = const [Color(0xFFB9CBDD), Color(0xFF7C93AA)], this.radius = 0});
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: Icon(icon, color: Colors.white54, size: 40)),
    );
    Widget child = fallback;
    if (url != null) {
      child = Image.network(url!, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
          errorBuilder: (_, __, ___) => fallback, loadingBuilder: (_, w, p) => p == null ? w : fallback);
    } else if (asset != null) {
      child = Image.asset(asset!, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => fallback);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  const PrimaryButton(this.label, {super.key, this.onTap, this.icon, this.loading = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: loading ? null : (onTap ?? () {}),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: ts(16, w: FontWeight.w600, color: Colors.white)),
                  if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
                ]),
        ),
      );
}

class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 20),
      );
}

class TopBar extends StatelessWidget {
  final String title;
  final bool back;
  const TopBar(this.title, {super.key, this.back = false});
  @override
  Widget build(BuildContext context) => Container(
        height: 60,
        padding: EdgeInsets.symmetric(horizontal: back ? 8 : 20),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
          if (back)
            IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 18))
          else
            const Logo(),
          SizedBox(width: back ? 4 : 12),
          Text(title, style: ts(17, w: FontWeight.w700)),
          const Spacer(),
          const Icon(Icons.notifications_none_rounded, color: C.muted),
          SizedBox(width: back ? 12 : 0),
        ]),
      );
}
