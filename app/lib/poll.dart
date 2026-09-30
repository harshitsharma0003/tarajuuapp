import 'dart:async';

import 'models.dart';

/// Poll a background search until the server reports status "done".
/// [onUpdate] fires on every response (pending ones may carry stale results).
Future<SearchResult> pollSearch(
  Future<SearchResult> Function() fetch, {
  void Function(SearchResult)? onUpdate,
  bool Function()? cancelled,
  Duration interval = const Duration(milliseconds: 1500),
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final r = await fetch();
    if (cancelled?.call() ?? false) return r;
    onUpdate?.call(r);
    if (r.done || DateTime.now().isAfter(deadline)) return r;
    await Future<void>.delayed(interval);
  }
}
