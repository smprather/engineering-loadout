#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./reproduce-llvm-build.sh [--clean] [--install] [--prefix PATH] [--jobs N]

Reproduce the successful LLVM build from this checkout.

Defaults:
  build dir: ./build
  install prefix: /usr/local
  ninja: ~/.local/bin/ninja
  jobs: nproc, capped at 8

Options:
  --clean        Remove ./build before configuring.
  --install      Install after building, using cmake --install.
  --prefix PATH  Install prefix for --install and CMAKE_INSTALL_PREFIX.
  --jobs N       Ninja parallelism.
  -h, --help     Show this help.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${BUILD_DIR:-$repo_root/build}"
ninja_bin="$HOME/.local/bin/ninja"
prefix="/usr/local"
clean=0
install=0

if command -v nproc >/dev/null 2>&1; then
  jobs="$(nproc)"
else
  jobs=8
fi
if (( jobs > 8 )); then
  jobs=8
fi

while (($#)); do
  case "$1" in
    --clean)
      clean=1
      shift
      ;;
    --install)
      install=1
      shift
      ;;
    --prefix)
      prefix="${2:?missing value for --prefix}"
      shift 2
      ;;
    --jobs|-j)
      jobs="${2:?missing value for --jobs}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd cmake

if [[ ! -x "$ninja_bin" ]]; then
  echo "error: expected ninja not found or not executable: $ninja_bin" >&2
  exit 1
fi

if [[ -r /opt/rh/gcc-toolset-14/enable ]]; then
  # shellcheck disable=SC1091
  source /opt/rh/gcc-toolset-14/enable
fi

require_cmd gcc
require_cmd g++

echo "repo: $repo_root"
echo "build: $build_dir"
echo "prefix: $prefix"
echo "jobs: $jobs"
echo "ninja: $ninja_bin ($("$ninja_bin" --version))"
echo "gcc: $(command -v gcc) ($(gcc -dumpfullversion -dumpversion))"
echo "g++: $(command -v g++) ($(g++ -dumpfullversion -dumpversion))"

if [[ ! -d "$repo_root/llvm" ]]; then
  echo "error: this script must run from an llvm-project checkout with ./llvm present" >&2
  exit 1
fi

if (( clean )); then
  rm -rf "$build_dir"
fi

cmake -S "$repo_root/llvm" -B "$build_dir" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$ninja_bin" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DLLVM_ENABLE_PROJECTS='clang;clang-tools-extra;lldb;lld;bolt' \
  -DLLVM_ENABLE_RUNTIMES='compiler-rt' \
  -DLLVM_TARGETS_TO_BUILD='X86;AArch64;RISCV'

"$ninja_bin" -C "$build_dir" -j "$jobs"

# The compiler-rt install manifest expects a few runtime archives that are not
# always pulled in by the broad target graph.
"$ninja_bin" -C "$build_dir" compiler-rt -j "$jobs"
if [[ -d "$build_dir/runtimes/runtimes-bins" ]]; then
  "$ninja_bin" -C "$build_dir/runtimes/runtimes-bins" stats -j "$jobs"
fi

if (( install )); then
  cmake --install "$build_dir" --prefix "$prefix"
  if [[ -d "$build_dir/runtimes/runtimes-bins" ]]; then
    cmake --install "$build_dir/runtimes/runtimes-bins" --prefix "$prefix"
  fi
fi
