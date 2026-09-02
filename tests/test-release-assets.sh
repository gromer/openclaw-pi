#!/bin/sh
set -eu

test_root=$(mktemp -d "${TMPDIR:-/tmp}/openclaw-release-assets.XXXXXX")
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

tag=v9.9.9-test
sh install.sh --help >/dev/null
if sh install.sh --unexpected >/dev/null 2>&1; then
  echo "installer accepted an unexpected argument" >&2
  exit 1
fi
scripts/build-release-assets.sh "$tag" "$test_root/dist"
archive="$test_root/dist/openclaw-pi-${tag}.tar.gz"

for asset in \
  bootstrap.sh \
  bootstrap.sh.sha256 \
  install.sh \
  install.sh.sha256 \
  "openclaw-pi-${tag}.tar.gz" \
  "openclaw-pi-${tag}.tar.gz.sha256" \
  release-manifest.json \
  release-manifest.json.sha256; do
  [ -s "$test_root/dist/$asset" ] || { echo "missing release asset: $asset" >&2; exit 1; }
done

tar -tzf "$archive" | awk -v prefix="openclaw-pi-${tag}/" '
  index($0, prefix) != 1 { bad = 1 }
  /\.github\// { bad = 1 }
  END { exit bad }
'
if tar -tzf "$archive" | grep -Eq '(^|/)(age-identity(\.txt)?|sops-age-keys\.txt|secrets\.plain(\.ya?ml)?)$|\.agekey$|\.dec\.ya?ml$'; then
  echo "forbidden secret filename found in release archive" >&2
  exit 1
fi
grep -F '"release": "v9.9.9-test"' "$test_root/dist/release-manifest.json" >/dev/null
grep -F '"archive": "openclaw-pi-v9.9.9-test.tar.gz"' "$test_root/dist/release-manifest.json" >/dev/null
grep -F "\"commit\": \"$(git rev-parse HEAD)\"" "$test_root/dist/release-manifest.json" >/dev/null
tar -xOf "$archive" "openclaw-pi-${tag}/bootstrap.sh" > "$test_root/bundled-bootstrap.sh"
cmp "$test_root/bundled-bootstrap.sh" "$test_root/dist/bootstrap.sh"
tar -xOf "$archive" "openclaw-pi-${tag}/install.sh" > "$test_root/bundled-install.sh"
cmp "$test_root/bundled-install.sh" "$test_root/dist/install.sh"
if grep -F 'git clone' "$test_root/bundled-bootstrap.sh" >/dev/null; then
  echo "release bundle bootstrap unexpectedly requires Git" >&2
  exit 1
fi
mkdir "$test_root/extracted"
tar -xzf "$archive" -C "$test_root/extracted"
python3 "$test_root/extracted/openclaw-pi-${tag}/tests/test_static.py"
echo "release assets: ok"
