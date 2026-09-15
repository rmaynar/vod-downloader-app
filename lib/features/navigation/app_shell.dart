import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../catalog/providers/catalog_provider.dart';

enum _AccountMenuAction {
  addAccount,
  manageAccounts,
}

/// App shell scaffold providing responsive navigation (Top Bar + BottomNav / NavRail)
/// for all authenticated routes in the application.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _syncSpinController;

  @override
  void initState() {
    super.initState();
    _syncSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _syncSpinController.dispose();
    super.dispose();
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location == '/') return 0;
    if (location.startsWith('/movies')) return 1;
    if (location.startsWith('/series')) return 2;
    if (location.startsWith('/downloads')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/movies');
        break;
      case 2:
        context.go('/series');
        break;
      case 3:
        context.go('/downloads');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }

  Future<void> _handleSync() async {
    final notifier = ref.read(catalogProvider.notifier);
    await notifier.syncCatalog(forceSync: true);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Log Out'),
        content: const Text(
          'Are you sure you want to log out of your current account?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(catalogProvider.notifier).logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _showAccountSwitcher(
    BuildContext context,
    CatalogState catalogState,
  ) async {
    final action = await showModalBottomSheet<_AccountMenuAction>(
      context: context,
      backgroundColor: AppColors.cardBackground,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final accounts = catalogState.savedAccounts;
        final currentId = catalogState.currentSourceId;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'XTREAM ACCOUNTS (${accounts.length})',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.border, height: 1),
                if (accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No saved accounts found',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: accounts.length,
                      itemBuilder: (context, index) {
                        final account = accounts[index];
                        final isActive = account.sourceId == currentId;

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          selected: isActive,
                          selectedTileColor: AppColors.indigo.withValues(alpha: 0.12),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.indigo.withValues(alpha: 0.2)
                                  : AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? AppColors.indigo
                                    : AppColors.border,
                              ),
                            ),
                            child: Icon(
                              Icons.person_outline,
                              size: 18,
                              color: isActive
                                  ? AppColors.indigoLight
                                  : AppColors.textSecondary,
                            ),
                          ),
                          title: Text(
                            account.name.isNotEmpty
                                ? account.name
                                : account.username,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${account.username} • ${account.url}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: isActive
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.indigo,
                                  size: 20,
                                )
                              : null,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            if (!isActive) {
                              ref
                                  .read(catalogProvider.notifier)
                                  .switchAccount(account.sourceId);
                            }
                          },
                        );
                      },
                    ),
                  ),
                const Divider(color: AppColors.border, height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.indigo.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.indigoLight,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Add Another Account',
                    style: TextStyle(
                      color: AppColors.indigoLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop(_AccountMenuAction.addAccount);
                  },
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Manage All Accounts',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop(_AccountMenuAction.manageAccounts);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case _AccountMenuAction.addAccount:
        context.push('/login?mode=add');
      case _AccountMenuAction.manageAccounts:
        context.push('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogProvider);
    final selectedIndex = _calculateSelectedIndex(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWiderScreen = screenWidth >= 800;

    // Control sync spinning animation
    if (catalogState.isSyncing) {
      if (!_syncSpinController.isAnimating) {
        _syncSpinController.repeat();
      }
    } else {
      if (_syncSpinController.isAnimating) {
        _syncSpinController.stop();
        _syncSpinController.reset();
      }
    }

    final activeAccount = catalogState.currentAccount;
    final accountDisplayName = activeAccount != null
        ? (activeAccount.name.isNotEmpty
            ? activeAccount.name
            : activeAccount.username)
        : 'Select Account';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // App Brand Logo & Title
                  InkWell(
                    onTap: () => context.go('/'),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.indigo.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/vod-download-icon.jpeg',
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.tv_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (isWiderScreen) ...[
                            const SizedBox(width: 10),
                            Text.rich(
                              const TextSpan(
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'VOD ',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'Downloader',
                                    style: TextStyle(
                                      color: AppColors.indigoLight,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              semanticsLabel: 'VOD Downloader',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Desktop/Tablet Navigation Links (visible when wide)
                  if (isWiderScreen) ...[
                    const SizedBox(width: 24),
                    _HeaderNavLink(
                      label: 'Movies',
                      isActive: selectedIndex == 1,
                      onTap: () => context.go('/movies'),
                    ),
                    const SizedBox(width: 8),
                    _HeaderNavLink(
                      label: 'TV Shows',
                      isActive: selectedIndex == 2,
                      onTap: () => context.go('/series'),
                    ),
                  ],

                  const Spacer(),

                  // Pulsing progress pill while syncing
                  if (catalogState.isSyncing) ...[
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.indigo.withValues(alpha: 0.15),
                          border: Border.all(
                            color: AppColors.indigo.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.indigoLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: screenWidth < 500 ? 90 : 160,
                                ),
                                child: Text(
                                  catalogState.syncProgress.isNotEmpty
                                      ? catalogState.syncProgress
                                      : 'Syncing...',
                                  style: const TextStyle(
                                    color: AppColors.indigoLight,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Source Account Dropdown Switcher Button
                  InkWell(
                    onTap: () => _showAccountSwitcher(context, catalogState),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.indigo.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              size: 13,
                              color: AppColors.indigoLight,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: screenWidth < 450 ? 80 : 130,
                            ),
                            child: Text(
                              accountDisplayName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Quick Sync Button
                  IconButton(
                    tooltip: catalogState.isSyncing
                        ? 'Syncing in progress...'
                        : 'Quick Sync Catalog',
                    onPressed: catalogState.isSyncing ||
                            catalogState.currentSourceId == null
                        ? null
                        : _handleSync,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                    icon: RotationTransition(
                      turns: _syncSpinController,
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: catalogState.isSyncing
                            ? AppColors.indigoLight
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Settings Button
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => context.go('/settings'),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Logout Button
                  IconButton(
                    tooltip: 'Log Out',
                    onPressed: _handleLogout,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // 2px animated progress line when syncing
          if (catalogState.isSyncing)
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.indigo),
              ),
            ),

          Expanded(
            child: Row(
              children: [
                // Navigation Rail for tablets / wider screens
                if (isWiderScreen)
                  NavigationRail(
                    backgroundColor: AppColors.surface,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (idx) => _onItemTapped(idx, context),
                    labelType: NavigationRailLabelType.all,
                    indicatorColor: AppColors.indigo.withValues(alpha: 0.2),
                    selectedIconTheme: const IconThemeData(color: AppColors.indigoLight),
                    unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
                    selectedLabelTextStyle: const TextStyle(
                      color: AppColors.indigoLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelTextStyle: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.movie_outlined),
                        selectedIcon: Icon(Icons.movie_rounded),
                        label: Text('Movies'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.tv_outlined),
                        selectedIcon: Icon(Icons.tv_rounded),
                        label: Text('TV Shows'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.download_outlined),
                        selectedIcon: Icon(Icons.download_rounded),
                        label: Text('Downloads'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: Text('Settings'),
                      ),
                    ],
                  ),

                // Main Content
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
      // Bottom Navigation Bar for Mobile screens
      bottomNavigationBar: isWiderScreen
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: NavigationBar(
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.indigo.withValues(alpha: 0.2),
                selectedIndex: selectedIndex,
                onDestinationSelected: (idx) => _onItemTapped(idx, context),
                height: 62,
                elevation: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined, color: AppColors.textMuted),
                    selectedIcon:
                        Icon(Icons.home_rounded, color: AppColors.indigoLight),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.movie_outlined, color: AppColors.textMuted),
                    selectedIcon:
                        Icon(Icons.movie_rounded, color: AppColors.indigoLight),
                    label: 'Movies',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tv_outlined, color: AppColors.textMuted),
                    selectedIcon:
                        Icon(Icons.tv_rounded, color: AppColors.indigoLight),
                    label: 'TV Shows',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.download_outlined, color: AppColors.textMuted),
                    selectedIcon:
                        Icon(Icons.download_rounded, color: AppColors.indigoLight),
                    label: 'Downloads',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined, color: AppColors.textMuted),
                    selectedIcon:
                        Icon(Icons.settings_rounded, color: AppColors.indigoLight),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
    );
  }
}

class _HeaderNavLink extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _HeaderNavLink({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppColors.indigo : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.indigoLight : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
