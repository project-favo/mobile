import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';
import '../utils/exceptions.dart';
import '../utils/session_helper.dart';

/// [Options.extra] içinde `true` ise bu istekte Bearer eklenmez (anonim public uçlar için).
const kDioExtraSkipFirebaseAuth = 'skipFirebaseAuth';

/// Her istekten önce oturum varsa Firebase ID token eklenir. [getIdToken(false)]
/// önbellekteki geçerli token’ı kullanır; her istekte zorunlu yenileme uygulamayı ciddi yavaşlatır.
///
/// Oturum yokken eski [Authorization] başlığını kaldırır; aksi halde Dio’daki kalıntı Bearer
/// bazı uçlarda (ör. permitAll + token doğrulaması) 401 üretebilir.
///
/// Public feed gibi uçlar için [kDioExtraSkipFirebaseAuth] kullanın.
void attachFirebaseIdTokenToAllRequests() {
  final sessionHelper = SessionHelper();
  ApiClient().dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.extra[kDioExtraSkipFirebaseAuth] == true) {
              options.headers.remove('Authorization');
              handler.next(options);
              return;
            }
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              final t = await user.getIdToken();
              if (t != null) {
                options.headers['Authorization'] = 'Bearer $t';
              }
            } else {
              options.headers.remove('Authorization');
            }
            handler.next(options);
          },
          onError: (e, handler) async {
            final body = dioResponseDataAsSearchString(e.response?.data);
            final message = e.message ?? '';
            final combined = '$body $message';
            if (looksLikeSuspendedAccountMessage(combined)) {
              await sessionHelper.handleSuspendedAccount();
              handler.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  response: e.response,
                  type: e.type,
                  error: const SuspendedAccountException(),
                  message: e.message,
                ),
              );
              return;
            }
            if (looksLikeDeactivatedAccountMessage(combined)) {
              await sessionHelper.handleDeactivatedAccount();
              handler.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  response: e.response,
                  type: e.type,
                  error: const DeactivatedAccountException(),
                  message: e.message,
                ),
              );
              return;
            }
            handler.next(e);
          },
        ),
      );
}
