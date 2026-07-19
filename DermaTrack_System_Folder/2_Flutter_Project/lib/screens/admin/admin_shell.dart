import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/role_switcher.dart';
import '../../widgets/settings_widgets.dart';
import 'admin_chats_screen.dart';
import 'break_glass_screen.dart';

/// Top-level shell for the admin role. Hosts Overview, Users, and Audit tabs;
/// break-glass emergency access is reached from Overview or the Users sheet.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  final _admin = AdminService.instance;

  @override
  void initState() {
    super.initState();
    _admin.addListener(_onChange);
    _admin.refresh();
  }

  @override
  void dispose() {
    _admin.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You\'ll leave the admin console and be returned to the welcome '
            'screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    const tabs = [
      _AdminOverviewTab(),
      _AdminUsersTab(),
      AdminChatsTab(),
      _AdminAuditTab(),
    ];
    const titles = [
      'Admin console',
      'User management',
      'Chat moderation',
      'Audit log',
    ];
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          if (AuthService.instance.canSwitchRoles)
            IconButton(
              tooltip: 'Switch role',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => showRoleSwitcher(context),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _admin.refresh(),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: _admin.isLoading && _admin.users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : tabs[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Audit',
          ),
        ],
      ),
    );
  }
}

// ===== Overview =====

class _AdminOverviewTab extends StatelessWidget {
  const _AdminOverviewTab();

  @override
  Widget build(BuildContext context) {
    final a = AdminService.instance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const SettingsSectionLabel('System monitoring'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.7,
          children: [
            _StatCard(label: 'Total users', value: '${a.totalUsers}', icon: Icons.group),
            _StatCard(label: 'Patients', value: '${a.countByRole(UserRole.patient)}', icon: Icons.person),
            _StatCard(label: 'Doctors', value: '${a.countByRole(UserRole.doctor)}', icon: Icons.medical_services),
            _StatCard(label: 'Admins', value: '${a.countByRole(UserRole.admin)}', icon: Icons.shield),
            _StatCard(label: 'Deactivated', value: '${a.deactivatedCount}', icon: Icons.block),
            _StatCard(
              label: 'Active break-glass',
              value: '${a.activeBreakGlassCount}',
              icon: Icons.lock_open,
              danger: a.activeBreakGlassCount > 0,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SettingsSectionLabel('Emergency access'),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935)),
            title: const Text('Break-glass access'),
            subtitle: const Text(
                'Time-limited, read-only emergency access to a patient record. '
                'Every use is logged and reviewed.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BreakGlassScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFE53935) : AppTheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

// ===== Users =====

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab();

  @override
  Widget build(BuildContext context) {
    final users = AdminService.instance.users;
    if (users.isEmpty) {
      return Center(
        child: Text('No users found.',
            style: TextStyle(color: AppTheme.textSecondary(context))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, i) => _UserTile(user: users[i]),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final AdminUser user;

  Color _roleColor() {
    switch (user.role) {
      case UserRole.admin:
        return const Color(0xFF7E57C2);
      case UserRole.doctor:
        return const Color(0xFF5C6BC0);
      case UserRole.patient:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _roleColor().withValues(alpha: 0.15),
        child: Text(
          (user.displayName.isNotEmpty ? user.displayName : user.username)
              .characters
              .first
              .toUpperCase(),
          style: TextStyle(color: _roleColor(), fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(user.username,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Row(
        children: [
          _Badge(text: user.role.name, color: _roleColor()),
          const SizedBox(width: 6),
          if (!user.isActive)
            const _Badge(text: 'deactivated', color: Color(0xFFE53935)),
        ],
      ),
      trailing: const Icon(Icons.tune),
      onTap: () => _openManageSheet(context, user),
    );
  }

  void _openManageSheet(BuildContext context, AdminUser user) {
    final isSelf = AuthService.instance.currentUser != null &&
        AdminService.instance.usernameFor(user.id) ==
            AuthService.instance.currentUser!.username;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ManageUserSheet(user: user, isSelf: isSelf),
    );
  }
}

class _ManageUserSheet extends StatefulWidget {
  const _ManageUserSheet({required this.user, required this.isSelf});
  final AdminUser user;
  final bool isSelf;

  @override
  State<_ManageUserSheet> createState() => _ManageUserSheetState();
}

class _ManageUserSheetState extends State<_ManageUserSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(u.username,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Manage role and account status',
                style: TextStyle(color: AppTheme.textSecondary(context))),
            const SizedBox(height: 16),
            if (widget.isSelf)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'You cannot change your own role or status.',
                  style: TextStyle(
                      color: Colors.orange.shade800, fontSize: 12.5),
                ),
              ),
            const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final r in UserRole.values)
              RadioListTile<UserRole>(
                value: r,
                groupValue: u.role,
                onChanged: (widget.isSelf || _busy)
                    ? null
                    : (v) {
                        if (v != null && v != u.role) {
                          _run(() => AdminService.instance.setRole(u, v),
                              'Role updated to ${v.name}.');
                        }
                      },
                activeColor: AppTheme.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(r.name),
              ),
            const SizedBox(height: 8),
            if (!widget.isSelf)
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () =>
                            AdminService.instance.setActive(u, !u.isActive),
                        u.isActive ? 'Account deactivated.' : 'Account activated.'),
                icon: Icon(u.isActive ? Icons.block : Icons.check_circle_outline),
                label: Text(u.isActive ? 'Deactivate account' : 'Activate account'),
                style: FilledButton.styleFrom(
                  foregroundColor: u.isActive ? const Color(0xFFE53935) : null,
                ),
              ),
            if (!widget.isSelf) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => AdminService.instance
                            .setMessagingRestricted(u, !u.messagingRestricted),
                        u.messagingRestricted
                            ? 'Messaging unrestricted.'
                            : 'Messaging restricted.'),
                icon: Icon(u.messagingRestricted ? Icons.lock_open : Icons.block),
                label: Text(u.messagingRestricted
                    ? 'Unrestrict messaging'
                    : 'Restrict messaging'),
              ),
            ],
            if (u.role == UserRole.patient) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BreakGlassScreen(presetPatient: u),
                        ));
                      },
                icon: const Icon(Icons.lock_open, color: Color(0xFFE53935)),
                label: const Text('Break-glass access'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===== Audit =====

class _AdminAuditTab extends StatelessWidget {
  const _AdminAuditTab();

  @override
  Widget build(BuildContext context) {
    final entries = AdminService.instance.audit;
    if (entries.isEmpty) {
      return Center(
        child: Text('No audit entries yet.',
            style: TextStyle(color: AppTheme.textSecondary(context))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(_iconFor(e.action), color: AppTheme.primary),
            title: Text(_titleFor(e.action),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              '${e.detail}\n${_fmt(e.createdAt)} · ${e.actorRole}',
              style: const TextStyle(fontSize: 12.5),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  IconData _iconFor(String a) {
    if (a.startsWith('break_glass')) return Icons.lock_open;
    if (a.startsWith('account_deactivate')) return Icons.block;
    if (a.startsWith('account_activate')) return Icons.check_circle_outline;
    if (a.startsWith('role')) return Icons.swap_horiz;
    return Icons.history;
  }

  String _titleFor(String a) {
    switch (a) {
      case 'role_change':
        return 'Role changed';
      case 'account_activate':
        return 'Account activated';
      case 'account_deactivate':
        return 'Account deactivated';
      case 'break_glass_opened':
        return 'Break-glass opened';
      case 'break_glass_revoked':
        return 'Break-glass revoked';
      default:
        return a;
    }
  }

  static String _fmt(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '${months[t.month - 1]} ${t.day}, ${t.year} $h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
