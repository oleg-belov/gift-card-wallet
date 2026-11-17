#!/usr/bin/env bash
# Patches cryptography_flutter's Android MethodCallHandler in the pub cache
# so crypto work runs on a background thread.
#
# The stock plugin executes PBKDF2 (SecretKeyFactory.generateSecret with
# 200k iterations) synchronously inside onMethodCall — i.e. on the Android
# MAIN thread. Unlocking the app then stalls the UI thread for seconds and
# trips "Lidl Gift Card isn't responding" (ANR) on cold starts. MethodChannel
# results may be completed from any thread, so simply moving the dispatch to
# a worker thread fixes it without touching Dart code.
#
# `flutter pub get` restores the original file whenever the pub cache is
# repaired or re-downloaded — re-run this script after that.
set -euo pipefail

FILE="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/cryptography_flutter-2.3.4/android/src/main/kotlin/dev/dint/cryptography_flutter/CryptographyFlutterPlugin.kt"

if [[ ! -f "$FILE" ]]; then
  echo "Not found: $FILE"
  echo "Run 'flutter pub get' first, or adjust the version in this script."
  exit 1
fi

if grep -q "runOnWorkerThread" "$FILE"; then
  echo "Already patched: $FILE"
  exit 0
fi

python3 - "$FILE" << 'PYEOF'
import sys

path = sys.argv[1]
s = open(path).read()

old_head = """    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {"""
new_head = """    override fun onMethodCall(call: MethodCall, result: Result) {
        // [patch] PBKDF2/HMAC can take seconds (200k+ iterations) and the
        // stock plugin runs them on the MAIN thread, which ANRs the app.
        // MethodChannel results may be completed from any thread, so the
        // whole dispatch below runs on a worker thread instead.
        runOnWorkerThread {
        try {
            when (call.method) {"""
assert old_head in s, 'onMethodCall head not found'
s = s.replace(old_head, new_head, 1)

old_tail = """        } catch (e: Throwable) {
            result.error(
                "CAUGHT_ERROR",
                "Unexpected error ${e}: ${e.message}\\nCause: ${e.cause}\\nStack stace:\\n${e.stackTraceToString()}",
                null
            )
        }
    }

    private fun androidCryptoProviders(call: MethodCall, result: Result) {"""
new_tail = """        } catch (e: Throwable) {
            result.error(
                "CAUGHT_ERROR",
                "Unexpected error ${e}: ${e.message}\\nCause: ${e.cause}\\nStack stace:\\n${e.stackTraceToString()}",
                null
            )
        }
        }
    }

    private fun runOnWorkerThread(block: () -> Unit) {
        Thread(block).start()
    }

    private fun androidCryptoProviders(call: MethodCall, result: Result) {"""
assert old_tail in s, 'onMethodCall tail not found'
s = s.replace(old_tail, new_tail, 1)

open(path, 'w').write(s)
print('patched', path)
PYEOF
echo "Patch applied."
