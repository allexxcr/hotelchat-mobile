#!/usr/bin/env python3
"""Configure generated Flutter Android files for HotelChat + Firebase."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
APP_ID = "online.ognispb.hotelchat"
APP_LABEL = "HotelChat"
MIN_SDK = 23
GOOGLE_SERVICES_PLUGIN = "4.5.0"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def insert_plugin(text: str, line: str) -> str:
    if "com.google.gms.google-services" in text:
        return text

    match = re.search(r"plugins\s*\{\s*", text)
    if not match:
        fail("Gradle plugins block was not found")

    return text[:match.end()] + "\n    " + line + text[match.end():]


def configure_settings() -> None:
    kotlin_file = ANDROID / "settings.gradle.kts"
    groovy_file = ANDROID / "settings.gradle"

    if kotlin_file.exists():
        text = kotlin_file.read_text(encoding="utf-8")
        text = insert_plugin(
            text,
            f'id("com.google.gms.google-services") version '
            f'"{GOOGLE_SERVICES_PLUGIN}" apply false\n',
        )
        kotlin_file.write_text(text, encoding="utf-8")
        return

    if groovy_file.exists():
        text = groovy_file.read_text(encoding="utf-8")
        text = insert_plugin(
            text,
            f"id 'com.google.gms.google-services' version "
            f"'{GOOGLE_SERVICES_PLUGIN}' apply false\n",
        )
        groovy_file.write_text(text, encoding="utf-8")
        return

    fail("Android settings Gradle file was not generated")


def configure_gradle() -> None:
    kotlin_file = ANDROID / "app" / "build.gradle.kts"
    groovy_file = ANDROID / "app" / "build.gradle"

    if kotlin_file.exists():
        text = kotlin_file.read_text(encoding="utf-8")
        text = insert_plugin(
            text,
            'id("com.google.gms.google-services")\n',
        )
        text, count_namespace = re.subn(
            r'namespace\s*=\s*["\'][^"\']+["\']',
            f'namespace = "{APP_ID}"',
            text,
            count=1,
        )
        text, count_app_id = re.subn(
            r'applicationId\s*=\s*["\'][^"\']+["\']',
            f'applicationId = "{APP_ID}"',
            text,
            count=1,
        )
        text, count_min_sdk = re.subn(
            r'minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)',
            f'minSdk = {MIN_SDK}',
            text,
            count=1,
        )

        if not all((count_namespace, count_app_id, count_min_sdk)):
            fail("Expected Android values missing in build.gradle.kts")

        kotlin_file.write_text(text, encoding="utf-8")
        return

    if groovy_file.exists():
        text = groovy_file.read_text(encoding="utf-8")
        text = insert_plugin(
            text,
            "id 'com.google.gms.google-services'\n",
        )
        text, count_namespace = re.subn(
            r'namespace\s*(?:=)?\s*["\'][^"\']+["\']',
            f'namespace "{APP_ID}"',
            text,
            count=1,
        )
        text, count_app_id = re.subn(
            r'applicationId\s+["\'][^"\']+["\']',
            f'applicationId "{APP_ID}"',
            text,
            count=1,
        )
        text, count_min_sdk = re.subn(
            r'minSdkVersion\s+(?:flutter\.minSdkVersion|\d+)',
            f'minSdkVersion {MIN_SDK}',
            text,
            count=1,
        )

        if not all((count_namespace, count_app_id, count_min_sdk)):
            fail("Expected Android values missing in build.gradle")

        groovy_file.write_text(text, encoding="utf-8")
        return

    fail("Android app Gradle file was not generated")


def configure_main_activity() -> None:
    main_root = ANDROID / "app" / "src" / "main"
    kotlin_root = main_root / "kotlin"
    java_root = main_root / "java"

    for root in (kotlin_root, java_root):
        if root.exists():
            for source in root.rglob("MainActivity.kt"):
                source.unlink()
            for source in root.rglob("MainActivity.java"):
                source.unlink()

    destination = (
        kotlin_root / Path(*APP_ID.split(".")) / "MainActivity.kt"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        f"""package {APP_ID}

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {{
    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
            val channel = NotificationChannel(
                "hotelchat_messages",
                "Сообщения HotelChat",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Новые сообщения гостей"
            channel.enableVibration(true)

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }}
    }}
}}
""",
        encoding="utf-8",
    )


def configure_manifest() -> None:
    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        fail("AndroidManifest.xml was not generated")

    text = manifest.read_text(encoding="utf-8")
    text, label_count = re.subn(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        text,
        count=1,
    )
    if label_count == 0:
        fail("Application label missing in AndroidManifest.xml")

    permissions = [
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    ]

    for permission in permissions:
        if permission not in text:
            manifest_end = text.find(">")
            if manifest_end == -1:
                fail("Malformed AndroidManifest.xml")
            text = (
                text[:manifest_end + 1]
                + "\n    "
                + permission
                + text[manifest_end + 1:]
            )

    metadata = """        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="hotelchat_messages" />
"""
    if "default_notification_channel_id" not in text:
        application_match = re.search(r"<application\b[^>]*>", text)
        if not application_match:
            fail("Application tag missing in AndroidManifest.xml")
        text = (
            text[:application_match.end()]
            + "\n"
            + metadata
            + text[application_match.end():]
        )

    manifest.write_text(text, encoding="utf-8")


def verify() -> None:
    google_services = ANDROID / "app" / "google-services.json"
    if not google_services.exists():
        fail("android/app/google-services.json is missing")

    settings_candidates = [
        ANDROID / "settings.gradle.kts",
        ANDROID / "settings.gradle",
    ]
    settings = next(
        (path for path in settings_candidates if path.exists()),
        None,
    )
    if settings is None:
        fail("Settings Gradle file missing")
    if "com.google.gms.google-services" not in settings.read_text(
        encoding="utf-8"
    ):
        fail("Google services settings plugin missing")

    gradle_candidates = [
        ANDROID / "app" / "build.gradle.kts",
        ANDROID / "app" / "build.gradle",
    ]
    gradle = next(
        (path for path in gradle_candidates if path.exists()),
        None,
    )
    if gradle is None:
        fail("App Gradle file missing")

    gradle_text = gradle.read_text(encoding="utf-8")
    for required in (
        APP_ID,
        "com.google.gms.google-services",
    ):
        if required not in gradle_text:
            fail(f"Missing Gradle value: {required}")

    activity = (
        ANDROID
        / "app"
        / "src"
        / "main"
        / "kotlin"
        / Path(*APP_ID.split("."))
        / "MainActivity.kt"
    )
    activity_text = activity.read_text(encoding="utf-8")
    if "hotelchat_messages" not in activity_text:
        fail("Notification channel missing from MainActivity.kt")
    if "FlutterActivity" not in activity_text:
        fail("FlutterActivity missing from MainActivity.kt")

    manifest = (
        ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    ).read_text(encoding="utf-8")
    for required in (
        "android.permission.INTERNET",
        "android.permission.POST_NOTIFICATIONS",
        "default_notification_channel_id",
        'android:label="HotelChat"',
    ):
        if required not in manifest:
            fail(f"Missing manifest value: {required}")

    print("Android/Firebase configuration verified")
    print(f"  package: {APP_ID}")
    print(f"  google-services plugin: {GOOGLE_SERVICES_PLUGIN}")
    print("  notification channel: hotelchat_messages")


def main() -> None:
    if not ANDROID.exists():
        fail("Run flutter create before this script")

    configure_settings()
    configure_gradle()
    configure_main_activity()
    configure_manifest()
    verify()


if __name__ == "__main__":
    main()
