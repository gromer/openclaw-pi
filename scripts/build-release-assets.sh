#!/bin/sh
set -eu
umask 022

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 RELEASE_TAG OUTPUT_DIRECTORY" >&2
  exit 2
fi

release_tag=$1
output_dir=$2

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi
}
case "$release_tag" in
  *[!A-Za-z0-9._-]*|'')
    echo "ERROR: release tag may contain only letters, numbers, dot, underscore, and dash" >&2
    exit 1
    ;;
esac

if git ls-files -s | awk '$1 == "120000" { found = 1 } END { exit !found }'; then
  echo "ERROR: tracked symbolic links are not permitted in release bundles" >&2
  exit 1
fi

mkdir -p "$output_dir"
archive_name="openclaw-pi-${release_tag}.tar.gz"
archive_path="$output_dir/$archive_name"
temporary_tar="$output_dir/openclaw-pi-${release_tag}.tar"
commit_sha=$(git rev-parse HEAD)

git archive --worktree-attributes --format=tar --prefix="openclaw-pi-${release_tag}/" \
  --output="$temporary_tar" HEAD
gzip --no-name --best "$temporary_tar"
(
  cd "$output_dir"
  sha256_file "$archive_name" > "$archive_name.sha256"
)
archive_sha256=$(awk 'NR == 1 { print $1 }' "$archive_path.sha256")

cat > "$output_dir/release-manifest.json" <<EOF
{
  "schema": 1,
  "release": "$release_tag",
  "commit": "$commit_sha",
  "archive": "$archive_name",
  "sha256": "$archive_sha256"
}
EOF
tar -xOf "$archive_path" "openclaw-pi-${release_tag}/bootstrap.sh" > "$output_dir/bootstrap.sh"
chmod 0755 "$output_dir/bootstrap.sh"
(
  cd "$output_dir"
  sha256_file release-manifest.json > release-manifest.json.sha256
  sha256_file bootstrap.sh > bootstrap.sh.sha256
)
tar -xOf "$archive_path" "openclaw-pi-${release_tag}/install.sh" > "$output_dir/install.sh"
chmod 0755 "$output_dir/install.sh"
(
  cd "$output_dir"
  sha256_file install.sh > install.sh.sha256
)

echo "Built release assets in $output_dir"
