import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/panic_button.dart';
import '../auth/presentation/change_pin_page.dart';
import '../evidence/capture/audio_capture_page.dart';
import '../evidence/capture/in_app_camera_page.dart';
import '../vault/evidence_vault_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const Color background = Color(0xFF090B10);
  static const Color cardColor = Color(0xFF11151D);
  static const Color cardColor2 = Color(0xFF151A23);
  static const Color purple = Color(0xFF9B7BFF);
  static const Color purpleDark = Color(0xFF7352E8);
  static const Color textMuted = Color(0xFF9297A3);
  static const Color success = Color(0xFF67E8B1);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    _HomeContent(),
    _EvidencePage(),
    _SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomePage.background,
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: HomePage.cardColor,
        indicatorColor: HomePage.purple.withValues(alpha: 0.16),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Evidence',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HOME CONTENT
// ============================================================

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  void _openCamera(BuildContext context, {required bool videoMode}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InAppCameraPage(videoMode: videoMode)),
    );
  }

  void _openAudio(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AudioCapturePage()));
  }

  void _openEvidence(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EvidenceVaultPage()));
  }

  void _openHelp(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _HelpPage()));
  }

  void _panic(BuildContext context) {
    AppScope.of(context).lock.panic();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HomeHeader(),

          const SizedBox(height: 24),

          const _ProtectionCard(),

          const SizedBox(height: 22),

          const Text(
            'Quick actions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.camera_alt_outlined,
                  title: 'Capture Evidence',
                  subtitle: 'Photo or video',
                  onTap: () {
                    _showCaptureChoices(context);
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _ActionCard(
                  icon: Icons.mic_none,
                  title: 'Capture Audio',
                  subtitle: 'Record audio evidence',
                  onTap: () {
                    _openAudio(context);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.folder_outlined,
                  title: 'My Evidence',
                  subtitle: 'View saved evidence',
                  onTap: () {
                    _openEvidence(context);
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _ActionCard(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'Get help when needed',
                  onTap: () {
                    _openHelp(context);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          _PanicCard(
            onTap: () {
              _panic(context);
            },
          ),
        ],
      ),
    );
  }

  void _showCaptureChoices(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: HomePage.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: HomePage.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 22),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Capture Evidence',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose how you want to capture.',
                    style: TextStyle(color: HomePage.textMuted, fontSize: 13),
                  ),
                ),

                const SizedBox(height: 18),

                _BottomSheetOption(
                  icon: Icons.camera_alt_outlined,
                  title: 'Take Photo',
                  subtitle: 'Capture a photo using the camera',
                  onTap: () {
                    Navigator.pop(sheetContext);

                    _openCamera(context, videoMode: false);
                  },
                ),

                const SizedBox(height: 10),

                _BottomSheetOption(
                  icon: Icons.videocam_outlined,
                  title: 'Record Video',
                  subtitle: 'Record video using the camera',
                  onTap: () {
                    Navigator.pop(sheetContext);

                    _openCamera(context, videoMode: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// HEADER
// ============================================================

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: HomePage.purple.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: HomePage.purple,
            size: 27,
          ),
        ),

        const SizedBox(width: 13),

        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Secure Evidence',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),

              SizedBox(height: 3),

              Text(
                'My Evidence Center',
                style: TextStyle(color: HomePage.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),

        const PanicButton(color: HomePage.textMuted),
      ],
    );
  }
}

// ============================================================
// PROTECTION CARD
// ============================================================

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181329), Color(0xFF0F1219)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomePage.purple.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: HomePage.success.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: HomePage.success,
              size: 28,
            ),
          ),

          const SizedBox(width: 14),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protection Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                SizedBox(height: 5),

                Text(
                  'Your evidence center is protected.',
                  style: TextStyle(color: HomePage.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),

          const Icon(Icons.check_circle, color: HomePage.success, size: 22),
        ],
      ),
    );
  }
}

// ============================================================
// ACTION CARD
// ============================================================

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomePage.cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: HomePage.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: HomePage.purple, size: 25),
              ),

              const SizedBox(height: 14),

              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                subtitle,
                style: const TextStyle(color: HomePage.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTTOM SHEET OPTION
// ============================================================

class _BottomSheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BottomSheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomePage.cardColor2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: HomePage.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: HomePage.purple),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: HomePage.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: HomePage.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PANIC
// ============================================================

class _PanicCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PanicCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF151015),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panic Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Return immediately to the calculator.',
                      style: TextStyle(color: HomePage.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: HomePage.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EVIDENCE PAGE
// ============================================================

class _EvidencePage extends StatelessWidget {
  const _EvidencePage();

  @override
  Widget build(BuildContext context) {
    return const EvidenceVaultPage();
  }
}

// ============================================================
// HELP
// ============================================================

class _HelpPage extends StatelessWidget {
  const _HelpPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomePage.background,
      appBar: AppBar(
        backgroundColor: HomePage.background,
        foregroundColor: Colors.white,
        title: const Text('Help & Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Emergency Helplines',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 14),

          const _Helpline(name: 'Women Helpline (India)', number: '181'),

          const _Helpline(name: 'Police Emergency', number: '112'),

          const _Helpline(
            name: 'National Commission for Women',
            number: '011-26944880',
          ),
        ],
      ),
    );
  }
}

class _Helpline extends StatelessWidget {
  final String name;
  final String number;

  const _Helpline({required this.name, required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: HomePage.cardColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, color: HomePage.purple),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  number,
                  style: const TextStyle(
                    color: HomePage.textMuted,
                    fontSize: 12,
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

// ============================================================
// SETTINGS
// ============================================================

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  // Biometric unlock is P9; this toggle is still inert.
  bool biometric = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PanicButton(color: HomePage.textMuted),
          ],
        ),

        const SizedBox(height: 5),

        const Text(
          'Preferences',
          style: TextStyle(color: HomePage.textMuted, fontSize: 13),
        ),

        const SizedBox(height: 25),

        // Material, not a decorated Container: list tiles paint their ink
        // on the nearest Material, which a coloured box would hide.
        Material(
          color: HomePage.cardColor,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListenableBuilder(
                listenable: AppScope.of(context).lock,
                builder: (context, _) {
                  final lock = AppScope.of(context).lock;

                  return SwitchListTile(
                    value: lock.autoLock,
                    onChanged: lock.setAutoLock,
                    title: const Text(
                      'Auto-lock',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Lock whenever you leave the app or the screen '
                      'turns off. Pressing Home is then the fastest way '
                      'to hide everything.',
                      style: TextStyle(color: HomePage.textMuted),
                    ),
                    secondary: const Icon(
                      Icons.timer_outlined,
                      color: HomePage.purple,
                    ),
                  );
                },
              ),

              const Divider(height: 1, color: Color(0xFF242934)),

              SwitchListTile(
                value: biometric,
                onChanged: (value) {
                  setState(() {
                    biometric = value;
                  });
                },
                title: const Text(
                  'Biometric unlock',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Use device biometrics.',
                  style: TextStyle(color: HomePage.textMuted),
                ),
                secondary: const Icon(
                  Icons.fingerprint,
                  color: HomePage.purple,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),

        // Material, not a decorated Container: list tiles paint their ink
        // on the nearest Material, which a coloured box would hide.
        Material(
          color: HomePage.cardColor,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(
              Icons.password_outlined,
              color: HomePage.purple,
            ),
            title: const Text(
              'Change PIN',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Change the app entry PIN.',
              style: TextStyle(color: HomePage.textMuted),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: HomePage.textMuted,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangePinPage(
                    keyManager: AppScope.of(context).keyManager,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
