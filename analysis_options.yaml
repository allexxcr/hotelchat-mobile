import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('HotelChat Mobile supports Android only.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'HotelChat Mobile supports Android only.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAEdVA1hgkciztH7p8yFOLf4fXkiL6qwyA',
    appId: '1:974419434347:android:c7080beb80ee8d26ee8a2e',
    messagingSenderId: '974419434347',
    projectId: 'hotelchat-e9c5f',
    storageBucket: 'hotelchat-e9c5f.firebasestorage.app',
  );
}
