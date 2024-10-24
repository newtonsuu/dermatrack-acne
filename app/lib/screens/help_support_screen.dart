import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_widgets.dart';

/// Help & Support hub: FAQ, contact, bug reporting, a how-to-scan guide, the
/// medical disclaimer, and terms & privacy. Each item opens a real screen.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const SettingsSectionLabel('Get help'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsTile(
              icon: Icons.help_outline,
              title: 'FAQ',
              subtitle: 'Common questions about scanning and results.',
              onTap: () => _push(context, const _FaqScreen()),
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.camera_alt_outlined,
              title: 'How to scan',
              subtitle: 'Get the most accurate results.',
              onTap: () => _push(context, const _HowToScanScreen()),
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.support_agent_outlined,
              title: 'Contact support',
              onTap: () => _push(context, const _ContactScreen()),
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.bug_report_outlined,
              title: 'Report a bug',
              onTap: () => _push(context, const _ReportBugScreen()),
            ),
          ]),
          const SizedBox(height: 20),
          const SettingsSectionLabel('Legal & safety'),
          const SizedBox(height: 8),
          SettingsCard(children: [
            SettingsTile(
              icon: Icons.health_and_safety_outlined,
              title: 'Medical disclaimer',
              onTap: () => _push(context, const _DisclaimerScreen()),
            ),
            const SettingsDivider(),
            SettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms & privacy',
              onTap: () => _push(context, const _TermsScreen()),
            ),
          ]),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

// ===== FAQ =====

class _FaqScreen extends StatelessWidget {
  const _FaqScreen();

  static const _faqs = <List<String>>[
    [
      'Is DermaTrack a medical diagnosis?',
      'No. DermaTrack is a monitoring-support tool that helps you track changes '
          'in your skin over time. It does not diagnose any condition. For '
          'diagnosis and treatment, consult a licensed dermatologist.',
    ],
    [
      'How is my acne severity calculated?',
      'Each scan is analyzed and graded on a severity scale, then summarized as '
          'Clear, Mild, Moderate, or Severe. The full-face quick scan gives an '
          'overall result; the per-region scan grades each facial zone and '
          'combines them into an overall facial summary.',
    ],
    [
      'What is the difference between the quick scan and the per-region scan?',
      'The quick single scan is one full-face photo for a fast overall result. '
          'The per-region scan walks through your forehead, cheeks, chin, and '
          'nose for a more detailed distribution and an overall summary.',
    ],
    [
      'Who can see my scans?',
      'Only you — unless you turn on “Share my records with a dermatologist” in '
          'Privacy & Data. You can revoke that consent at any time.',
    ],
    [
      'Why didn\'t my scan detect a face?',
      'Make sure your face is well-lit, centered, and close enough to fill the '
          'guide. For per-region shots, follow the on-screen oval for each zone.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final qa in _faqs)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  qa[0],
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                    fontSize: 14.5,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      qa[1],
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        height: 1.5,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ===== How to scan =====

class _HowToScanScreen extends StatelessWidget {
  const _HowToScanScreen();

  static const _steps = <List<String>>[
    ['Find good light', 'Face a window or a bright, even light source. Avoid '
        'harsh shadows and strong backlight.'],
    ['Clean the lens', 'A quick wipe of your camera keeps detections sharp.'],
    ['Fill the guide', 'Hold the phone steady and bring your face close enough '
        'to fill the on-screen oval.'],
    ['Quick scan', 'For a fast overall result, use the full-face quick single '
        'scan from the home screen.'],
    ['Per-region scan', 'For a detailed breakdown, run the guided session and '
        'follow the oval for each zone: forehead, cheeks, chin, and nose.'],
    ['Scan consistently', 'Scanning around the same time each day makes your '
        'trend more accurate.'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('How to scan')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: _steps.length,
        itemBuilder: (context, i) {
          final step = _steps[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTheme.primary,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step[0],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step[1],
                        style: TextStyle(
                          color: AppTheme.textSecondary(context),
                          height: 1.45,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===== Contact support =====

class _ContactScreen extends StatelessWidget {
  const _ContactScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Contact support')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Need a hand? Email the DermaTrack team and we\'ll get back to you.',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Icon(Icons.email_outlined, color: AppTheme.primary),
              title: const Text(kSupportEmail),
              subtitle: const Text('Tap to copy'),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: kSupportEmail));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Support email copied.')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Report a bug =====

class _ReportBugScreen extends StatefulWidget {
  const _ReportBugScreen();

  @override
  State<_ReportBugScreen> createState() => _ReportBugScreenState();
}

class _ReportBugScreenState extends State<_ReportBugScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _platform {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the problem first.')),
      );
      return;
    }
    final report = 'DermaTrack bug report\n'
        'Version: $kAppVersion\n'
        'Platform: $_platform\n'
        '---\n$text';
    Clipboard.setData(ClipboardData(text: report));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report copied'),
        content: const Text(
          'Your report (with app version + platform) was copied to the '
          'clipboard. Please paste it into an email to:\n\n$kSupportEmail',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Report a bug')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Tell us what went wrong — what you did, what you expected, and '
            'what happened instead.',
            style: TextStyle(
              color: AppTheme.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 5,
            decoration: const InputDecoration(
              hintText: 'Describe the bug…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Prepare report'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Disclaimer & Terms =====

class _DisclaimerScreen extends StatelessWidget {
  const _DisclaimerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Medical disclaimer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Para(
            'DermaTrack is a monitoring-support tool, not a medical device. It '
            'does not provide a medical diagnosis, prescription, or treatment '
            'plan, and it is not a substitute for professional medical advice.',
          ),
          _Para(
            'Severity results (Mild, Moderate, Severe) and any guidance shown '
            'are for tracking and educational purposes only. Always consult a '
            'licensed dermatologist or physician for diagnosis and treatment '
            'decisions.',
          ),
          _Para(
            'If you have a medical emergency, a severe or rapidly worsening skin '
            'reaction, signs of infection, or any urgent health concern, do not '
            'rely on this app — contact a healthcare professional or your local '
            'emergency services immediately.',
          ),
        ],
      ),
    );
  }
}

class _TermsScreen extends StatelessWidget {
  const _TermsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(title: const Text('Terms & privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Heading('Using DermaTrack'),
          _Para(
            'By using DermaTrack you acknowledge that it provides monitoring '
            'support only and does not diagnose or treat any condition, and '
            'that you remain responsible for seeking professional care.',
          ),
          _Heading('Your data'),
          _Para(
            'Your scan photos and results are stored in private, access-'
            'controlled storage and are only visible to you unless you '
            'explicitly consent to share them with a dermatologist. Traffic is '
            'encrypted in transit. You can export or delete your records, or '
            'request account deletion, from Privacy & Data.',
          ),
          _Heading('Consent'),
          _Para(
            'Sharing with a dermatologist is opt-in and can be withdrawn at any '
            'time. Withdrawing consent stops further access to your records.',
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: AppTheme.textPrimary(context),
        ),
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.textSecondary(context),
          height: 1.55,
          fontSize: 14,
        ),
      ),
    );
  }
}
