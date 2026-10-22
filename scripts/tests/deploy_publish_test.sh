#!/bin/bash

# deploy_publish_test.sh
#
# ./deploy publishes a release by writing each artifact into the files/
# directory that the file_to_s3 service behind VVTERM_UPLOAD_BASE serves, because
# that service runs on the same machine.
#
# It is worth a test because every failure here is invisible at release time and
# only surfaces on a device: the install page and the OTA manifest are built
# from the URLs Uploader.upload returns, so a URL that does not match where the
# file actually landed publishes a 404 that the release output still reports as
# a success. The pinned names are equally load-bearing -- a name that escaped
# the directory would write somewhere else entirely, and a half-copied .ipa
# visible at a pinned URL is what a device would download mid-release.
#
# Everything runs against a scratch publish directory, so it needs no Xcode, no
# network, and never touches the real service's files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

test_directory="$(mktemp -d /tmp/vvterm-deploy-publish.XXXXXX)"
trap 'rm -rf "${test_directory}"' EXIT

publish_dir="${test_directory}/files"
mkdir -p "${publish_dir}"

source_file="${test_directory}/VVTerm-9.9.9.ipa"
printf 'first release payload' > "${source_file}"

# VVTERM_PUBLISH_DIR is set on every call below. Without it the default resolves
# to the real file_to_s3 checkout beside the repo, and these tests would publish
# into the live service.
publish() {
    VVTERM_UPLOAD_BASE="https://files.example.com" VVTERM_PUBLISH_DIR="$1" ruby -r "${PROJECT_ROOT}/scripts/deploy/uploader" \
        -e 'puts Uploader.upload(ARGV[0], name: ARGV[1])' -- "$2" "$3"
}

fail() {
    echo "$1" >&2
    exit 1
}

# A published artifact lands under exactly the name given, and the returned URL
# is the one the manifest and install page will point at.
url="$(publish "${publish_dir}" "${source_file}" "VVTerm-9.9.9.ipa")"
[ "${url}" = "https://files.example.com/files/VVTerm-9.9.9.ipa" ] \
    || fail "Expected the public URL for the pinned name, got '${url}'"
[ -f "${publish_dir}/VVTerm-9.9.9.ipa" ] \
    || fail "Expected the artifact at ${publish_dir}/VVTerm-9.9.9.ipa"
[ "$(cat "${publish_dir}/VVTerm-9.9.9.ipa")" = "first release payload" ] \
    || fail "Published artifact does not match its source"

# Pinning is what keeps a Home Screen bookmark installing the newest release:
# publishing the same name again replaces the previous one in place.
printf 'second release payload' > "${source_file}"
publish "${publish_dir}" "${source_file}" "VVTerm-9.9.9.ipa" >/dev/null
[ "$(cat "${publish_dir}/VVTerm-9.9.9.ipa")" = "second release payload" ] \
    || fail "Expected a pinned publish to overwrite the previous artifact"

# The copy is staged beside the target and renamed, so nothing is left behind
# and no device ever downloads a partially written .ipa from a pinned URL.
leftovers="$(find "${publish_dir}" -name '*.publishing-*' -print -quit)"
[ -z "${leftovers}" ] || fail "Publishing left a staging file behind: ${leftovers}"

# A name carrying a path would write outside the directory the service serves.
if publish "${publish_dir}" "${source_file}" "../escaped.ipa" >/dev/null 2>&1; then
    fail "Expected a name that escapes the publish directory to be refused"
fi
[ ! -e "${test_directory}/escaped.ipa" ] \
    || fail "A refused name still wrote outside the publish directory"

# A source that is not there must fail loudly rather than publish nothing and
# report a URL that would 404.
if publish "${publish_dir}" "${test_directory}/absent.ipa" "VVTerm-9.9.9.ipa" >/dev/null 2>&1; then
    fail "Expected a missing source file to abort the publish"
fi

# deploy preflights the directory so a missing or moved service fails before a
# release builds, not after.
if VVTERM_PUBLISH_DIR="${test_directory}/not-a-directory" \
    ruby -r "${PROJECT_ROOT}/scripts/deploy/uploader" \
        -e 'Uploader.check_publish_dir!' >/dev/null 2>&1; then
    fail "Expected preflight to fail when the publish directory is missing"
fi

echo "Deploy publish tests passed"
