import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/account.dart';
import '../../../core/network/xtream_client.dart';
import '../../catalog/providers/catalog_provider.dart';
import '../../../core/theme/app_colors.dart';

enum _AuthTab { accounts, add }

class LoginScreen extends ConsumerStatefulWidget {
  final String? initialMode;

  const LoginScreen({super.key, this.initialMode});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late _AuthTab _activeTab;

  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _labelController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String _currentStep = '';
  String? _localError;

  @override
  void initState() {
    super.initState();
    final savedAccounts = ref.read(catalogProvider).savedAccounts;
    if (widget.initialMode == 'add' || savedAccounts.isEmpty) {
      _activeTab = _AuthTab.add;
    } else {
      _activeTab = _AuthTab.accounts;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _localError = null;
    });

    final serverUrl = _serverUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final label = _labelController.text.trim();

    if (serverUrl.isEmpty) {
      setState(() => _localError = 'Please enter your Xtream Codes server URL');
      return;
    }

    if (username.isEmpty) {
      setState(() => _localError = 'Please enter your username');
      return;
    }

    if (password.isEmpty) {
      setState(() => _localError = 'Please enter your password');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _currentStep = 'Connecting to Xtream provider...';
    });

    try {
      await ref.read(catalogProvider.notifier).loginWithXtream(
            url: serverUrl,
            username: username,
            password: password,
            name: label.isNotEmpty ? label : null,
          );

      if (mounted) {
        setState(() {
          _currentStep = 'Saved to SQLite cache. Redirecting...';
        });
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) {
          context.go('/movies');
        }
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          // Use the exception's own message, never toString() - that would
          // put "XtreamException(credentials, null): ..." on screen.
          _localError = err is XtreamException
              ? err.message
              : err.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleSelectAccount(Account account) async {
    setState(() {
      _localError = null;
      _isSubmitting = true;
      _currentStep = 'Connecting to "${account.displayName}"...';
    });

    try {
      await ref.read(catalogProvider.notifier).switchAccount(account);
      if (mounted) {
        context.go('/movies');
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _localError = 'Failed to switch account: $err';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleDeleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Saved Account'),
        content: Text(
          'Remove saved account "${account.displayName}" from this device? Cached data will also be removed.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(catalogProvider.notifier).removeAccount(account.sourceId);
      final remaining = ref.read(catalogProvider).savedAccounts;
      if (remaining.isEmpty && mounted) {
        setState(() {
          _activeTab = _AuthTab.add;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogProvider);
    final savedAccounts = catalogState.savedAccounts;
    final currentSourceId = catalogState.currentSourceId;
    final isSyncing = catalogState.isSyncing;
    final syncProgress = catalogState.syncProgress;

    final errorMessage = _localError ?? catalogState.error;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background Gradient Glow
          Positioned(
            top: -50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.indigo.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brand Header
                      _buildBrandHeader(),
                      const SizedBox(height: 24),

                      // Tab Switcher (if accounts exist)
                      if (savedAccounts.isNotEmpty) ...[
                        _buildTabSwitcher(savedAccounts.length),
                        const SizedBox(height: 20),
                      ],

                      // Main Card
                      _buildMainCard(
                        savedAccounts: savedAccounts,
                        currentSourceId: currentSourceId,
                        isSyncing: isSyncing,
                        syncProgress: syncProgress,
                        errorMessage: errorMessage,
                      ),

                      const SizedBox(height: 20),

                      // Footer Info
                      _buildFooterInfo(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        // Brand Icon
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.indigo.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.tv_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        // Brand Title
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'VOD ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Downloader',
                style: TextStyle(
                  color: AppColors.indigoLight,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        const Text(
          'Manage your Xtream Codes accounts and cache your library locally',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTabSwitcher(int accountsCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Saved Accounts ($accountsCount)',
              icon: Icons.person_outline_rounded,
              isActive: _activeTab == _AuthTab.accounts,
              onTap: () {
                setState(() {
                  _activeTab = _AuthTab.accounts;
                  _localError = null;
                });
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTabButton(
              title: 'Add Account',
              icon: Icons.add_rounded,
              isActive: _activeTab == _AuthTab.add,
              onTap: () {
                setState(() {
                  _activeTab = _AuthTab.add;
                  _localError = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.indigoDark : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.indigoDark.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainCard({
    required List<Account> savedAccounts,
    required dynamic currentSourceId,
    required bool isSyncing,
    required String syncProgress,
    required String? errorMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Error banner
          if (errorMessage != null) ...[
            _buildErrorBanner(errorMessage),
            const SizedBox(height: 18),
          ],

          // Active View
          if (_activeTab == _AuthTab.accounts && savedAccounts.isNotEmpty)
            _buildSavedAccountsView(
              savedAccounts: savedAccounts,
              currentSourceId: currentSourceId,
            )
          else
            _buildAddAccountForm(
              savedAccountsCount: savedAccounts.length,
              isSyncing: isSyncing,
              syncProgress: syncProgress,
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.errorLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.errorLight,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedAccountsView({
    required List<Account> savedAccounts,
    required dynamic currentSourceId,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // View header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SELECT AN ACCOUNT TO LOAD',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _activeTab = _AuthTab.add;
                  _localError = null;
                });
              },
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('New Account'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Accounts list
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: savedAccounts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final account = savedAccounts[index];
              final isActive =
                  account.sourceId.toString() == currentSourceId?.toString();
              return _buildAccountItem(account: account, isActive: isActive);
            },
          ),
        ),

        // Submitting status box
        if (_isSubmitting) ...[
          const SizedBox(height: 16),
          _buildStatusBox(_currentStep.isNotEmpty ? _currentStep : 'Loading account...'),
        ],
      ],
    );
  }

  Widget _buildAccountItem({
    required Account account,
    required bool isActive,
  }) {
    return InkWell(
      onTap: _isSubmitting ? null : () => _handleSelectAccount(account),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.indigo.withValues(alpha: 0.12)
              : AppColors.inputBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.indigo.withValues(alpha: 0.6)
                : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Account Tv Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.indigo
                    : AppColors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.tv_rounded,
                size: 20,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),

            // Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.indigo.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.indigo.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: AppColors.indigoLighter,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${account.username} @ ${account.url}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Trailing Actions
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.textMuted,
              hoverColor: AppColors.error.withValues(alpha: 0.15),
              tooltip: 'Remove account',
              onPressed: () => _handleDeleteAccount(account),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddAccountForm({
    required int savedAccountsCount,
    required bool isSyncing,
    required String syncProgress,
  }) {
    final busy = _isSubmitting || isSyncing;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title
          const Text(
            'Add Xtream Account',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Connect and cache a new Xtream Codes provider',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),

          // Server URL Input
          _buildFieldLabel(icon: Icons.language_rounded, label: 'SERVER URL'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _serverUrlController,
            enabled: !busy,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://example.com:8080',
            ),
          ),
          const SizedBox(height: 14),

          // Username Input
          _buildFieldLabel(icon: Icons.person_outline_rounded, label: 'USERNAME'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _usernameController,
            enabled: !busy,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Username',
            ),
          ),
          const SizedBox(height: 14),

          // Password Input
          _buildFieldLabel(icon: Icons.vpn_key_outlined, label: 'PASSWORD'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            enabled: !busy,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Friendly Label (optional)
          _buildFieldLabel(
            icon: Icons.label_outline_rounded,
            label: 'FRIENDLY LABEL',
            optional: true,
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _labelController,
            enabled: !busy,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'e.g. Living Room IPTV',
            ),
          ),
          const SizedBox(height: 22),

          // Submit Button
          ElevatedButton(
            onPressed: busy ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppColors.indigoDark,
              disabledBackgroundColor: AppColors.indigoDark.withValues(alpha: 0.5),
            ),
            child: busy
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          _currentStep.isNotEmpty
                              ? _currentStep
                              : (syncProgress.isNotEmpty
                                  ? syncProgress
                                  : 'Connecting...'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dns_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Save & Cache Catalog',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),

          // Cancel & view saved accounts button
          if (savedAccountsCount > 0) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        _activeTab = _AuthTab.accounts;
                        _localError = null;
                      });
                    },
              child: const Text(
                'Cancel and view saved accounts',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldLabel({
    required IconData icon,
    required String label,
    bool optional = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.indigoLight),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 4),
          const Text(
            '(optional)',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.indigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.indigo.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.indigoLight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.indigoLighter,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterInfo() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 14,
          color: AppColors.successLight,
        ),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            "Each account's catalog is isolated and cached locally in SQLite.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
