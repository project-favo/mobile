import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';

/// Her istekten hemen önce oturum varsa Firebase **ID token**'ı [getIdToken(true)] ile yeniler.
///
/// Oturum yokken eski [Authorization] başlığını kaldırır; aksi halde Dio’daki kalıntı Bearer
/// bazı uçlarda (ör. permitAll + token doğrulaması) 401 üretebilir.
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
            } else {
              options.headers.remove('Authorization');
            }
            handler.next(options);
          },
        ),
      );
}
