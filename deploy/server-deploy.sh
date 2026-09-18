#!/usr/bin/env bash

# Forced command for the dedicated ochepulse-webseite GitHub Actions key.
# It accepts a gzip-compressed tar archive on stdin and publishes exactly the
# three website files. The SSH key is not allowed to execute arbitrary input.

set -Eeuo pipefail

PATH=/usr/bin:/bin
export PATH
umask 077

readonly WEB_ROOT=/srv/ochepulse/web
readonly EXPECTED_FILES=(datenschutz.html impressum.html index.html)

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

# The current site is only a few kilobytes. Keep a deliberately generous but
# bounded ceiling so a leaked key cannot fill the server disk through stdin.
timeout 30s head -c 1048577 > "$archive"
if (( $(stat -c '%s' "$archive") > 1048576 )); then
  echo "Deployment archive exceeds the 1 MiB limit." >&2
  exit 65
fi

tar -xzf "$archive" \
  --directory "$incoming" \
  --no-same-owner \
  --no-same-permissions

mapfile -t actual_files < <(
  find "$incoming" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort
)

if (( ${#actual_files[@]} != ${#EXPECTED_FILES[@]} )); then
  echo "Deployment archive does not contain the expected file set." >&2
  exit 65
fi

for index in "${!EXPECTED_FILES[@]}"; do
  if [[ "${actual_files[$index]}" != "${EXPECTED_FILES[$index]}" ]]; then
    echo "Deployment archive contains an unexpected file." >&2
    exit 65
  fi
done

if find "$incoming" -mindepth 1 -maxdepth 1 ! -type f -print -quit | grep -q .; then
  echo "Deployment archive contains a non-regular entry." >&2
  exit 65
fi

for file in "${EXPECTED_FILES[@]}"; do
  test -s "$incoming/$file"
  grep -Eiq '<!doctype[[:space:]]+html|<html([[:space:]>])' "$incoming/$file"

  if [[ -f "$WEB_ROOT/$file" ]]; then
    cp -p -- "$WEB_ROOT/$file" "$backup/$file"
  else
    touch "$backup/.missing-$file"
  fi
done

rollback_needed=true
rollback() {
  if [[ "$rollback_needed" == true ]]; then
    for file in "${EXPECTED_FILES[@]}"; do
      rm -f -- "$WEB_ROOT/.$file.new"
      if [[ -f "$backup/$file" ]]; then
        install -m 0644 -- "$backup/$file" "$WEB_ROOT/$file"
      elif [[ -f "$backup/.missing-$file" ]]; then
        rm -f -- "$WEB_ROOT/$file"
      fi
    done
  fi
}
trap 'rollback; cleanup' EXIT

for file in "${EXPECTED_FILES[@]}"; do
  install -m 0644 -- "$incoming/$file" "$WEB_ROOT/.$file.new"
done

for file in "${EXPECTED_FILES[@]}"; do
  mv -f -- "$WEB_ROOT/.$file.new" "$WEB_ROOT/$file"
done

rollback_needed=false
echo "OchePulse website deployed successfully."
