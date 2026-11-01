#!/usr/bin/env bash
# Downloads the two Debian packages the VM is built from, each pinned by sha256, into DIR/dl.
# A file already there with the right hash is kept. Debian moves a package between pools as
# releases go by, so each one has a list of places to try, ending at snapshot.debian.org,
# which keeps every file it has seen.
# usage: bash vm/fetch.sh DIR
set -eu
dir=$1/dl
mkdir -p "$dir"

# fetch FILE SHA256 URL...: the first URL whose download has the pinned hash wins
fetch() {
  local file=$1 sum=$2
  shift 2
  if [ -f "$dir/$file" ] && echo "$sum  $dir/$file" | sha256sum -c --status; then
    echo "have $file"
    return 0
  fi
  local url
  for url in "$@"; do
    if timeout 900 curl -fsSL -o "$dir/$file.part" "$url/$file" &&
      echo "$sum  $dir/$file.part" | sha256sum -c --status; then
      mv "$dir/$file.part" "$dir/$file"
      echo "got $file from $url"
      return 0
    fi
    echo "no good copy of $file at $url"
  done
  rm -f "$dir/$file.part"
  echo "fetch: could not get $file with sha256 $sum" >&2
  return 1
}

fetch busybox-static_1.37.0-6+b9_arm64.deb \
  c833be48abfa16bc19c4966ec93e289ff1ce5d2f1476cad3a57bd105378cd15c \
  https://deb.debian.org/debian/pool/main/b/busybox \
  https://snapshot.debian.org/archive/debian/20260712T202631Z/pool/main/b/busybox

fetch linux-image-6.12.113+deb13-arm64_6.12.113-1_arm64.deb \
  fb1d4ff8bffc992b9b7e073f9a07d1ce378c041cfba78bb8e039c15a504b3129 \
  https://deb.debian.org/debian/pool/main/l/linux-signed-arm64 \
  https://security.debian.org/debian-security/pool/updates/main/l/linux-signed-arm64 \
  https://snapshot.debian.org/archive/debian-security/20261016T133910Z/pool/updates/main/l/linux-signed-arm64
