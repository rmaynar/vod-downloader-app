import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';

const String kPrefBackendProxyUrl = 'backend_proxy_url';
const String kDefaultBackendProxyUrl = 'http://10.0.2.2:3000';

class BackendConfigNotifier extends StateNotifier<String> {
  BackendConfigNotifier() : super(kDefaultBackendProxyUrl) {
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kPrefBackendProxyUrl);
      if (saved != null && saved.trim().isNotEmpty) {
        state = saved.trim();
      }
    } catch (_) {}
  }

  Future<void> setProxyUrl(String url) async {
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    state = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefBackendProxyUrl, clean);
    } catch (_) {}
  }

  Future<void> resetToDefault() async {
    state = kDefaultBackendProxyUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefBackendProxyUrl);
    } catch (_) {}
  }
}

final backendProxyUrlProvider =
    StateNotifierProvider<BackendConfigNotifier, String>((ref) {
  return BackendConfigNotifier();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final url = ref.watch(backendProxyUrlProvider);
  return ApiClient(baseUrl: url);
});
