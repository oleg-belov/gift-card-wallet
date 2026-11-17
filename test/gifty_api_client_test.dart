import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lidl_gift_card/services/gifty_api_client.dart';

void main() {
  const token =
      '8b704a4bb22d5b92b2243c540349246f.avjOBAa2U+4uE/lNAQwqhw=.AgAA';

  http.Request? capturedRequest;
  late Uri capturedUrl;

  GiftyApiClient clientWith(
      Future<http.Response> Function(http.Request) handler) {
    return GiftyApiClient(
      client: MockClient((request) async {
        capturedRequest = request;
        capturedUrl = request.url;
        return handler(request);
      }),
    );
  }

  test('sends the captured API contract (url, headers, payload)', () async {
    final client = clientWith((request) async {
      return http.Response(
        jsonEncode({
          'status': 'ACTIVE',
          'balance': {'amount': 0, 'currency': 'CHF'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final body = await client.fetchBalance(
      cardNumber: '211224627680296028',
      pin: '7195',
      captchaToken: token,
      cookies: 'consent=1; session=abc',
    );

    expect(capturedUrl.toString(), contains('/explore/giftyBalanceV2/gifty'));
    expect(capturedRequest!.headers['content-type'], 'application/json');
    expect(capturedRequest!.headers['origin'], 'https://www.lidl.ch');
    expect(capturedRequest!.headers['referer'], contains('guthabenabfrage'));
    expect(capturedRequest!.headers['cookie'], 'consent=1; session=abc');

    final payload = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
    expect(payload['cardNumber'], '211224627680296028');
    expect(payload['pinNumber'], '7195');
    expect(payload['country'], 'CH');
    expect(payload['locale'], 'de-CH');
    expect(payload['frcCaptchaToken'], token);

    expect(body, isNotNull);
    expect(body!['status'], 'ACTIVE');
  });

  test('a challenge body ("/") yields null so the caller falls back', () async {
    final client = clientWith((_) async => http.Response('/', 200));
    expect(
      await client.fetchBalance(
        cardNumber: '211224627680296028',
        pin: '7195',
        captchaToken: token,
      ),
      isNull,
    );
  });

  test('non-200 answers yield null', () async {
    final client = clientWith((_) async => http.Response('{"code": 500}', 500));
    expect(
      await client.fetchBalance(
        cardNumber: '211224627680296028',
        pin: '7195',
        captchaToken: token,
      ),
      isNull,
    );
  });

  test('JSON arrays yield null', () async {
    final client = clientWith((_) async => http.Response('[1,2,3]', 200));
    expect(
      await client.fetchBalance(
        cardNumber: '211224627680296028',
        pin: '7195',
        captchaToken: token,
      ),
      isNull,
    );
  });

  test('network failures yield null instead of throwing', () async {
    final client = GiftyApiClient(
      client: MockClient((_) async => throw StateError('offline')),
    );
    expect(
      await client.fetchBalance(
        cardNumber: '211224627680296028',
        pin: '7195',
        captchaToken: token,
      ),
      isNull,
    );
  });
}
