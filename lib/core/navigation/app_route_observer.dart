import 'package:flutter/material.dart';

/// Üst rota kapanınca alttaki sayfada [RouteAware.didPopNext] tetiklenir (ör. detaydan dönüşte liste tazeleme).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
