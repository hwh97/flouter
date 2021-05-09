import 'dart:async';
import 'dart:collection';

import 'package:flouter/src/route_information.dart';
import 'package:flouter/src/typedef.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:provider/provider.dart';

/// a [RouterDelegate] based on [Uri]
class FlouterRouterDelegate extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  final GlobalKey<NavigatorState> navigatorKey;
  final List<NavigatorObserver> observers;

  late final FlouterRouteManager flouterRouteManager;

  FlouterRouterDelegate(
      {required this.navigatorKey,
      required Map<RegExp, PageBuilder> routes,
      List<Uri>? initialUris,
      PageBuilder? pageNotFound,
      this.observers = const <NavigatorObserver>[]}) {
    final _initialUris = initialUris ?? <Uri>[Uri(path: '/')];
    flouterRouteManager = FlouterRouteManager(
      routes: routes,
      pageNotFound: pageNotFound,
    );
    for (final uri in _initialUris) {
      flouterRouteManager.pushUri(uri);
    }
    flouterRouteManager._skipNext = true;
  }

  @visibleForTesting
  List<Uri> get uris => flouterRouteManager.uris;

  /// get the current route [Uri]
  /// this is show by the browser if your app run in the browser
  Uri? get currentConfiguration => flouterRouteManager.uris.isNotEmpty
      ? flouterRouteManager.uris.last
      : null;

  /// add a new [Uri] and the corresponding [Page] on top of the navigator
  @override
  Future<void> setNewRoutePath(Uri uri) {
    return flouterRouteManager.pushUri(uri);
  }

  /// @nodoc
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: flouterRouteManager,
      child: Consumer<FlouterRouteManager>(
        builder: (context, uriRouteManager, _) => Navigator(
          key: navigatorKey,
          observers: observers,
          pages: [
            for (final page in uriRouteManager.pages) page,
          ],
          onPopPage: (route, result) {
            if (!route.didPop(result)) {
              return false;
            }

            if (uriRouteManager.routes.isNotEmpty) {
              // print("onPopPage ${result}");
              // uriRouteManager.removeLastUri();
              uriRouteManager._removeLastUriWithValue(result);
              return true;
            }

            return false;
          },
        ),
      ),
    );
  }
}

/// allow you to interact with the List of [pages]
class FlouterRouteManager extends ChangeNotifier {
  static FlouterRouteManager of(BuildContext context) =>
      Provider.of<FlouterRouteManager>(context, listen: false);

  FlouterRouteManager({required this.routes, required this.pageNotFound});

  final Map<RegExp, PageBuilder> routes;
  final PageBuilder? pageNotFound;

  final _internalPages = <Page>[];
  final _internalUris = <Uri>[];

  bool _skipNext = false;
  bool _shouldUpdate = true;
  Completer<dynamic>? routerResultCompleter;
  Uri? currentAwaitUri;

  /// give you a read only access
  /// to the [List] of [Page] you have in your navigator
  List<Page> get pages => UnmodifiableListView(_internalPages);

  /// give you a read only access
  /// to the [List] of [Uri] you have in your navigator
  List<Uri> get uris => UnmodifiableListView(_internalUris);

  Future<void> _setNewRoutePath(Uri uri) {
    if (_skipNext) {
      _skipNext = false;
      return SynchronousFuture(null);
    }

    bool _findRoute = false;
    for (var i = 0; i < routes.keys.length; i++) {
      final key = routes.keys.elementAt(i);
      if (key.hasMatch(uri.path)) {
        final match = key.firstMatch(uri.path);
        final route = routes[key]!;
        _internalPages.add(route(FlouterRouteInformation(uri, match)));
        _internalUris.add(uri);
        _findRoute = true;
        break;
      }
    }
    if (!_findRoute) {
      var page = pageNotFound?.call(FlouterRouteInformation(uri, null));
      if (page == null) {
        page = MaterialPage(
          child: Scaffold(
            body: Container(
              child: Center(
                child: Text('Page not found'),
              ),
            ),
          ),
        );
      }
      _internalPages.add(page);
      _internalUris.add(uri);
    }
    if (_shouldUpdate) {
      notifyListeners();
    }
    return SynchronousFuture(null);
  }

  /// allow you to push multiple [Uri] at once
  @experimental
  Future<void> pushMultipleUri(List<Uri> uris) async {
    _shouldUpdate = false;
    for (final uri in uris) {
      await pushUri(uri);
    }
    notifyListeners();
    _shouldUpdate = true;
  }

  /// allow you one [Uri]
  Future<void> pushUri(Uri uri) => _setNewRoutePath(uri);

  /// allow you one [Uri] and wait result
  Future<T> pushUriAndWait<T>(Uri uri) async {
    routerResultCompleter = Completer<T>();
    currentAwaitUri = _internalUris.last;
    await pushUri(uri);
    return routerResultCompleter!.future as Future<T>;
  }

  /// allow you clear the list of [pages] and then push an [Uri]
  Future<void> clearAndPushUri(Uri uri) {
    _internalPages.clear();
    _internalUris.clear();
    return pushUri(uri);
  }

  /// allow you clear the list of [pages] and then push multiple [Uri] at once
  @experimental
  Future<void> clearAndPushMultipleUri(List<Uri> uris) async {
    _internalPages.clear();
    _internalUris.clear();
    await pushMultipleUri(uris);
    notifyListeners();
  }

  /// allow you to remove a specific [Uri] and the corresponding [Page]
  void removeUri(Uri uri) {
    final index = _internalUris.indexOf(uri);
    _internalPages.removeAt(index);
    _internalUris.removeAt(index);
    notifyListeners();
  }

  /// allow you to remove the last [Uri] and the corresponding [Page]
  void removeLastUri() {
    _internalPages.removeLast();
    _internalUris.removeLast();
    notifyListeners();
  }

  /// Pop to a specific [Uri] and delete any page at the top
  void removeUtilUri(Uri uri) {
    final index = _internalUris.indexOf(uri);

    _internalPages.removeRange(index + 1, _internalPages.length);
    _internalUris.removeRange(index + 1, _internalUris.length);
    notifyListeners();
  }

  /// Pop to a specific [Uri] and delete any page at the top and push [Uri]
  void removeUtilUriAndPush(Uri popPath, Uri toPath) {
    final index = _internalUris.indexOf(popPath);

    _internalPages.removeRange(index + 1, _internalPages.length);
    _internalUris.removeRange(index + 1, _internalUris.length);
    pushUri(toPath);
    // notifyListeners();
  }

  /// Pop to a specific [Uri] with [value] and delete any page at the top
  void removeUtilUriWithValue(Uri uri, dynamic value) {
    final index = _internalUris.indexOf(uri);

    _internalPages.removeRange(index + 1, _internalPages.length);
    _internalUris.removeRange(index + 1, _internalUris.length);

    _completeValue(uri, value);
    notifyListeners();
  }

  /// pop with value
  void _removeLastUriWithValue(dynamic value) {
    if (_internalUris.length >= 2) {
      _completeValue(_internalUris[_internalUris.length - 2], value);
    }
    removeLastUri();
  }

  /// complete value
  void _completeValue(Uri uri, dynamic value) {
    if (uri.path == currentAwaitUri?.path &&
        routerResultCompleter != null &&
        !routerResultCompleter!.isCompleted) {
      routerResultCompleter!.complete(value);
      routerResultCompleter = null;
      currentAwaitUri = null;
    }
  }
}
