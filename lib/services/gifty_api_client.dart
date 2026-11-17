import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

import 'balance_service.dart';

/// Talks to the gifty balance API directly, bypassing the page.
///
/// Why: Lidl's edge (Myra) challenges the API POST with a bot page when it
/// comes from an Android WebView — a fingerprint difference below anything
/// page JavaScript can influence (TLS handshake, HTTP/2 settings). Cronet is
/// Google Play services' network stack — the same engine desktop Chrome
/// uses — so a request sent through it presents a Chrome-class fingerprint
/// and passes.
///
/// The FriendlyCaptcha token is produced by the page's own widget (it talks
/// to friendlycaptcha.com, which is not edge-blocked) and handed to us by
/// the caller; the PoW the token certifies is exactly what the page submits
/// for every visitor.
class GiftyApiClient {
  GiftyApiClient({http.Client? client})
      : _client = client ?? _defaultClient();

  final http.Client _client;

  static http.Client _defaultClient() {
    // Cronet (Chrome's stack) on Android — the point of this class. Plain
    // dart:io HTTP elsewhere (host tests inject a mock client anyway).
    if (Platform.isAndroid) {
      return CronetClient.defaultCronetEngine();
    }
    return http.Client();
  }

  /// Sends the balance request and returns the decoded JSON body, or null
  /// when the endpoint answered with something other than a JSON object
  /// (a challenge page, an HTTP error, a network failure).
  Future<Map<String, dynamic>?> fetchBalance({
    required String cardNumber,
    required String pin,
    required String captchaToken,
    String cookies = '',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(kGiftyApiUrl),
            headers: {
              'content-type': 'application/json',
              'accept': '*/*',
              'accept-language': 'de-CH,de;q=0.9,en;q=0.8',
              'origin': 'https://www.lidl.ch',
              'referer': kPrimarySource.url,
              // Cronet's own UA is "Cronet/…" — a dead giveaway for bot
              // filters. Present the same UA the page's WebView uses.
              'user-agent': kChromeMobileUserAgent,
              if (cookies.isNotEmpty) 'cookie': cookies,
            },
            body: jsonEncode({
              'cardNumber': cardNumber,
              'pinNumber': pin,
              'country': 'CH',
              'locale': 'de-CH',
              'frcCaptchaToken': captchaToken,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}
