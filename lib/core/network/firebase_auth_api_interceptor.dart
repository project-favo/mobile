import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';

/// Her korumalı istekten hemen önce Firebase ID token'ı [getIdToken(true)] ile yeniler.
void attachFirebaseIdTokenToAllRequests() {
  ApiClient().dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              final t = await user.getIdToken(true);
              if (t != null) {
                options.headers['Authorization'] = 'Bearer $t';
              }
            }
            handler.next(options);
          },
        ),
      );
}
