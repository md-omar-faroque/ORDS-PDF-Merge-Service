#!/usr/bin/env bash
set -euo pipefail

PDF_DIR="${PDF_DIR:-/mysoft/file_attachment/prescription}"
PDFUNITE="${PDFUNITE:-/usr/bin/pdfunite}"

echo "Checking pdfunite..."
if [[ -x "$PDFUNITE" ]]; then
  "$PDFUNITE" -v 2>&1 | head -n 2 || true
else
  echo "ERROR: $PDFUNITE is missing or not executable." >&2
  echo "On Oracle Linux/RHEL, install it with: dnf install -y poppler-utils" >&2
  exit 1
fi

echo
echo "Checking directory..."
if [[ -d "$PDF_DIR" ]]; then
  ls -ld "$PDF_DIR"
else
  echo "ERROR: directory does not exist: $PDF_DIR" >&2
  exit 1
fi

if [[ -r "$PDF_DIR" && -w "$PDF_DIR" && -x "$PDF_DIR" ]]; then
  echo "Current user has directory read/write/search permissions."
else
  echo "WARNING: current user may not have required read/write/search permissions." >&2
fi

echo
echo "Run this script as the Oracle OS account to validate the same permissions Oracle JVM will use."
