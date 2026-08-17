import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/app_sources.dart';
import 'app_logger.dart';
import 'local_cache_service.dart';

class QfWord {
  final String textUthmani;
  final String? translation;
  final String? audioUrl;
  const QfWord({required this.textUthmani, this.translation, this.audioUrl});
}

class QfConnectionResult {
  final bool success;
  final String message;
  const QfConnectionResult(this.success, this.message);
}

class QuranFoundationService {
  QuranFoundationService._();

  static String? _cachedToken;
  static DateTime? _tokenExpiresAt;
  static String? _tokenForClientId;

  static Future<String> _getAccessToken(String clientId, String clientSecret) async {
    final now = DateTime.now();
    if (_cachedToken != null &&
        _tokenExpiresAt != null &&
        _tokenForClientId == clientId &&
        now.isBefore(_tokenExpiresAt!)) {
      return _cachedToken!;
    }

    final uri = Uri.parse('${AppSources.quranFoundationOAuthBase}/oauth2/token');
    final basicAuth = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Basic $basicAuth',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'grant_type': 'client_credentials', 'scope': 'content'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Token request failed (HTTP ${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['access_token'] as String?;
    if (token == null) {
      throw Exception('Token response missing access_token: ${response.body}');
    }
    final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 3600;
    final safeExpiresIn = expiresIn > 60 ? expiresIn - 60 : expiresIn;

    _cachedToken = token;
    _tokenExpiresAt = now.add(Duration(seconds: safeExpiresIn));
    _tokenForClientId = clientId;
    return token;
  }

  static Future<QfConnectionResult> testConnection(String clientId, String clientSecret) async {
    if (clientId.trim().isEmpty || clientSecret.trim().isEmpty) {
      return const QfConnectionResult(false, 'Enter both the Client ID and Client Secret first.');
    }
    try {
      await _getAccessToken(clientId.trim(), clientSecret.trim());
      return const QfConnectionResult(true, 'Connected successfully.');
    } catch (e) {
      return QfConnectionResult(false, 'Connection failed: $e');
    }
  }

  static String _cacheKey(int surahNumber) => 'cache_qf_wbw_surah_$surahNumber';
  static final Map<int, List<List<QfWord>>> _memoryCache = {};

  static Future<List<List<QfWord>>?> fetchWordsForSurah({
    required String clientId,
    required String clientSecret,
    required int surahNumber,
    bool forceRefresh = false,
  }) async {
    if (clientId.trim().isEmpty || clientSecret.trim().isEmpty) return null;

    if (!forceRefresh && _memoryCache.containsKey(surahNumber)) {
      return _memoryCache[surahNumber];
    }

    if (!forceRefresh) {
      final cached = await LocalCacheService.getString(_cacheKey(surahNumber));
      if (cached != null) {
        final parsed = _parse(cached);
        _memoryCache[surahNumber] = parsed;
        // ignore: unawaited_futures
        _refreshInBackground(clientId.trim(), clientSecret.trim(), surahNumber);
        return parsed;
      }
    }

    try {
      final raw = await _fetchRaw(clientId.trim(), clientSecret.trim(), surahNumber);
      await LocalCacheService.setString(_cacheKey(surahNumber), raw);
      final parsed = _parse(raw);
      _memoryCache[surahNumber] = parsed;
      return parsed;
    } catch (e, st) {
      AppLogger.error('Quran Foundation word-by-word fetch failed for surah $surahNumber', error: e, stackTrace: st);
      final cached = await LocalCacheService.getString(_cacheKey(surahNumber));
      if (cached != null) {
        final parsed = _parse(cached);
        _memoryCache[surahNumber] = parsed;
        return parsed;
      }
      return null;
    }
  }

  static Future<void> _refreshInBackground(String clientId, String clientSecret, int surahNumber) async {
    try {
      final raw = await _fetchRaw(clientId, clientSecret, surahNumber);
      await LocalCacheService.setString(_cacheKey(surahNumber), raw);
      _memoryCache[surahNumber] = _parse(raw);
    } catch (e, st) {
      AppLogger.error('Quran Foundation word-by-word background refresh failed for surah $surahNumber', error: e, stackTrace: st);
    }
  }

  static Future<String> _fetchRaw(String clientId, String clientSecret, int surahNumber) async {
    final token = await _getAccessToken(clientId, clientSecret);
    final uri = Uri.parse(
      '${AppSources.quranFoundationApiBase}/content/api/v4/verses/by_chapter/$surahNumber'
      '?words=true&word_fields=text_uthmani,audio_url&word_translation_language=en&per_page=300',
    );
    final response = await http.get(
      uri,
      headers: {'x-auth-token': token, 'x-client-id': clientId, 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Word-by-word request failed (HTTP ${response.statusCode}): ${response.body}');
    }
    return utf8.decode(response.bodyBytes);
  }

  static List<List<QfWord>> _parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final versesJson = decoded['verses'] as List<dynamic>? ?? const [];
    final result = <List<QfWord>>[];
    for (final v in versesJson) {
      final verse = v as Map<String, dynamic>;
      final wordsJson = verse['words'] as List<dynamic>? ?? const [];
      final words = <QfWord>[];
      for (final w in wordsJson) {
        final word = w as Map<String, dynamic>;
        final charType = (word['char_type_name'] as String?) ?? 'word';
        if (charType != 'word') continue;
        final text = (word['text_uthmani'] ?? word['text'] ?? '') as String;
        String? translation;
        final translationField = word['translation'];
        if (translationField is Map<String, dynamic>) {
          translation = translationField['text'] as String?;
        } else if (translationField is String) {
          translation = translationField;
        }
        String? audioUrl;
        final rawAudio = word['audio_url'] as String?;
        if (rawAudio != null && rawAudio.isNotEmpty) {
          audioUrl = rawAudio.startsWith('http') ? rawAudio : '${AppSources.quranFoundationAudioBase}$rawAudio';
        }
        words.add(QfWord(textUthmani: text, translation: translation, audioUrl: audioUrl));
      }
      result.add(words);
    }
    return result;
  }
}
