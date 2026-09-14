import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/catalog_stats.dart';
import '../../../core/providers/backend_config_provider.dart';
import '../../catalog/providers/catalog_provider.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _proxyUrlController;
  late final AnimationController _spinController;

  bool _isTestingConnection = false;
  bool? _connectionSuccess;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    final currentProxy = ref.read(backendProxyUrlProvider);
    _proxyUrlController = TextEditingController(text: currentProxy);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _handleTestConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionSuccess = null;
      _connectionMessage = null;
    });

    final targetUrl = _proxyUrlController.text.trim();
    final api = ref.read(apiClientProvider);
    final ok = await api.testConnection(customUrl: targetUrl);

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _connectionSuccess = ok;
        _connectionMessage = ok
            ? 'Connected successfully to backend proxy'
            : 'Could not reach backend proxy at $targetUrl';
      });
    }
  }

  Future<void> _handleSaveProxy() async {
    final newUrl = _proxyUrlController.text.trim();
    if (newUrl.isEmpty) return;

    await ref.read(backendProxyUrlProvider.notifier).setProxyUrl(newUrl);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend proxy configuration saved'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleForceSync() async {
    final catalogState = ref.read(catalogProvider);
    if (catalogState.isSyncing) return;

    _spinController.repeat();
    try {
      await ref.read(catalogProvider.notifier).syncCatalog(forceSync: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Catalog synchronized successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Catalog sync failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        _spinController.stop();
        _spinController.reset();
      }
    }
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.errorLight),
            SizedBox(width: 8),
            Text('Clear Local Catalog Cache?'),
          ],
        ),
        content: const Text(
          'This will remove all cached movies, TV series, and categories from local SQLite storage.\n\nYour account credentials will NOT be deleted. You can re-sync the catalog at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(catalogProvider.notifier).clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local catalog cache has been cleared'),
            backgroundColor: AppColors.info,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    await ref.read(catalogProvider.notifier).logout();
    if (mounted) {
      context.go('/login');
    }
  }

  String _formatRelativeTime(DateTime? timestamp) {
    if (timestamp == null) return 'Not synced yet';
    final diff = DateTime.now().difference(timestamp);

    if (diff.isNegative || diff.inSeconds < 45) {
      return 'Updated just now';
    }
    if (diff.inMinutes < 60) {
      return 'Updated ${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return 'Updated ${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return 'Updated ${diff.inDays}d ago';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogProvider);
    final currentAccount = catalogState.currentAccount;
    final isSyncing = catalogState.isSyncing;
    final syncProgress = catalogState.syncProgress;
    final stats = catalogState.stats;

    if (isSyncing && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!isSyncing && _spinController.isAnimating) {
      _spinController.stop();
      _spinController.reset();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings & Storage'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/movies');
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Page Header
                  _buildPageHeader(),
                  const SizedBox(height: 24),

                  // Backend Configuration Card
                  _buildBackendConfigCard(),
                  const SizedBox(height: 24),

                  // Active Catalog & Storage Stats Card
                  _buildCatalogStatsCard(
                    stats: stats,
                    currentAccount: currentAccount,
                    isSyncing: isSyncing,
                    syncProgress: syncProgress,
                  ),
                  const SizedBox(height: 24),

                  // Danger Zone / Data Management Card
                  _buildDangerZoneCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.indigo.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.indigo.withValues(alpha: 0.35)),
            ),
            child: const Icon(
              Icons.settings_rounded,
              color: AppColors.indigoLight,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings & Storage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Inspect cached catalog statistics and manage data.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title
          const Row(
            children: [
              Icon(
                Icons.settings_ethernet_rounded,
                size: 20,
                color: AppColors.indigoLight,
              ),
              SizedBox(width: 10),
              Text(
                'Backend Proxy Configuration',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Configure the backend proxy server URL that handles Xtream Codes API requests.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),

          // URL TextField
          TextFormField(
            controller: _proxyUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'PROXY SERVER URL',
              hintText: 'http://10.0.2.2:3000',
            ),
          ),
          const SizedBox(height: 12),

          // Presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip(
                label: 'Android Emulator (10.0.2.2:3000)',
                url: 'http://10.0.2.2:3000',
              ),
              _buildPresetChip(
                label: 'Localhost (localhost:3000)',
                url: 'http://localhost:3000',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Connection status pill if tested
          if (_connectionMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_connectionSuccess == true)
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_connectionSuccess == true)
                      ? AppColors.success.withValues(alpha: 0.35)
                      : AppColors.error.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    (_connectionSuccess == true)
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: (_connectionSuccess == true)
                        ? AppColors.successLight
                        : AppColors.errorLight,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionMessage!,
                      style: TextStyle(
                        color: (_connectionSuccess == true)
                            ? AppColors.successLight
                            : AppColors.errorLight,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Buttons row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _isTestingConnection ? null : _handleTestConnection,
                icon: _isTestingConnection
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded, size: 16),
                label: Text(_isTestingConnection ? 'Testing...' : 'Test Connection'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.indigoLight,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _handleSaveProxy,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Proxy URL'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip({required String label, required String url}) {
    final isSelected = _proxyUrlController.text.trim() == url;
    return InkWell(
      onTap: () {
        setState(() {
          _proxyUrlController.text = url;
          _connectionSuccess = null;
          _connectionMessage = null;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.indigo.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.indigo : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.indigoLight : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogStatsCard({
    required CatalogStats stats,
    required dynamic currentAccount,
    required bool isSyncing,
    required String syncProgress,
  }) {
    final formattedLastSync = _formatRelativeTime(stats.lastSyncTime);
    final numberFormat = NumberFormat('#,###');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: AppColors.purpleLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Catalog & Storage Stats',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cached locally in device persistent storage (SQLite).',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Grid of 4 stats
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isNarrow ? 2 : 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isNarrow ? 1.4 : 1.3,
                children: [
                  _buildStatTile(
                    title: 'Total Movies',
                    value: numberFormat.format(stats.totalMovies),
                    icon: Icons.movie_outlined,
                    iconColor: AppColors.indigoLight,
                  ),
                  _buildStatTile(
                    title: 'Total TV Series',
                    value: numberFormat.format(stats.totalSeries),
                    icon: Icons.tv_rounded,
                    iconColor: AppColors.purpleLight,
                  ),
                  _buildStatTile(
                    title: 'Categories',
                    value: numberFormat.format(stats.totalCategories),
                    icon: Icons.category_outlined,
                    iconColor: AppColors.info,
                  ),
                  _buildStatTile(
                    title: 'Last Synced',
                    value: formattedLastSync,
                    icon: Icons.access_time_rounded,
                    iconColor: AppColors.successLight,
                    isTextValue: true,
                    fullTimestamp: stats.lastSyncTime != null
                        ? DateFormat('yyyy-MM-dd HH:mm:ss')
                            .format(stats.lastSyncTime!)
                        : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Active Provider Info & Force Sync Button
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.storage_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          children: [
                            const TextSpan(text: 'Active Provider: '),
                            TextSpan(
                              text: currentAccount != null
                                  ? (currentAccount.displayName as String)
                                  : 'None',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (currentAccount != null &&
                                (currentAccount.url as String).isNotEmpty)
                              TextSpan(
                                text: ' (${currentAccount.url})',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Force Re-sync Button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: (isSyncing || currentAccount == null)
                        ? null
                        : _handleForceSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: AnimatedBuilder(
                      animation: _spinController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: isSyncing
                            ? AppColors.indigoLight
                            : AppColors.textSecondary,
                      ),
                    ),
                    label: Text(
                      isSyncing
                          ? (syncProgress.isNotEmpty
                              ? syncProgress
                              : 'Syncing...')
                          : 'Force Re-sync Catalog',
                      style: const TextStyle(fontSize: 12),
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

  Widget _buildStatTile({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    bool isTextValue = false,
    String? fullTimestamp,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, size: 14, color: iconColor),
            ],
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: fullTimestamp ?? value,
            child: Text(
              value,
              maxLines: isTextValue ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTextValue ? AppColors.indigoLight : Colors.white,
                fontSize: isTextValue ? 12 : 20,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.warning,
              ),
              SizedBox(width: 10),
              Text(
                'Data Management & Danger Zone',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Reset cached items or switch/logout of your active provider session.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Clear Local Catalog Cache Button
              OutlinedButton.icon(
                onPressed: _handleClearCache,
                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                label: const Text('Clear Local Catalog Cache'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.errorLight,
                  backgroundColor: AppColors.error.withValues(alpha: 0.08),
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),

              // Logout / Switch Account Button
              ElevatedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Logout / Switch Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
