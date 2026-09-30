import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Thin HTTP client over the Tarajuu backend. All business logic is server-side.
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;
  final _http = http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        // Harmless elsewhere; stops free ngrok tunnels serving their browser warning page.
        'ngrok-skip-browser-warning': '1',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _u(String path, [Map<String, dynamic>? q]) => Uri.parse('${Config.apiBase}$path')
      .replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response r;
    try {
      r = await call().timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException(0, "Can't reach Tarajuu servers. Check your connection.");
    }
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiException(r.statusCode, detail is String ? detail : 'Something went wrong (${r.statusCode})');
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? q]) => _send(() => _http.get(_u(path, q), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(_u(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> patch(String path, [Object? body]) =>
      _send(() => _http.patch(_u(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> put(String path) => _send(() => _http.put(_u(path), headers: _headers));
  Future<dynamic> delete(String path) => _send(() => _http.delete(_u(path), headers: _headers));

  // ── auth ──
  Future<(String, AppUser)> firebaseLogin(String idToken, {String? name, String? email, bool? acceptedTerms}) async {
    final j = await post('/auth/firebase', {
      'idToken': idToken,
      'name': ?name,
      'email': ?email,
      'acceptedTerms': ?acceptedTerms,
    });
    return (j['token'] as String, AppUser.fromJson(j['user']));
  }

  Future<(AppUser, int)> me() async {
    final j = await get('/me');
    return (AppUser.fromJson(j['user']), (j['savedTotal'] as num).round());
  }

  Future<(List<RecentItem>, List<Product>)> recent() async {
    final j = await get('/me/recent');
    return (
      [for (final r in j['searches']) RecentItem.fromJson(r)],
      [for (final p in j['favourites']) Product.fromJson(p)],
    );
  }

  Future<void> setFavourite(String productId, bool on) =>
      on ? put('/me/favourites/$productId') : delete('/me/favourites/$productId');

  Future<void> buyClick({String? productId, required String kind, required String source, int saved = 0}) =>
      post('/me/buy-click', {'productId': productId, 'kind': kind, 'source': source, 'savedAmount': saved});

  // ── products ──
  Future<SearchResult> search(String q, {bool record = false}) async =>
      SearchResult.fromJson(await get('/products/search', {'q': q, 'record': record}));

  Future<SearchResult> home(String cat) async => SearchResult.fromJson(await get('/products/home', {'cat': cat}));

  Future<ProductDetail> product(String id) async => ProductDetail.fromJson(await get('/products/$id'));

  // ── places & rides ──
  Future<List<Place>> autocomplete(String q, {double? lat, double? lon}) async {
    final j = await get('/places/autocomplete', {'q': q, 'lat': ?lat, 'lon': ?lon});
    return [for (final p in j) Place.fromJson(p)];
  }

  Future<Place> reverse(double lat, double lon) async => Place.fromJson(await get('/places/reverse', {'lat': lat, 'lon': lon}));

  Future<RideEstimate> estimate(Place from, Place to, String type) async => RideEstimate.fromJson(
      await post('/rides/estimate', {'pickup': from.toJson(), 'dropoff': to.toJson(), 'type': type}));
}
