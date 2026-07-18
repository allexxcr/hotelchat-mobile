import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

const String apiBase =
    'https://ognispb.online/api/mobile/v1/index.php';
const String appVersion = '1.1.2';

final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();
final ValueNotifier<int> chatRefreshSignal = ValueNotifier<int>(0);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );
  runApp(const HotelChatApp());
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient()
      : dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: <String, String>{'Accept': 'application/json'},
          ),
        );

  final Dio dio;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  String? token;

  Options get authOptions => Options(
        headers: token == null
            ? const <String, String>{}
            : <String, String>{'Authorization': 'Bearer $token'},
      );

  Future<void> loadToken() async {
    token = await storage.read(key: 'api_token');
  }

  Future<Map<String, dynamic>> _unwrap(Response<dynamic> response) async {
    final dynamic raw = response.data;

    if (raw is! Map) {
      throw ApiException('Сервер вернул некорректный ответ');
    }

    final Map<String, dynamic> data =
        Map<String, dynamic>.from(raw);

    if (data['ok'] != true) {
      throw ApiException(
        data['error']?.toString() ?? 'Ошибка сервера',
      );
    }

    return data;
  }

  Future<Map<String, dynamic>> login(
    String login,
    String password,
  ) async {
    try {
      final Response<dynamic> response = await dio.post(
        apiBase,
        queryParameters: const <String, String>{'route': 'login'},
        data: <String, String>{
          'login': login,
          'password': password,
          'device_name': 'HotelChat Android',
        },
      );

      final Map<String, dynamic> data = await _unwrap(response);
      final dynamic rawToken = data['token'];

      if (rawToken is! String || rawToken.isEmpty) {
        throw ApiException('Сервер не выдал токен авторизации');
      }

      token = rawToken;
      await storage.write(key: 'api_token', value: token);

      return Map<String, dynamic>.from(data['user'] as Map);
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<Map<String, dynamic>> me() async {
    try {
      return await _unwrap(
        await dio.get(
          apiBase,
          queryParameters: const <String, String>{'route': 'me'},
          options: authOptions,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<List<ChatItem>> chats({
    String status = 'open',
  }) async {
    try {
      final Map<String, dynamic> data = await _unwrap(
        await dio.get(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats',
            'status': status,
            'limit': 100,
          },
          options: authOptions,
        ),
      );

      return (data['items'] as List<dynamic>)
          .map(
            (dynamic item) => ChatItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<ChatDetails> chat(int id) async {
    try {
      final Map<String, dynamic> data = await _unwrap(
        await dio.get(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats/$id',
          },
          options: authOptions,
        ),
      );

      return ChatDetails(
        chat: ChatItem.fromJson(
          Map<String, dynamic>.from(data['chat'] as Map),
        ),
        messages: (data['messages'] as List<dynamic>)
            .map(
              (dynamic item) => MessageItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<List<MessageItem>> messages(
    int id,
    int afterId,
  ) async {
    try {
      final Map<String, dynamic> data = await _unwrap(
        await dio.get(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats/$id/messages',
            'after_id': afterId,
          },
          options: authOptions,
        ),
      );

      return (data['items'] as List<dynamic>)
          .map(
            (dynamic item) => MessageItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<MessageItem> sendMessage(
    int id,
    String text,
    XFile? image,
  ) async {
    try {
      final FormData form = FormData.fromMap(
        <String, dynamic>{
          'body': text,
          if (image != null)
            'image': await MultipartFile.fromFile(
              image.path,
              filename: image.name,
            ),
        },
      );

      final Map<String, dynamic> data = await _unwrap(
        await dio.post(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats/$id/messages',
          },
          data: form,
          options: authOptions,
        ),
      );

      return MessageItem.fromJson(
        Map<String, dynamic>.from(data['message'] as Map),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<void> updateStatus(
    int id,
    String adminState,
    String status,
  ) async {
    try {
      await _unwrap(
        await dio.post(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats/$id/status',
          },
          data: <String, String>{
            'admin_state': adminState,
            'status': status,
          },
          options: authOptions,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<void> assignToMe(int id) async {
    try {
      await _unwrap(
        await dio.post(
          apiBase,
          queryParameters: <String, dynamic>{
            'route': 'chats/$id/assign',
          },
          data: const <String, dynamic>{},
          options: authOptions,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<List<QuickReply>> quickReplies() async {
    try {
      final Map<String, dynamic> data = await _unwrap(
        await dio.get(
          apiBase,
          queryParameters: const <String, String>{
            'route': 'quick-replies',
          },
          options: authOptions,
        ),
      );

      return (data['items'] as List<dynamic>)
          .map(
            (dynamic item) => QuickReply.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<void> registerPushToken(String fcmToken) async {
    try {
      await _unwrap(
        await dio.post(
          apiBase,
          queryParameters: const <String, String>{
            'route': 'push/register',
          },
          data: <String, String>{
            'fcm_token': fcmToken,
            'platform': 'android',
            'device_name': 'HotelChat Android',
            'app_version': appVersion,
          },
          options: authOptions,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<void> unregisterPushToken(String fcmToken) async {
    try {
      await _unwrap(
        await dio.post(
          apiBase,
          queryParameters: const <String, String>{
            'route': 'push/unregister',
          },
          data: <String, String>{
            'fcm_token': fcmToken,
          },
          options: authOptions,
        ),
      );
    } on DioException catch (error) {
      throw ApiException(_dioError(error));
    }
  }

  Future<void> logout() async {
    try {
      if (token != null) {
        await dio.post(
          apiBase,
          queryParameters: const <String, String>{
            'route': 'logout',
          },
          options: authOptions,
        );
      }
    } catch (_) {
      // Локальный выход должен сработать даже при недоступном сервере.
    } finally {
      token = null;
      await storage.delete(key: 'api_token');
    }
  }

  String _dioError(DioException error) {
    final dynamic responseData = error.response?.data;

    if (responseData is Map && responseData['error'] != null) {
      return responseData['error'].toString();
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Сервер не ответил вовремя';
      case DioExceptionType.connectionError:
        return 'Нет соединения с сервером';
      default:
        return 'Не удалось связаться с сервером';
    }
  }
}

class ChatItem {
  ChatItem({
    required this.id,
    required this.unread,
    required this.roomNumber,
    required this.roomName,
    required this.guestName,
    required this.category,
    required this.adminState,
    required this.status,
    required this.lastActivity,
    this.assignedName,
    this.lastMessage,
    this.rating,
    this.ratingComment,
  });

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> room =
        Map<String, dynamic>.from(json['room'] as Map);

    return ChatItem(
      id: (json['id'] as num).toInt(),
      unread: ((json['unread'] ?? 0) as num).toInt(),
      roomNumber: room['number'].toString(),
      roomName: room['name'].toString(),
      guestName: json['guest_name']?.toString() ?? 'Гость',
      category: json['category']?.toString() ?? 'other',
      adminState: json['admin_state']?.toString() ?? 'new',
      status: json['status']?.toString() ?? 'open',
      lastActivity:
          DateTime.tryParse(json['last_activity_at']?.toString() ?? '') ??
              DateTime.now(),
      assignedName: json['assigned_name']?.toString(),
      lastMessage: json['last_message']?.toString(),
      rating: json['rating'] == null
          ? null
          : (json['rating'] as num).toInt(),
      ratingComment: json['rating_comment']?.toString(),
    );
  }

  final int id;
  final int unread;
  final String roomNumber;
  final String roomName;
  final String guestName;
  final String category;
  final String adminState;
  final String status;
  final DateTime lastActivity;
  final String? assignedName;
  final String? lastMessage;
  final int? rating;
  final String? ratingComment;
}

class MessageItem {
  MessageItem({
    required this.id,
    required this.sender,
    required this.createdAt,
    this.body,
    this.imageUrl,
  });

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
      id: (json['id'] as num).toInt(),
      sender: json['sender']?.toString() ?? 'guest',
      body: json['body']?.toString(),
      imageUrl: json['image_url']?.toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }

  final int id;
  final String sender;
  final String? body;
  final String? imageUrl;
  final DateTime createdAt;
}

class ChatDetails {
  ChatDetails({
    required this.chat,
    required this.messages,
  });

  final ChatItem chat;
  final List<MessageItem> messages;
}

class QuickReply {
  QuickReply({
    required this.id,
    required this.title,
    required this.bodyRu,
  });

  factory QuickReply.fromJson(Map<String, dynamic> json) {
    return QuickReply(
      id: (json['id'] as num).toInt(),
      title: json['title']?.toString() ?? 'Ответ',
      bodyRu: json['body_ru']?.toString() ?? '',
    );
  }

  final int id;
  final String title;
  final String bodyRu;
}

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  String? _currentToken;
  int? _pendingChatId;
  bool _listenersReady = false;
  bool _initialMessageChecked = false;
  bool _permissionRequested = false;

  Future<void> initializeForSignedInUser() async {
    try {
      await messaging.setAutoInitEnabled(true);

      if (!_permissionRequested) {
        _permissionRequested = true;
        await messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
      }

      if (!_listenersReady) {
        _listenersReady = true;

        _tokenSubscription =
            messaging.onTokenRefresh.listen((String token) {
          _registerToken(token);
        });

        _foregroundSubscription =
            FirebaseMessaging.onMessage.listen(_handleForeground);

        _openedSubscription =
            FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      }

      final String? token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }

      if (!_initialMessageChecked) {
        _initialMessageChecked = true;
        final RemoteMessage? initialMessage =
            await messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleOpen(initialMessage);
        }
      }

      openPendingChat();
    } catch (error) {
      debugPrint('FCM initialization error: $error');
    }
  }

  Future<Map<String, dynamic>> diagnosticStatus() async {
    final Map<String, dynamic> result = <String, dynamic>{
      'appVersion': appVersion,
      'firebaseProject': 'hotelchat-e9c5f',
      'packageName': 'online.ognispb.hotelchat',
      'apiAuthorized': api.token != null,
    };

    try {
      final Map<dynamic, dynamic>? nativeStatus =
          await const MethodChannel('hotelchat/notifications')
              .invokeMapMethod<dynamic, dynamic>('getStatus');
      if (nativeStatus != null) {
        for (final MapEntry<dynamic, dynamic> entry
            in nativeStatus.entries) {
          result[entry.key.toString()] = entry.value;
        }
      }
    } catch (error) {
      result['nativeStatusError'] = error.toString();
    }

    try {
      final NotificationSettings settings =
          await messaging.getNotificationSettings();
      result['firebaseAuthorizationStatus'] =
          settings.authorizationStatus.name;
      result['firebaseAlertSetting'] = settings.alert.name;
      result['firebaseSoundSetting'] = settings.sound.name;
    } catch (error) {
      result['firebaseSettingsError'] = error.toString();
    }

    try {
      final String? token = await messaging
          .getToken()
          .timeout(const Duration(seconds: 25));

      result['fcmTokenCreated'] =
          token != null && token.isNotEmpty;
      result['fcmTokenPreview'] =
          token == null || token.isEmpty
              ? ''
              : '${token.substring(0, token.length > 24 ? 24 : token.length)}…';

      if (token != null && token.isNotEmpty) {
        _currentToken = token;

        try {
          await api.registerPushToken(token);
          result['serverRegistration'] = 'success';
        } catch (error) {
          result['serverRegistration'] = 'failed';
          result['serverRegistrationError'] = error.toString();
        }
      }
    } catch (error) {
      result['fcmTokenCreated'] = false;
      result['fcmTokenError'] = error.toString();
    }

    return result;
  }

  Future<Map<String, dynamic>> requestPermissionAndRegister() async {
    final Map<String, dynamic> result = <String, dynamic>{};

    try {
      final bool? nativeGranted =
          await const MethodChannel('hotelchat/notifications')
              .invokeMethod<bool>('requestPermission');
      result['nativePermissionGranted'] = nativeGranted;
    } catch (error) {
      result['nativePermissionError'] = error.toString();
    }

    try {
      final NotificationSettings settings =
          await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      result['firebaseAuthorizationStatus'] =
          settings.authorizationStatus.name;
    } catch (error) {
      result['firebasePermissionError'] = error.toString();
    }

    result.addAll(await diagnosticStatus());
    return result;
  }

  Future<void> openNotificationSettings() async {
    await const MethodChannel('hotelchat/notifications')
        .invokeMethod<void>('openNotificationSettings');
  }

  Future<void> _registerToken(String token) async {
    _currentToken = token;

    if (api.token == null) return;

    try {
      await api.registerPushToken(token);
    } catch (error) {
      debugPrint('FCM token registration error: $error');
    }
  }

  Future<void> unregisterCurrentToken() async {
    final String? token = _currentToken;

    if (token == null || api.token == null) return;

    try {
      await api.unregisterPushToken(token);
    } catch (error) {
      debugPrint('FCM token unregister error: $error');
    }
  }

  void _handleForeground(RemoteMessage message) {
    chatRefreshSignal.value++;

    final int? chatId = _chatId(message);
    final String title =
        message.notification?.title ?? 'Новое сообщение';
    final String body =
        message.notification?.body ?? 'Откройте HotelChat';

    final BuildContext? context = appNavigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        action: chatId == null
            ? null
            : SnackBarAction(
                label: 'Открыть',
                onPressed: () => _openChat(chatId),
              ),
      ),
    );
  }

  void _handleOpen(RemoteMessage message) {
    final int? chatId = _chatId(message);
    if (chatId != null) {
      _openChat(chatId);
    }
  }

  int? _chatId(RemoteMessage message) {
    final dynamic raw = message.data['chat_id'];
    return raw == null ? null : int.tryParse(raw.toString());
  }

  void _openChat(int chatId) {
    if (api.token == null || appNavigatorKey.currentState == null) {
      _pendingChatId = chatId;
      return;
    }

    _pendingChatId = null;
    appNavigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatScreen(
          chatId: chatId,
        ),
      ),
    );
  }

  void openPendingChat() {
    final int? chatId = _pendingChatId;
    if (chatId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openChat(chatId);
    });
  }
}

final ApiClient api = ApiClient();

class HotelChatApp extends StatefulWidget {
  const HotelChatApp({super.key});

  @override
  State<HotelChatApp> createState() => _HotelChatAppState();
}

class _HotelChatAppState extends State<HotelChatApp> {
  bool ready = false;
  bool loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await api.loadToken();

    if (api.token != null) {
      try {
        await api.me();
        loggedIn = true;
      } catch (_) {
        await api.logout();
      }
    }

    if (mounted) {
      setState(() => ready = true);

      if (loggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PushService.instance.initializeForSignedInUser();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'HotelChat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff245fdb),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff5f7fb),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6d9cff),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: !ready
          ? const SplashScreen()
          : loggedIn
              ? HomeScreen(
                  onLogout: () {
                    setState(() => loggedIn = false);
                  },
                )
              : LoginScreen(
                  onLogin: () {
                    setState(() => loggedIn = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      PushService.instance.initializeForSignedInUser();
                    });
                  },
                ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onLogin,
    super.key,
  });

  final VoidCallback onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController loginController =
      TextEditingController();
  final TextEditingController passwordController =
      TextEditingController();

  bool loading = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    loginController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (loading) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      await api.login(
        loginController.text.trim(),
        passwordController.text,
      );

      if (mounted) {
        widget.onLogin();
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const CircleAvatar(
                          radius: 34,
                          child: Icon(Icons.hotel_rounded, size: 36),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'HotelChat',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Вход для сотрудников',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: loginController,
                          autofillHints: const <String>[
                            AutofillHints.username,
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Логин',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: passwordController,
                          obscureText: obscure,
                          autofillHints: const <String>[
                            AutofillHints.password,
                          ],
                          onSubmitted: (_) => submit(),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            prefixIcon:
                                const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() => obscure = !obscure);
                              },
                              icon: Icon(
                                obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                        ),
                        if (error != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: loading ? null : () => submit(),
                          icon: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: const Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: 13),
                            child: Text('Войти'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PushDiagnosticsScreen extends StatefulWidget {
  const PushDiagnosticsScreen({super.key});

  @override
  State<PushDiagnosticsScreen> createState() =>
      _PushDiagnosticsScreenState();
}

class _PushDiagnosticsScreenState
    extends State<PushDiagnosticsScreen> {
  Map<String, dynamic> status = <String, dynamic>{};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => loading = true);

    final Map<String, dynamic> value =
        await PushService.instance.diagnosticStatus();

    if (!mounted) return;
    setState(() {
      status = value;
      loading = false;
    });
  }

  Future<void> requestAndRegister() async {
    setState(() => loading = true);

    final Map<String, dynamic> value =
        await PushService.instance.requestPermissionAndRegister();

    if (!mounted) return;
    setState(() {
      status = value;
      loading = false;
    });
  }

  String displayValue(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'да' : 'нет';
    return value.toString();
  }

  Widget statusRow(String title, String key) {
    final dynamic value = status[key];
    final bool isError = key.toLowerCase().contains('error');
    final bool isGood = value == true || value == 'success';

    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(
        displayValue(value),
        style: TextStyle(
          color: isError && value != null
              ? Theme.of(context).colorScheme.error
              : null,
          fontWeight: isGood ? FontWeight.w700 : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика уведомлений'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Здесь видно, вошло ли разрешение в APK, '
                    'разрешил ли его Android, создался ли FCM-токен '
                    'и зарегистрировал ли его сервер.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                statusRow('Версия приложения', 'appVersion'),
                statusRow('Версия Android SDK', 'sdkInt'),
                statusRow(
                  'Разрешение объявлено в APK',
                  'permissionDeclared',
                ),
                statusRow(
                  'Разрешение выдано Android',
                  'permissionGranted',
                ),
                statusRow(
                  'Уведомления включены системой',
                  'notificationsEnabled',
                ),
                statusRow(
                  'Канал уведомлений создан',
                  'channelExists',
                ),
                statusRow(
                  'Важность канала',
                  'channelImportance',
                ),
                statusRow(
                  'Статус Firebase',
                  'firebaseAuthorizationStatus',
                ),
                statusRow(
                  'FCM-токен создан',
                  'fcmTokenCreated',
                ),
                statusRow(
                  'Начало FCM-токена',
                  'fcmTokenPreview',
                ),
                statusRow(
                  'Регистрация на сервере',
                  'serverRegistration',
                ),
                statusRow(
                  'Ошибка FCM-токена',
                  'fcmTokenError',
                ),
                statusRow(
                  'Ошибка регистрации сервера',
                  'serverRegistrationError',
                ),
                statusRow(
                  'Ошибка нативной проверки',
                  'nativeStatusError',
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    onPressed: requestAndRegister,
                    icon: const Icon(Icons.notifications_active),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Запросить разрешение и зарегистрировать',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await PushService.instance
                          .openNotificationSettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text(
                      'Открыть настройки уведомлений Android',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить проверку'),
                  ),
                ),
              ],
            ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onLogout,
    super.key,
  });

  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  List<ChatItem> items = <ChatItem>[];
  bool loading = true;
  bool requestRunning = false;
  String selectedStatus = 'open';
  Timer? timer;
  String? error;
  late final VoidCallback pushRefreshListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pushRefreshListener = () => load(silent: true);
    chatRefreshSignal.addListener(pushRefreshListener);
    load();
    timer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => load(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    chatRefreshSignal.removeListener(pushRefreshListener);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load(silent: true);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (requestRunning) return;
    requestRunning = true;

    if (!silent && mounted) {
      setState(() => loading = true);
    }

    try {
      final List<ChatItem> loadedItems =
          await api.chats(status: selectedStatus);

      loadedItems.sort(
        (ChatItem first, ChatItem second) =>
            second.lastActivity.compareTo(first.lastActivity),
      );

      if (!mounted) return;

      setState(() {
        items = loadedItems;
        error = null;
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception.toString());
      }
    } finally {
      requestRunning = false;

      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> logout() async {
    await PushService.instance.unregisterCurrentToken();
    await api.logout();

    if (mounted) {
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обращения'),
        actions: <Widget>[
          IconButton(
            onPressed: () => load(),
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'notifications') {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const PushDiagnosticsScreen(),
                  ),
                );
              } else if (value == 'logout') {
                logout();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'notifications',
                child: ListTile(
                  leading: Icon(Icons.notifications_active_outlined),
                  title: Text('Диагностика уведомлений'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Выйти'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'open',
                  label: Text('Активные'),
                  icon: Icon(Icons.chat_bubble_outline),
                ),
                ButtonSegment<String>(
                  value: 'closed',
                  label: Text('Закрытые'),
                  icon: Icon(Icons.check_circle_outline),
                ),
              ],
              selected: <String>{selectedStatus},
              onSelectionChanged: (Set<String> selection) {
                setState(() {
                  selectedStatus = selection.first;
                  items = <ChatItem>[];
                });
                load();
              },
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => load(),
                    child: items.isEmpty
                        ? ListView(
                            children: const <Widget>[
                              Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: Text('Обращений нет'),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: items.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final ChatItem chat = items[index];

                              return Card(
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    child: Text(chat.roomNumber),
                                  ),
                                  title: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          chat.roomName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (chat.unread > 0)
                                        Badge(
                                          label:
                                              Text('${chat.unread}'),
                                        ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const SizedBox(height: 4),
                                      Text(
                                        chat.lastMessage?.isNotEmpty ==
                                                true
                                            ? chat.lastMessage!
                                            : 'Нет текстового сообщения',
                                        maxLines: 2,
                                        overflow:
                                            TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: <Widget>[
                                          Chip(
                                            label: Text(
                                              categoryName(
                                                chat.category,
                                              ),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          Chip(
                                            label: Text(
                                              stateName(
                                                chat.adminState,
                                              ),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    DateFormat('HH:mm').format(
                                      chat.lastActivity,
                                    ),
                                  ),
                                  onTap: () async {
                                    await Navigator.push<void>(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder:
                                            (BuildContext context) =>
                                                ChatScreen(
                                          chatId: chat.id,
                                        ),
                                      ),
                                    );

                                    if (mounted) {
                                      load(silent: true);
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chatId,
    super.key,
  });

  final int chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController messageController =
      TextEditingController();
  final ScrollController scrollController = ScrollController();

  ChatDetails? details;
  bool loading = true;
  bool sending = false;
  bool polling = false;
  Timer? timer;
  XFile? pendingImage;
  List<QuickReply> replies = <QuickReply>[];

  @override
  void initState() {
    super.initState();
    load();

    api.quickReplies().then((List<QuickReply> value) {
      if (mounted) {
        setState(() => replies = value);
      }
    }).catchError((Object _) {
      // Быстрые ответы необязательны для работы чата.
    });

    timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => poll(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final ChatDetails loadedDetails =
          await api.chat(widget.chatId);

      if (!mounted) return;

      setState(() {
        details = loadedDetails;
        loading = false;
      });

      scrollToBottom();
    } catch (exception) {
      if (mounted) {
        setState(() => loading = false);
        showMessage(exception.toString());
      }
    }
  }

  Future<void> poll() async {
    if (details == null || polling) return;

    polling = true;

    try {
      final int afterId = details!.messages.isEmpty
          ? 0
          : details!.messages.last.id;

      final List<MessageItem> newMessages =
          await api.messages(widget.chatId, afterId);

      if (newMessages.isNotEmpty && mounted) {
        setState(() {
          details!.messages.addAll(newMessages);
        });
        scrollToBottom();
      }
    } catch (_) {
      // Следующий цикл повторит запрос.
    } finally {
      polling = false;
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> send() async {
    final String text = messageController.text.trim();
    final XFile? image = pendingImage;

    if (sending || (text.isEmpty && image == null)) return;

    setState(() => sending = true);

    try {
      final MessageItem message =
          await api.sendMessage(widget.chatId, text, image);

      if (!mounted || details == null) return;

      messageController.clear();

      setState(() {
        pendingImage = null;
        details!.messages.add(message);
      });

      scrollToBottom();
    } catch (exception) {
      showMessage(exception.toString());
    } finally {
      if (mounted) {
        setState(() => sending = false);
      }
    }
  }

  Future<void> pickImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(
                context,
                ImageSource.gallery,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фотографию'),
              onTap: () => Navigator.pop(
                context,
                ImageSource.camera,
              ),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (image != null && mounted) {
      setState(() => pendingImage = image);
    }
  }

  Future<void> updateChatState(
    String adminState,
    String status,
  ) async {
    try {
      await api.updateStatus(
        widget.chatId,
        adminState,
        status,
      );
      await load();
    } catch (exception) {
      showMessage(exception.toString());
    }
  }

  Future<void> assignToMe() async {
    try {
      await api.assignToMe(widget.chatId);
      showMessage('Обращение назначено вам');
      await load();
    } catch (exception) {
      showMessage(exception.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatItem? chat = details?.chat;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          chat == null ? 'Чат' : 'Номер ${chat.roomNumber}',
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'assign':
                  assignToMe();
                  break;
                case 'progress':
                  updateChatState('in_progress', 'open');
                  break;
                case 'waiting':
                  updateChatState('waiting', 'open');
                  break;
                case 'close':
                  updateChatState('done', 'closed');
                  break;
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'assign',
                child: Text('Назначить на себя'),
              ),
              PopupMenuItem<String>(
                value: 'progress',
                child: Text('В работе'),
              ),
              PopupMenuItem<String>(
                value: 'waiting',
                child: Text('Ожидает'),
              ),
              PopupMenuItem<String>(
                value: 'close',
                child: Text('Закрыть обращение'),
              ),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : details == null
              ? const Center(
                  child: Text('Не удалось открыть обращение'),
                )
              : Column(
                  children: <Widget>[
                    if (chat != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Text(
                          '${categoryName(chat.category)} · '
                          '${stateName(chat.adminState)}'
                          '${chat.assignedName == null ? '' : ' · ${chat.assignedName}'}',
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: details!.messages.length,
                        itemBuilder:
                            (BuildContext context, int index) {
                          final MessageItem message =
                              details!.messages[index];
                          final bool mine =
                              message.sender == 'admin';

                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(10),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width *
                                        0.78,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (message.imageUrl != null)
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      child: Image.network(
                                        message.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (
                                          BuildContext context,
                                          Object error,
                                          StackTrace? stackTrace,
                                        ) =>
                                            const SizedBox(
                                          height: 120,
                                          child: Center(
                                            child: Icon(
                                              Icons.broken_image,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (message.body?.isNotEmpty ==
                                      true) ...<Widget>[
                                    if (message.imageUrl != null)
                                      const SizedBox(height: 8),
                                    Text(message.body!),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('HH:mm').format(
                                      message.createdAt,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (replies.isNotEmpty)
                      SizedBox(
                        height: 46,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          itemCount: replies.length,
                          separatorBuilder:
                              (BuildContext context, int index) =>
                                  const SizedBox(width: 6),
                          itemBuilder:
                              (BuildContext context, int index) {
                            final QuickReply reply = replies[index];

                            return ActionChip(
                              label: Text(reply.title),
                              onPressed: () {
                                messageController.text =
                                    reply.bodyRu;
                                messageController.selection =
                                    TextSelection.collapsed(
                                  offset:
                                      messageController.text.length,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    if (pendingImage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: <Widget>[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(pendingImage!.path),
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace,
                                    ) =>
                                        const SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    pendingImage!.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  onPressed: sending
                                      ? null
                                      : () {
                                          setState(() {
                                            pendingImage = null;
                                          });
                                        },
                                  tooltip: 'Убрать фотографию',
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: Row(
                          children: <Widget>[
                            IconButton(
                              onPressed:
                                  sending ? null : () => pickImage(),
                              tooltip: 'Прикрепить фотографию',
                              icon:
                                  const Icon(Icons.photo_outlined),
                            ),
                            Expanded(
                              child: TextField(
                                controller: messageController,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Сообщение',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filled(
                              onPressed:
                                  sending ? null : () => send(),
                              icon: sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

String categoryName(String code) {
  return const <String, String>{
        'cleaning': 'Уборка',
        'linen': 'Бельё',
        'towels': 'Полотенца',
        'repair': 'Поломка',
        'taxi': 'Такси',
        'restaurant': 'Ресторан',
        'wifi': 'Wi‑Fi',
        'other': 'Другое',
      }[code] ??
      code;
}

String stateName(String code) {
  return const <String, String>{
        'new': 'Новое',
        'in_progress': 'В работе',
        'waiting': 'Ожидает',
        'done': 'Выполнено',
      }[code] ??
      code;
}
