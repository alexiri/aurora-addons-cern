#!/usr/bin/env bash
# Build, test, sign and describe the packages of this repository, and keep aurora-addons.yaml in
# step with them. Used by hand (the owner) and by .github/workflows/release.yml (CI).
#
#   scripts/release.sh build                 unsigned archives in dist/ + `aurora plugin test` per package
#   scripts/release.sh sign --key FILE       sign dist/*.aurora-plugin, verify each against the manifest's key
#   scripts/release.sh record                write releases/<id>-<version>.release from dist/ (immutable)
#   scripts/release.sh manifest [--check]    write aurora-addons.yaml; --check only diffs (CI: drift = failure)
#   scripts/release.sh all --key FILE        build + sign + record + manifest (what the owner runs locally)
#   scripts/release.sh check                 build + manifest --check: everything CI can do without the key
#   scripts/release.sh verify-signed         dist/ archives match the records (sha256 and size) after signing
#   scripts/release.sh notes <tag>           the GitHub release body (markdown) for a tag
#   scripts/release.sh assets <tag>          the dist/ archives that belong to a tag, one per line
#   scripts/release.sh verify-published      download every recorded package URL and compare its sha256
#
# The private key is only ever a PATH argument (`--key FILE`) handed to `aurora plugin sign`; this
# script never reads, prints or copies it.
#
# A version is immutable. `record` refuses to change a record that exists: fix a mistake with a new
# version in plugins/<id>/plugin.yaml. The record keeps the sha256 of the unsigned build too, so CI,
# which has no key, still detects a source change that was not re-recorded (the build is deterministic).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AURORA="${AURORA:-aurora}"
DIST="${DIST:-dist}"
HEAD_FILE=scripts/manifest-head.yaml
MANIFEST=aurora-addons.yaml
REPO_SLUG="${REPO_SLUG:-alexiri/aurora-addons-cern}"

die() { echo "release.sh: $*" >&2; exit 1; }

# pkg_field <plugin.yaml> <key>: a scalar of the top-level `package:` block.
pkg_field() {
  awk -v k="$2" '
    /^package:/ { f = 1; next }
    /^[^ #]/ { f = 0 }
    f && $1 == k ":" { sub(/^[^:]*: */, ""); gsub(/^"|"$/, ""); print; exit }
  ' "$1"
}

plugins() { for f in plugins/*/plugin.yaml; do dirname "$f"; done; }
signing_key() { awk -F'"' '/^signing_key:/ { print $2 }' "$HEAD_FILE"; }
record_get() { sed -n "s/^$2=//p" "$1"; }
archive_of() { echo "$DIST/$1-$2.aurora-plugin"; }
require_aurora() { command -v "$AURORA" >/dev/null || [ -x "$AURORA" ] || die "the aurora CLI is not found (set AURORA=/path/to/aurora)"; }
yaml_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

cmd_build() {
  require_aurora
  rm -rf "$DIST"; mkdir -p "$DIST"
  for dir in $(plugins); do
    id="$(pkg_field "$dir/plugin.yaml" id)"; ver="$(pkg_field "$dir/plugin.yaml" version)"
    [ "$(basename "$dir")" = "$id" ] || die "$dir: package id '$id' differs from the directory name"
    [ "$(pkg_field "$dir/plugin.yaml" publisher)" = "$(awk '/^publisher:/ { print $2 }' "$HEAD_FILE")" ] \
      || die "$dir: publisher differs from the manifest's publisher"
    "$AURORA" plugin test "$dir" > "$DIST/$id-test.json" || { cat "$DIST/$id-test.json" >&2; die "$id: fixtures failed"; }
    "$AURORA" plugin build "$dir" --out "$(archive_of "$id" "$ver")" >/dev/null
    sha256sum "$(archive_of "$id" "$ver")" | cut -d' ' -f1 > "$DIST/$id-$ver.unsigned.sha256"
    echo "built $(archive_of "$id" "$ver") (fixtures pass, unsigned sha256 $(cat "$DIST/$id-$ver.unsigned.sha256"))"
  done
}

cmd_sign() {
  require_aurora
  local key=""
  while [ "$#" -gt 0 ]; do case "$1" in --key) key="$2"; shift 2 ;; *) die "sign: unknown argument $1" ;; esac; done
  [ -n "$key" ] && [ -s "$key" ] || die "sign: --key FILE (the private key) is required"
  local pub; pub="$(mktemp)"; trap 'rm -f "$pub"' RETURN
  printf '%s\n' "$(signing_key)" > "$pub"
  for dir in $(plugins); do
    id="$(pkg_field "$dir/plugin.yaml" id)"; ver="$(pkg_field "$dir/plugin.yaml" version)"
    a="$(archive_of "$id" "$ver")"
    [ -f "$a" ] || die "sign: $a is missing (run build first)"
    "$AURORA" plugin sign "$a" --key "$key" >/dev/null
    "$AURORA" plugin validate "$a" --pubkey "$pub" >/dev/null || die "sign: $a does not verify against the manifest's signing_key"
    echo "signed $a (verified against the manifest's signing_key)"
  done
}

cmd_record() {
  mkdir -p releases
  for dir in $(plugins); do
    id="$(pkg_field "$dir/plugin.yaml" id)"; ver="$(pkg_field "$dir/plugin.yaml" version)"
    a="$(archive_of "$id" "$ver")"; r="releases/$id-$ver.release"
    [ -f "$a" ] || die "record: $a is missing"
    new="id=$id
version=$ver
tag=${TAG:-v$ver}
unsigned_sha256=$(cat "$DIST/$id-$ver.unsigned.sha256")
sha256=$(sha256sum "$a" | cut -d' ' -f1)
size=$(stat -c %s "$a")"
    if [ -f "$r" ]; then
      [ "$(cat "$r")" = "$new" ] || die "record: $r exists with different content; a published version is immutable, bump the version of $id"
      echo "record $r unchanged"
    else
      printf '%s\n' "$new" > "$r"; echo "recorded $r"
    fi
  done
}

# the manifest text, assembled from the head, plugin.yaml (name, description) and the records
manifest_text() {
  cat "$HEAD_FILE"
  echo
  echo "addons:"
  for dir in $(plugins); do
    id="$(pkg_field "$dir/plugin.yaml" id)"
    name="$(pkg_field "$dir/plugin.yaml" name)"; desc="$(pkg_field "$dir/plugin.yaml" description)"
    [ "${#desc}" -le 280 ] || die "$id: description is longer than 280 characters (manifest limit)"
    echo "  - id: $id"
    echo "    name: $(yaml_str "$name")"
    echo "    description: $(yaml_str "$desc")"
    echo "    versions:"
    found=""
    for r in $(ls releases/"$id"-*.release 2>/dev/null | sort -V -r); do
      found=1
      ver="$(record_get "$r" version)"; tag="$(record_get "$r" tag)"
      echo "      \"$ver\":"
      echo "        package: https://github.com/$REPO_SLUG/releases/download/$tag/$id-$ver.aurora-plugin"
      echo "        sha256: $(record_get "$r" sha256)"
      echo "        size_bytes: $(record_get "$r" size)"
      echo "        min_core: \"$(pkg_field "$dir/plugin.yaml" min_core)\""
    done
    [ -n "$found" ] || die "$id has no release record: run scripts/release.sh all --key <private key> and commit the result"
  done
}

cmd_manifest() {
  local text; text="$(manifest_text)"
  if [ "${1:-}" = "--check" ]; then
    [ "$text" = "$(cat "$MANIFEST")" ] || {
      diff <(printf '%s\n' "$text") "$MANIFEST" >&2 || true
      die "$MANIFEST drifts from plugins/, releases/ and $HEAD_FILE: run scripts/release.sh manifest and commit it"
    }
    # every current package version has a record, and its unsigned build is the recorded one
    for dir in $(plugins); do
      id="$(pkg_field "$dir/plugin.yaml" id)"; ver="$(pkg_field "$dir/plugin.yaml" version)"
      r="releases/$id-$ver.release"
      [ -f "$r" ] || die "$id $ver has no release record: bump nothing, run scripts/release.sh all --key <private key> and commit"
      [ "$(record_get "$r" unsigned_sha256)" = "$(cat "$DIST/$id-$ver.unsigned.sha256")" ] \
        || die "$id $ver: the source changed since it was recorded (unsigned sha256 differs); a version is immutable, bump the version and re-run scripts/release.sh all"
    done
    echo "manifest in step with the packages"
  else
    printf '%s\n' "$text" > "$MANIFEST"; echo "wrote $MANIFEST"
  fi
}

cmd_verify_signed() {
  for dir in $(plugins); do
    id="$(pkg_field "$dir/plugin.yaml" id)"; ver="$(pkg_field "$dir/plugin.yaml" version)"
    a="$(archive_of "$id" "$ver")"; r="releases/$id-$ver.release"
    [ "$(sha256sum "$a" | cut -d' ' -f1)" = "$(record_get "$r" sha256)" ] || die "$a: signed sha256 differs from the manifest's record"
    [ "$(stat -c %s "$a")" = "$(record_get "$r" size)" ] || die "$a: signed size differs from the manifest's record"
    echo "$a matches $r"
  done
}

cmd_assets() {
  local tag="$1"
  for r in releases/*.release; do
    [ "$(record_get "$r" tag)" = "$tag" ] && archive_of "$(record_get "$r" id)" "$(record_get "$r" version)"
  done
  return 0
}

cmd_notes() {
  local tag="$1"
  echo "Signed Aurora app packages published with \`$tag\`. Register the repository in Aurora (Admin, Addon sources): https://github.com/$REPO_SLUG"
  echo
  echo "| Addon | Version | sha256 | Size (bytes) |"
  echo "|---|---|---|---|"
  for r in releases/*.release; do
    [ "$(record_get "$r" tag)" = "$tag" ] || continue
    echo "| \`$(record_get "$r" id)\` | $(record_get "$r" version) | \`$(record_get "$r" sha256)\` | $(record_get "$r" size) |"
  done
  echo
  echo "Signing key (public): \`$(signing_key)\`"
}

cmd_verify_published() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  for r in releases/*.release; do
    id="$(record_get "$r" id)"; ver="$(record_get "$r" version)"; tag="$(record_get "$r" tag)"
    url="https://github.com/$REPO_SLUG/releases/download/$tag/$id-$ver.aurora-plugin"
    curl -fsSL --max-time 120 "$url" -o "$tmp/a" || die "cannot download $url"
    [ "$(sha256sum "$tmp/a" | cut -d' ' -f1)" = "$(record_get "$r" sha256)" ] || die "$url: sha256 differs from the manifest"
    [ "$(stat -c %s "$tmp/a")" = "$(record_get "$r" size)" ] || die "$url: size differs from the manifest"
    echo "published $url matches the manifest"
  done
}

c="${1:-}"; [ "$#" -gt 0 ] && shift
case "$c" in
  build) cmd_build ;;
  sign) cmd_sign "$@" ;;
  record) cmd_record ;;
  manifest) cmd_manifest "$@" ;;
  all) cmd_build; cmd_sign "$@"; cmd_record; cmd_manifest ;;
  check) cmd_build; cmd_manifest --check ;;
  verify-signed) cmd_verify_signed ;;
  notes) cmd_notes "${1:?usage: notes <tag>}" ;;
  assets) cmd_assets "${1:?usage: assets <tag>}" ;;
  verify-published) cmd_verify_published ;;
  *) sed -n '2,16p' "$0" >&2; exit 2 ;;
esac
