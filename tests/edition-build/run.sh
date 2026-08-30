#!/bin/sh
# tests/edition-build/run.sh
#
# Base/Standard editionビルド分離機構の静的/モックテストの単一
# エントリポイント。実lb・実sudo・実virsh・実virt-install・実ISOビルド・
# 実libvirt操作は一切行わない。
#
# 使い方: tests/edition-build/run.sh
set -eu

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/../.." && pwd)"

BUILD_SH="${REPO_ROOT}/scripts/build.sh"
UPDATE_ISO_SH="${REPO_ROOT}/scripts/update-test-iso.sh"
CREATE_VM_SH="${REPO_ROOT}/scripts/create-test-vm.sh"

PRE_SHA_BUILD="$(sha256sum "${BUILD_SH}")"
PRE_SHA_UPDATE="$(sha256sum "${UPDATE_ISO_SH}")"
PRE_SHA_CREATE_VM="$(sha256sum "${CREATE_VM_SH}")"

overall_rc=0

echo "############################################"
echo "# test_package_lists.sh (config/package-lists.d/ 静的確認)"
echo "############################################"
sh "${TESTS_DIR}/test_package_lists.sh" && pl_rc=0 || pl_rc=$?
[ "${pl_rc}" -eq 0 ] || overall_rc=1

echo
echo "############################################"
echo "# test_build.sh (scripts/build.sh モックテスト)"
echo "############################################"
sh "${TESTS_DIR}/test_build.sh" && build_rc=0 || build_rc=$?
[ "${build_rc}" -eq 0 ] || overall_rc=1

echo
echo "############################################"
echo "# test_update_iso.sh (scripts/update-test-iso.sh モックテスト)"
echo "############################################"
sh "${TESTS_DIR}/test_update_iso.sh" && update_rc=0 || update_rc=$?
[ "${update_rc}" -eq 0 ] || overall_rc=1

echo
echo "############################################"
echo "# test_create_vm.sh (scripts/create-test-vm.sh モックテスト)"
echo "############################################"
sh "${TESTS_DIR}/test_create_vm.sh" && create_vm_rc=0 || create_vm_rc=$?
[ "${create_vm_rc}" -eq 0 ] || overall_rc=1

echo
echo "############################################"
echo "# script integrity (post-run)"
echo "############################################"
POST_SHA_BUILD="$(sha256sum "${BUILD_SH}")"
POST_SHA_UPDATE="$(sha256sum "${UPDATE_ISO_SH}")"
POST_SHA_CREATE_VM="$(sha256sum "${CREATE_VM_SH}")"
if [ "${POST_SHA_BUILD}" != "${PRE_SHA_BUILD}" ]; then
	echo 'FATAL: scripts/build.sh changed during the test run' >&2
	overall_rc=1
else
	echo 'scripts/build.sh SHA-256: unchanged'
fi
if [ "${POST_SHA_UPDATE}" != "${PRE_SHA_UPDATE}" ]; then
	echo 'FATAL: scripts/update-test-iso.sh changed during the test run' >&2
	overall_rc=1
else
	echo 'scripts/update-test-iso.sh SHA-256: unchanged'
fi
if [ "${POST_SHA_CREATE_VM}" != "${PRE_SHA_CREATE_VM}" ]; then
	echo 'FATAL: scripts/create-test-vm.sh changed during the test run' >&2
	overall_rc=1
else
	echo 'scripts/create-test-vm.sh SHA-256: unchanged'
fi

echo
echo "package_lists=${pl_rc} build=${build_rc} update_iso=${update_rc} create_vm=${create_vm_rc} overall=${overall_rc}"
exit "${overall_rc}"
