#!/usr/bin/env bash
# getburpcert.sh — extract Burp Suite CA certificate in headless mode
# Usage: getburpcert.sh
# Output: /tmp/BurpSuiteCA.der  (then imported by Ansible)
set -uo pipefail

CERT_OUT="/tmp/BurpSuiteCA.der"
BURP_JAR=""

echo "[*] Locating Burp Suite JAR..."

# Check known Kali install locations first
for candidate in \
  /usr/share/burpsuite/burpsuite.jar \
  /opt/BurpSuitePro/burpsuite_pro.jar \
  /opt/BurpSuiteCommunity/burpsuite_community.jar; do
  if [[ -f "$candidate" ]]; then
    BURP_JAR="$candidate"
    break
  fi
done

# Fall back to filesystem search if not found in known locations
if [[ -z "$BURP_JAR" ]]; then
  BURP_JAR="$(find /usr /opt /home -name 'burpsuite*.jar' 2>/dev/null | grep -v '.bak' | sort | tail -1 || true)"
fi

if [[ -z "$BURP_JAR" ]]; then
  echo "[!] Burp Suite JAR not found. Is Burp installed?"
  exit 1
fi
echo "[+] Found: $BURP_JAR"

# Locate bundled JRE (Burp ships its own)
BURP_JRE="$(dirname "$BURP_JAR")/../jre/bin/java"
if [[ -x "$BURP_JRE" ]]; then
  JAVA="$BURP_JRE"
else
  JAVA="$(command -v java)"
fi

# Launch Burp headlessly. Pipe 'yes' to auto-accept the T&C prompt that
# Burp Community prints on first run before it will start listening.
echo "[*] Launching Burp in headless mode (auto-accepting T&C)..."
yes | timeout 90 "$JAVA" -Djava.awt.headless=true -jar "$BURP_JAR" &
BURP_PID=$!

echo "[*] Waiting 40s for Burp to initialise..."
sleep 40

echo "[*] Fetching CA certificate from :8080..."
if curl -sf http://127.0.0.1:8080/cert -o "$CERT_OUT"; then
  echo "[+] Certificate saved to $CERT_OUT"
else
  echo "[!] Failed to fetch cert — is Burp listening on :8080?"
  kill "$BURP_PID" 2>/dev/null || true
  exit 1
fi

kill "$BURP_PID" 2>/dev/null || true
echo "[+] Done."
