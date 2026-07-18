#!/usr/bin/env python3
"""Configure generated Flutter Android files for HotelChat."""

from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
APP_ID = "online.ognispb.hotelchat"
APP_LABEL = "HotelChat"
MIN_SDK = 23


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def configure_gradle() -> None:
    kotlin_file = ANDROID / "app" / "build.gradle.kts"
    groovy_file = ANDROID / "app" / "build.gradle"

    if kotlin_file.exists():
        text = kotlin_file.read_text(encoding="utf-8")
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
            fail("Expected Android values were not found in build.gradle.kts")

        kotlin_file.write_text(text, encoding="utf-8")
        return

    if groovy_file.exists():
        text = groovy_file.read_text(encoding="utf-8")
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
            fail("Expected Android values were not found in build.gradle")

        groovy_file.write_text(text, encoding="utf-8")
        return

    fail("Android app Gradle file was not generated")


def configure_main_activity() -> None:
    main_root = ANDROID / "app" / "src" / "main"
    kotlin_root = main_root / "kotlin"
    java_root = main_root / "java"

    # Remove every generated MainActivity so an old package cannot be compiled.
    for root in (kotlin_root, java_root):
        if root.exists():
            for source in root.rglob("MainActivity.kt"):
                source.unlink()
            for source in root.rglob("MainActivity.java"):
                source.unlink()

    destination = (
        kotlin_root
        / Path(*APP_ID.split("."))
        / "MainActivity.kt"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)

    # Write the complete Kotlin file instead of modifying the generated package
    # line. This prevents accidental newline removal and malformed imports.
    destination.write_text(
        f"""package {APP_ID}

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
""",
        encoding="utf-8",
    )

    # Remove empty old package directories.
    for root in (kotlin_root, java_root):
        if not root.exists():
            continue
        directories = sorted(
            (path for path in root.rglob("*") if path.is_dir()),
            key=lambda path: len(path.parts),
            reverse=True,
        )
        for directory in directories:
            try:
                directory.rmdir()
            except OSError:
                pass


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
        fail("Application label was not found in AndroidManifest.xml")

    permission = (
        '<uses-permission android:name="android.permission.INTERNET"/>'
    )
    if permission not in text:
        manifest_end = text.find(">")
        if manifest_end == -1:
            fail("Malformed AndroidManifest.xml")
        text = (
            text[: manifest_end + 1]
            + "\n    "
            + permission
            + text[manifest_end + 1 :]
        )

    manifest.write_text(text, encoding="utf-8")


def verify() -> None:
    gradle_candidates = [
        ANDROID / "app" / "build.gradle.kts",
        ANDROID / "app" / "build.gradle",
    ]
    gradle = next(
        (path for path in gradle_candidates if path.exists()),
        None,
    )
    if gradle is None:
        fail("Gradle file missing during verification")

    gradle_text = gradle.read_text(encoding="utf-8")
    if APP_ID not in gradle_text:
        fail("Application ID was not configured")
    if (
        f"minSdk = {MIN_SDK}" not in gradle_text
        and f"minSdkVersion {MIN_SDK}" not in gradle_text
    ):
        fail("Minimum Android SDK was not configured")

    activity = (
        ANDROID
        / "app"
        / "src"
        / "main"
        / "kotlin"
        / Path(*APP_ID.split("."))
        / "MainActivity.kt"
    )
    if not activity.exists():
        fail("MainActivity.kt is missing")

    expected_activity = f"""package {APP_ID}

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
"""
    actual_activity = activity.read_text(encoding="utf-8")
    if actual_activity != expected_activity:
        fail("MainActivity.kt content is malformed")

    all_activities = list(
        (ANDROID / "app" / "src" / "main").rglob("MainActivity.*")
    )
    if len(all_activities) != 1:
        fail(
            f"Expected one MainActivity file, found {len(all_activities)}"
        )

    manifest = (
        ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    ).read_text(encoding="utf-8")
    if f'android:label="{APP_LABEL}"' not in manifest:
        fail("Application label was not configured")
    if "android.permission.INTERNET" not in manifest:
        fail("Internet permission is missing")

    print("Android configuration verified:")
    print(f"  applicationId: {APP_ID}")
    print(f"  label: {APP_LABEL}")
    print(f"  minSdk: {MIN_SDK}")
    print(f"  MainActivity: {activity}")
    print("--- MainActivity.kt ---")
    print(actual_activity, end="")
    print("-----------------------")


def main() -> None:
    if not ANDROID.exists():
        fail("Run flutter create before this script")

    configure_gradle()
    configure_main_activity()
    configure_manifest()
    verify()


if __name__ == "__main__":
    main()
