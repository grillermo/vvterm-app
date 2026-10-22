#!/bin/bash

# deploy_rollback_test.sh
#
# ./deploy writes the MARKETING_VERSION / CURRENT_PROJECT_VERSION bump into
# project.pbxproj partway through a release. A run that dies after that write
# but before the commit must leave the working tree exactly as it found it.
#
# It is worth a test because the failure is silent and delayed: the leftover
# bump says nothing in the failing run's output, and only surfaces one run
# later as "working tree is dirty", pointing nowhere near the run that caused
# it -- and every release after that stays blocked until someone reverts by
# hand.
#
# The whole thing runs against a throwaway clone with a stub xcodebuild, so it
# needs no Xcode, no signing, no network, and never touches the real checkout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

test_directory="$(mktemp -d /tmp/vvterm-deploy-rollback.XXXXXX)"
trap 'rm -rf "${test_directory}"' EXIT

clone="${test_directory}/clone"
git clone --quiet --no-tags "${PROJECT_ROOT}" "${clone}"

# Exercise the working-tree deploy, not whatever HEAD happens to hold, then
# commit it so the clone starts clean -- deploy refuses to run on a dirty tree.
cp "${PROJECT_ROOT}/deploy" "${clone}/deploy"
cp "${PROJECT_ROOT}/scripts/deploy/"*.rb "${clone}/scripts/deploy/"
chmod +x "${clone}/deploy"

# Releases are cut from main, and Vendor/libssh2 is gitignored but preflighted.
git -C "${clone}" checkout --quiet -B main
mkdir -p "${clone}/Vendor/libssh2"
git -C "${clone}" remote remove origin           # nothing here may reach a remote
git -C "${clone}" -c user.email=test@example.com -c user.name=test \
    commit --quiet --all --allow-empty --message "deploy under test"

# Releases are published into the files/ directory of the file_to_s3 service
# checked out beside the repo, and deploy preflights it. Without one here the
# run would die before the bump was ever written, quietly turning the rollback
# assertions below into a test of nothing.
mkdir -p "${test_directory}/file_to_s3/files"

# xcodebuild fails, standing in for any mid-release failure after the bump:
# a signing error, a dropped upload, an interrupted archive.
mkdir -p "${test_directory}/bin"
printf '#!/bin/sh\nexit 65\n' > "${test_directory}/bin/xcodebuild"
chmod +x "${test_directory}/bin/xcodebuild"

version_in() {
    grep -m1 'MARKETING_VERSION' "${clone}/VVTerm.xcodeproj/project.pbxproj" | tr -d '\t ;'
}

assert_pristine() {
    local label="$1" dirty
    dirty="$(git -C "${clone}" status --porcelain)"
    if [ -n "${dirty}" ]; then
        echo "Expected a clean tree after ${label}, got:" >&2
        echo "${dirty}" >&2
        exit 1
    fi
    if [ "$(version_in)" != "${baseline_version}" ]; then
        echo "Expected ${baseline_version} after ${label}, got $(version_in)" >&2
        exit 1
    fi
}

baseline_version="$(version_in)"

# A declined prompt happens before anything is written at all.
if (cd "${clone}" && echo n | ./deploy) >/dev/null 2>&1; then
    echo "Expected a declined prompt to abort the release" >&2
    exit 1
fi
assert_pristine "declining the prompt"

# --yes writes the bump, then the stub xcodebuild fails the archive.
if (cd "${clone}" && PATH="${test_directory}/bin:${PATH}" ./deploy --yes) >/dev/null 2>&1; then
    echo "Expected a failing xcodebuild to abort the release" >&2
    exit 1
fi
assert_pristine "a failed build"

echo "Deploy rollback tests passed"
