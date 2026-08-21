#!/usr/bin/env bash
#
# MyPocketOS - live-build ビルドスクリプト
# clean -> config -> build の順に実行し、ログを build.log に保存する。
#
set -euo pipefail

cd "$(dirname "$0")/.."

LOG_FILE="build.log"
: > "${LOG_FILE}"

log_and_run() {
    echo "==> $*" | tee -a "${LOG_FILE}"
    "$@" 2>&1 | tee -a "${LOG_FILE}"
}

log_and_run sudo lb clean
log_and_run lb config
log_and_run sudo lb build

echo "==> Build finished. See ${LOG_FILE}" | tee -a "${LOG_FILE}"
