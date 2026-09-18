#!/usr/bin/env bash

# Forced command for the dedicated ochepulse-webseite GitHub Actions key.
# It accepts a gzip-compressed tar archive on stdin and mirrors its validated
# static files into the website root. The SSH key cannot execute arbitrary
# commands.

set -Eeuo pipefail

PATH=/usr/bin:/bin
export PATH
umask 077

readonly WEB_ROOT=/srv/ochepulse/web
readonly MAX_ARCHIVE_BYTES=52428800
readonly MAX_EXTRACTED_BYTES=209715200
readonly MAX_FILE_COUNT=5000

if [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  echo "Remote commands are not permitted for this deployment key." >&2
  exit 64
fi

if [[ ! -d "$WEB_ROOT" || ! -w "$WEB_ROOT" ]]; then
  echo "The website root is unavailable or not writable." >&2
  exit 73
fi

stage_dir="$(mktemp -d /srv/ochepulse/.website-deploy.XXXXXX)"
readonly stage_dir
readonly archive="$stage_dir/upload.tar.gz"
readonly incoming="$stage_dir/incoming"
readonly backup="$stage_dir/backup"

cleanup() {
  rm -rf -- "$stage_dir"
}
trap cleanup EXIT

mkdir -m 700 "$incoming" "$backup"

# Keep a bounded ceiling so a leaked key cannot fill the server disk through
# stdin. Extracted size and file count are checked separately below.
timeout 60s head -c "$((MAX_ARCHIVE_BYTES + 1))" > "$archive"
if (( $(stat -c '%s' "$archive") > MAX_ARCHIVE_BYTES )); then
  echo "Deployment archive exceeds the 50 MiB compressed limit." >&2
  exit 65
fi

tar -xzf "$archive" \
  --directory "$incoming" \
  --no-same-owner \
  --no-same-permissions

if find "$incoming" -mindepth 1 ! -type f ! -type d -print -quit | grep -q .; then
  echo "Deployment archive contains a non-regular entry." >&2
  exit 65
fi

if find "$incoming" -mindepth 1 -name .git -print -quit | grep -q .; then
  echo "Deployment archive contains a nested .git directory." >&2
  exit 65
fi

test -f "$incoming/index.html"
test -s "$incoming/index.html"
grep -Eiq '<!doctype[[:space:]]+html|<html([[:space:]>])' "$incoming/index.html"

file_count="$(find "$incoming" -type f | wc -l)"
extracted_bytes="$(du -sb "$incoming" | cut -f 1)"
if (( file_count == 0 || file_count > MAX_FILE_COUNT )); then
  echo "Deployment file count is outside the permitted range." >&2
  exit 65
fi
if (( extracted_bytes > MAX_EXTRACTED_BYTES )); then
  echo "Deployment exceeds the 200 MiB extracted limit." >&2
  exit 65
fi

rsync -a -- "$WEB_ROOT/" "$backup/"

rollback_needed=true
rollback() {
  if [[ "$rollback_needed" == true ]]; then
    rsync -a --delete --chmod=D755,F644 -- "$backup/" "$WEB_ROOT/"
  fi
}
trap 'rollback; cleanup' EXIT

rsync -a --delete --chmod=D755,F644 -- "$incoming/" "$WEB_ROOT/"

manifest_digest() {
  local root="$1"
  (
    cd "$root"
    while IFS= read -r -d '' file; do
      printf '%s\0' "$file"
      sha256sum "$file" | cut -d ' ' -f 1 | tr -d '\n'
      printf '\0'
    done < <(find . -type f -print0 | sort -z)
  ) | sha256sum | cut -d ' ' -f 1
}

deployed_manifest="$(manifest_digest "$WEB_ROOT")"
rollback_needed=false

printf 'DEPLOYED_MANIFEST_SHA256=%s\n' "$deployed_manifest"
echo "OchePulse website deployed successfully."
