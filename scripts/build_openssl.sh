#!/usr/bin/env bash
set -euo pipefail

PREFIX=${OPENSSL_PREFIX:-vendor/openssl}
VERSION=${OPENSSL_VERSION:-1.1.1w}
URL="https://www.openssl.org/source/openssl-${VERSION}.tar.gz"

# Capture project root before leaving it, so we install into the repo not the temp dir.
PROJECT_ROOT=$(pwd)
INSTALL_PREFIX="${PROJECT_ROOT}/${PREFIX}"

echo "[*] Building OpenSSL ${VERSION} -> ${INSTALL_PREFIX}"
mkdir -p "${INSTALL_PREFIX}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
pushd "$WORKDIR" >/dev/null
curl -sSL "$URL" -o src.tar.gz
tar xf src.tar.gz
cd "openssl-${VERSION}"
echo "[*] Configuring..."
./config --prefix="${INSTALL_PREFIX}" no-shared 1>/dev/null
echo "[*] Building... (JOBS=${JOBS:-4})"
make -j"${JOBS:-4}" 1>/dev/null
echo "[*] Installing..."
make install_sw 1>/dev/null
popd >/dev/null

echo "[*] Finished. Artifacts:"
ls -l "${INSTALL_PREFIX}/lib" | grep -E 'lib(ssl|crypto)\.a' || echo "[!] Libraries not found (unexpected)"
echo "[*] To use: set WEBSOCKET_TLS=1 WEBSOCKET_OPENSSL_LOCAL=${PREFIX} (or edit lakefile) and rebuild."