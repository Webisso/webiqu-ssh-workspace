#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh --app-path <path-to-app> --version <version> [--tag]

Packages a built macOS .app bundle into dist/ as a zip archive and checksum.

Options:
  --app-path <path>   Path to the built .app bundle.
  --version <value>   Release version used in the archive name and optional tag.
  --tag               Create an annotated git tag named v<version>.
  --help              Show this help text.
EOF
}

app_path=""
version=""
create_tag=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      app_path="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    --tag)
      create_tag=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$app_path" || -z "$version" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "This script must run inside the git repository." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
dist_dir="$repo_root/dist"
archive_name="webiqu-${version}-macos.zip"
archive_path="$dist_dir/$archive_name"
checksum_path="$archive_path.sha256"
latest_archive_path="$dist_dir/webiqu-macos.zip"
latest_checksum_path="$latest_archive_path.sha256"
normalized_app_path="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"

mkdir -p "$dist_dir"
rm -f "$archive_path" "$checksum_path" "$latest_archive_path" "$latest_checksum_path"

ditto -c -k --sequesterRsrc --keepParent "$normalized_app_path" "$archive_path"
shasum -a 256 "$archive_path" > "$checksum_path"
cp "$archive_path" "$latest_archive_path"
cp "$checksum_path" "$latest_checksum_path"

echo "Created archive: $archive_path"
echo "Created checksum: $checksum_path"
echo "Created latest archive: $latest_archive_path"
echo "Created latest checksum: $latest_checksum_path"

if [[ "$create_tag" == true ]]; then
  tag_name="v$version"

  if git rev-parse "$tag_name" >/dev/null 2>&1; then
    echo "Tag already exists: $tag_name" >&2
    exit 1
  fi

  git tag -a "$tag_name" -m "release($tag_name): publish macOS build"
  echo "Created tag: $tag_name"
fi