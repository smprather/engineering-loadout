#!/bin/sh
set -eu

version=${JQ_VERSION:-}
jobs=${JOBS:-}
run_checks=1
clean=0
onig_url=${ONIGURUMA_URL:-https://github.com/kkos/oniguruma.git}

usage() {
  cat <<'EOF'
Usage: ./build-jq.sh [options]

Options:
  --clean       Run make clean before building when a Makefile exists.
  --no-check    Build only; skip make check.
  --jobs N      Parallel make jobs. Defaults to nproc/getconf, then 8.
  --version V   jq version to embed. Defaults to first NEWS.md heading.
  -h, --help    Show this help.

Environment overrides:
  JQ_VERSION       Same as --version.
  JOBS             Same as --jobs.
  ONIGURUMA_URL    Git URL used when vendor/oniguruma is empty.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --clean)
      clean=1
      ;;
    --no-check)
      run_checks=0
      ;;
    --jobs)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --jobs" >&2; exit 2; }
      jobs=$1
      ;;
    --version)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --version" >&2; exit 2; }
      version=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$(dirname "$0")"

if [ -z "$version" ]; then
  version=$(sed -n 's/^# \([0-9][^ ]*\)$/\1/p' NEWS.md | sed -n '1p')
fi
[ -n "$version" ] || { echo "could not determine jq version" >&2; exit 1; }

if [ -z "$jobs" ]; then
  if command -v nproc >/dev/null 2>&1; then
    jobs=$(nproc)
  else
    jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s\n' 8)
  fi
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need autoreconf
need git
need make
need sed

if [ ! -d vendor/oniguruma ]; then
  mkdir -p vendor/oniguruma
fi

if [ -z "$(find vendor/oniguruma -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  rmdir vendor/oniguruma
  git clone "$onig_url" vendor/oniguruma
fi

if [ -f vendor/oniguruma/.gitmodules ] || [ -d vendor/oniguruma/.git ]; then
  git -C vendor/oniguruma submodule update --init --recursive
fi

autoreconf -i
./configure --with-oniguruma=builtin

if [ "$clean" -eq 1 ] && [ -f Makefile ]; then
  make clean
fi

make "VERSION=$version" -j"$jobs"

if [ "$run_checks" -eq 1 ]; then
  make "VERSION=$version" check
fi

./jq --version
