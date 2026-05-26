#!/bin/zsh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh --version <version> [options]

Packages a built macOS .app bundle into releases/ as zip archives.
Can also commit and push artifacts, create and push a release tag, and upload assets to GitHub Releases.

Options:
  --app-path <path>   Path to the built .app bundle. Default: webiqu.app
  --version <value>   Release version used in archive and tag names (required).
  --branch <name>     Branch to push. Default: current checked-out branch.
  --remote <name>     Git remote to push. Default: origin
  --publish           Commit+push release artifacts, create+push tag, and upload assets with gh.
  --tag-only          Create an annotated git tag named v<version> and stop.
  --help              Show this help text.
EOF
}

app_path="webiqu.app"
version=""
branch=""
remote_name="origin"
publish=false
tag_only=false

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
    --branch)
      branch="$2"
      shift 2
      ;;
    --remote)
      remote_name="$2"
      shift 2
      ;;
    --publish)
      publish=true
      shift
      ;;
    --tag-only)
      tag_only=true
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

if [[ -z "$version" ]]; then
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
if [[ -z "$branch" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
fi

if [[ "$branch" == "HEAD" ]]; then
  echo "Detached HEAD detected. Pass --branch <name>." >&2
  exit 1
fi

release_dir="$repo_root/releases"
archive_name="webiqu-${version}-macos.zip"
archive_path="$release_dir/$archive_name"
latest_archive_name="webiqu-macos.zip"
latest_archive_path="$release_dir/$latest_archive_name"
normalized_app_path="$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")"
tag_name="v$version"

mkdir -p "$release_dir"
rm -f "$archive_path" "$latest_archive_path"

ditto -c -k --sequesterRsrc --keepParent "$normalized_app_path" "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$normalized_app_path" "$latest_archive_path"

echo "Created archive: $archive_path"
echo "Created archive: $latest_archive_path"

if [[ "$tag_only" == true ]]; then
  if git rev-parse "$tag_name" >/dev/null 2>&1; then
    echo "Tag already exists: $tag_name" >&2
    exit 1
  fi

  git tag -a "$tag_name" -m "release($tag_name): publish macOS build"
  echo "Created tag: $tag_name"
  exit 0
fi

if [[ "$publish" == true ]]; then
  if ! git remote get-url "$remote_name" >/dev/null 2>&1; then
    echo "Git remote not found: $remote_name" >&2
    exit 1
  fi

  if git rev-parse "$tag_name" >/dev/null 2>&1; then
    echo "Tag already exists: $tag_name" >&2
    exit 1
  fi

  git add "$archive_path" "$latest_archive_path"

  if git diff --cached --quiet; then
    echo "No release artifact changes to commit."
  else
    git commit -m "release($tag_name): add macOS archive"
    echo "Committed release artifacts to branch: $branch"
  fi

  git tag -a "$tag_name" -m "release($tag_name): publish macOS build"
  echo "Created tag: $tag_name"

  git push "$remote_name" "$branch"
  echo "Pushed branch: $remote_name/$branch"

  git push "$remote_name" "$tag_name"
  echo "Pushed tag: $remote_name/$tag_name"

  if command -v gh >/dev/null 2>&1; then
    if gh release view "$tag_name" >/dev/null 2>&1; then
      gh release upload "$tag_name" "$archive_path" "$latest_archive_path" --clobber
      echo "Uploaded assets to existing GitHub Release: $tag_name"
    else
      gh release create "$tag_name" "$archive_path" "$latest_archive_path" \
        --title "Webiqu $tag_name" \
        --notes "Automated macOS release for $tag_name"
      echo "Created GitHub Release and uploaded assets: $tag_name"
    fi
  else
    echo "gh CLI not found. Skipped GitHub Release upload." >&2
  fi
fi