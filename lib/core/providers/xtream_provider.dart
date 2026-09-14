import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/catalog/providers/catalog_provider.dart';
import '../network/xtream_client.dart';

/// Provides an [XtreamClient] wired to the currently active account exposed
/// by [catalogProvider] (`CatalogState.currentAccount`).
///
/// Returns `null` when there is no active account, or when the account has
/// no url/username, or when [SourceAccount.password] is null — password is
/// currently nullable while the migration is in progress; a later task makes
/// it non-null and this null-check becomes effectively dead but harmless.
final xtreamClientProvider = Provider<XtreamClient?>((ref) {
  final account = ref.watch(catalogProvider).currentAccount;
  if (account == null) return null;

  final password = account.password;
  if (password == null || password.isEmpty) return null;
  if (account.url.isEmpty || account.username.isEmpty) return null;

  return XtreamClient(
    baseUrl: account.url,
    username: account.username,
    password: password,
  );
});
