#!/usr/bin/env bash
set -Eeu

# Builds the newest GoogleTest release from its source, rather than the one
# Debian's archive froze at its release. GitHub redirects releases/latest to
# the newest release's tag, which is resolved here at build time so a
# rebuild picks up the next release by itself.

# Appends one test framework to the test_frameworks list the base image
# wrote in /versions.json, keeping any entry an earlier image added. Stops
# the build if the list is not found, rather than record nothing.
add_test_framework()
{
  local -r name="${1}"
  local -r version="${2}"
  local -r entry="{\"name\": \"${name}\", \"version\": \"${version}\"}"
  if grep -q '"test_frameworks": \[\]' /versions.json; then
    sed -i "s|\"test_frameworks\": \[\]|\"test_frameworks\": [${entry}]|" /versions.json
  else
    sed -i "/\"test_frameworks\": \[/s|}\]|}, ${entry}]|" /versions.json
  fi
  if ! grep -q -F "${entry}" /versions.json; then
    echo "Could not add ${name} to /versions.json" >&2
    cat /versions.json >&2
    exit 1
  fi
}

apt-get update
apt-get install --yes cmake

readonly LATEST_URL=$(curl --silent --fail --output /dev/null --write-out '%{redirect_url}' \
  https://github.com/google/googletest/releases/latest)
readonly GTEST_TAG="${LATEST_URL##*/}"

# An empty tag means the redirect could not be read or has changed shape,
# not that GoogleTest stopped releasing, so stop rather than build nothing.
if [ -z "${GTEST_TAG}" ]; then
  echo 'Found no GoogleTest release tag at github.com/google/googletest' >&2
  exit 1
fi

cd /usr/src
curl --silent --fail --location \
  "https://github.com/google/googletest/archive/refs/tags/${GTEST_TAG}.tar.gz" \
  | tar --extract --gzip
cd "googletest-${GTEST_TAG#v}"
# Shared libraries, not static ones. A kata's makefile links -lgtest before
# -lgtest_main, and a static libgtest_main.a placed after libgtest.a finds its
# references to libgtest unresolved whenever no test file pulled them in.
# Shared libraries resolve in any order, so every kata's makefile links.
cmake -S . -B build -DBUILD_SHARED_LIBS=ON
cmake --build build
cmake --install build --prefix /usr
ldconfig
cd /usr/src
rm -rf "googletest-${GTEST_TAG#v}"

apt-get remove --yes cmake

add_test_framework GoogleTest "${GTEST_TAG#v}"
cat /versions.json
