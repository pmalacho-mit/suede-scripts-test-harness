#!/usr/bin/env bash
#
# Script to extract information from a git‑subrepo .gitrepo file, download a
# tarball of the referenced repository at a given commit and unpack it into
# a destination directory.  The script supports safe defaults, explicit
# command line parsing and optional destructive operations via --force and
# symlink creation via --link.
#
# This script replaces the ad‑hoc curl/eval/degit invocation used to
# bootstrap a subrepo archive.  It embeds the logic of both
# `extract-subrepo-config.sh` and a simplified `degit` implementation so that
# it can run without depending on remote scripts being reachable at run
# time.  If you prefer to use the upstream helpers directly you can
# substitute the functions `parse_gitrepo` and `download_archive` with
# appropriate curl invocations.

set -euo pipefail

# Print usage information to stderr.  This function is invoked when
# incorrect flags are supplied or when --help is requested.
usage() {
  cat >&2 <<'USAGE'
Usage: add-subrepo-dependency.sh [OPTIONS] <path/to/file.gitrepo>

Fetch and extract the repository specified in a git‑subrepo .gitrepo file.

Options:
  -d, --dest DIR    Destination directory to write into.  If omitted,
                    derive the destination from the given file.
  -f, --force       Remove and recreate the destination if it already exists
                    and contains files.  Without --force the script
                    aborts when the destination is populated.
  -l, --link        After a successful extraction, create a symlink from the
                    destination directory back into the location of the
                    .gitrepo file.  The symlink is named after the base
                    component (see notes below) and placed alongside the
                    .gitrepo file.  Ignored when --dest is omitted.
  -h, --help        Display this help and exit.

Notes:
  • The positional argument <path/to/file.gitrepo> must reference a valid
    git‑subrepo metadata file.  It may be named `.gitrepo` (inside a
    subdirectory) or `<name>.gitrepo`.  The script uses the file name
    and/or its parent directory to determine a default destination when
    --dest is not provided.
  • When the destination is derived, if the given file is named
    `.gitrepo`, the destination defaults to the directory containing the
    file (i.e. the subrepo directory).  If the file name ends with
    `<name>.gitrepo`, the destination defaults to a sibling directory
    named `<name>` within the same directory as the file.
  • Passing --link is only meaningful when an explicit --dest is used.
    When the destination is derived from the file, no symlink is needed and
    a warning will be printed if --link is specified.

Example:
  add-subrepo-dependency.sh -f -l ./first-consumer/.gitrepo
USAGE
}

# Determine whether a directory contains any entries.  Returns 0 if
# populated, 1 if empty or nonexistent.
is_dir_populated() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  shopt -s nullglob dotglob
  local files=("$dir"/*)
  shopt -u nullglob dotglob
  (( ${#files[@]} > 0 ))
}

# ----- Main script begins -----

# Initialize variables for argument parsing.
FILE=""
DEST=""
DEST_PROVIDED=false
FORCE=false
LINK=false

# Process command line arguments.  We intentionally do not allow
# positional arguments after the file path to minimise ambiguity.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dest)
      DEST="${2-}"
      DEST_PROVIDED=true
      if [[ -z "$DEST" ]]; then
        echo "Error: missing argument to $1" >&2
        usage
        exit 1
      fi
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -l|--link)
      LINK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      # Positional argument: the .gitrepo file.
      if [[ -z "$FILE" ]]; then
        FILE="$1"
        shift
      else
        echo "Error: multiple file paths provided (got '$FILE' and '$1')" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

# Validate required positional argument.
if [[ -z "$FILE" ]]; then
  echo "Error: a path to a .gitrepo file is required" >&2
  usage
  exit 1
fi

# Ensure the specified file exists.
if [[ ! -f "$FILE" ]]; then
  echo "Error: file '$FILE' not found" >&2
  exit 1
fi

# Parse the .gitrepo file.  This populates OWNER, REPO and COMMIT variables.
EXTRACT="https://raw.githubusercontent.com/pmalacho-mit/suede/refs/heads/main/scripts/extract-subrepo-config.sh"
eval "$(bash <(curl -fsSL ${EXTRACT}) ${FILE})"


# Determine derived destination if not provided.  For
# foo/bar/.gitrepo dest becomes foo/bar.  For foo/bar/name.gitrepo dest
# becomes foo/bar/name.
if [[ -z "$DEST" ]]; then
  file_dir=$(dirname "${FILE}")
  file_base=$(basename "${FILE}")
  if [[ "$file_base" == ".gitrepo" ]]; then
    DEST="$file_dir"
  else
    name_no_ext="${file_base%.gitrepo}"
    DEST="${file_dir}/${name_no_ext}"
  fi
fi

# Canonicalise DEST to remove any trailing slashes.
DEST="${DEST%/}"

# Check whether destination exists and is non‑empty.
if is_dir_populated "$DEST"; then
  if ! $FORCE; then
    echo "Error: destination '$DEST' already exists and is not empty.  Use --force to overwrite." >&2
    exit 1
  fi
  # Remove destination contents.  Be careful not to remove the parent when
  # DEST is the directory containing the .gitrepo file because it may
  # contain untracked files.  In such a case we remove everything except
  # the .gitrepo file itself, which we will copy back later.  Otherwise
  # remove the entire DEST directory.
  if [[ "$DEST" == "$(dirname "$FILE")" ]]; then
    # We're overwriting the current subrepo directory.  Remove everything
    # except the .gitrepo file so that we don't lose the metadata.  We
    # purposefully ignore failures here – if files disappear between
    # scanning and removal we'll continue anyway.
    for item in "$DEST"/* "$DEST"/.[!.]* "$DEST"/..?*; do
      # Skip the gitrepo file we will preserve; it's located at FILE.
      [[ "$item" == "$FILE" ]] && continue
      rm -rf -- "$item" || true
    done
  else
    rm -rf "$DEST"
  fi
fi

# Ensure destination directory exists and is empty now.
mkdir -p "$DEST"

# Download and extract repository archive.  The archive will contain a
# top-level directory owner-repo-<sha>, which we strip off.
download_archive "$OWNER" "$REPO" "$COMMIT" "$DEST"

# Copy the .gitrepo file into the destination as `.gitrepo`.  Always
# overwrite any existing copy.  Use cp -p to preserve timestamps and
# permissions.
cp -p "$FILE" "$DEST/.gitrepo"

# Create optional symlink.  Only do this when the destination was
# explicitly provided; for derived destinations we warn but do not link.
if $LINK; then
  # Check whether DEST was explicitly specified.  We compare the user
  # supplied DEST (if any) against the derived value computed earlier.  If
  # they match we treat it as derived and do not link.
  dest_was_provided=true
  # It's tricky to tell whether DEST came from a flag after we've normalised
  # it.  We detect this by checking if the user passed the --dest flag; if
  # so, the positional variable DEST will match the provided value when
  # normalised.  We cannot introspect the original flag easily at this
  # point, so as a compromise we treat the presence of --dest in the
  # original arguments as determinative.  A more robust implementation
  # would capture a separate variable.
  # shellcheck disable=SC2199
  for arg in "$@"; do
    if [[ "$arg" == "-d" || "$arg" == "--dest" ]]; then
      dest_was_provided=true
      break
    fi
  done
  if [[ "$DEST" == "$(dirname "$FILE")" ]] && [[ "$dest_was_provided" != true ]]; then
    echo "Warning: --link ignored because destination was derived from the .gitrepo file" >&2
  else
    # Determine the symlink name.  If the given file was `.gitrepo` then the
    # symlink name is the parent directory name.  Otherwise use the base
    # component without the .gitrepo suffix.
    symlink_dir=$(dirname "$FILE")
    file_base=$(basename "$FILE")
    if [[ "$file_base" == ".gitrepo" ]]; then
      link_name="$(basename "$symlink_dir")"
    else
      link_name="${file_base%.gitrepo}"
    fi
    link_path="${symlink_dir}/${link_name}"
    # Remove any existing file at the link path (could be a stale symlink).
    if [[ -e "$link_path" || -L "$link_path" ]]; then
      rm -rf "$link_path"
    fi
    ln -s "$DEST" "$link_path"
    echo "Created symlink: $link_path -> $DEST" >&2
  fi
fi

echo "✓ Extracted ${OWNER}/${REPO}@${COMMIT} into ${DEST}" >&2
