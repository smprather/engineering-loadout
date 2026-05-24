# Building LLVM on EL8

This documents the exact build that succeeded on this EL8/WSL system, including the compiler-rt runtime needed for `libclang_rt.profile.a`.

## Result

The completed install placed LLVM 23.0.0git tools under `/usr/local`:

```bash
/usr/local/bin/clang --version
/usr/local/bin/ld.lld --version
/usr/local/bin/lldb --version
/usr/local/bin/llvm-bolt --version
/usr/local/bin/clang -print-file-name=libclang_rt.profile.a
```

The expected profile runtime path is:

```text
/usr/local/lib/clang/23/lib/x86_64-unknown-linux-gnu/libclang_rt.profile.a
```

## Platform

This is for Enterprise Linux 8, specifically the Red Hat-compatible EL8 userspace used here. The base EL8 compiler is GCC 8.5, which is too old for this build. Use GCC Toolset 14.

The successful machine had about 24 GB WSL memory available and the WSL disk moved to a large D: backed virtual disk. At the end of the build, `/` had roughly 890 GB free. Do not try this with a small root filesystem.

## Non-Base Dependencies

These are not all present on a base EL8 install.

Install from EL8/AppStream/CRB/EPEL or the matching vendor repos as appropriate:

```bash
sudo dnf install \
  gcc-toolset-14-gcc \
  gcc-toolset-14-gcc-c++ \
  git \
  libedit-devel \
  libxml2-devel \
  ncurses-devel \
  pkgconf-pkg-config \
  xz-devel \
  zlib-devel
```

The local machine also had:

```text
gcc-toolset-14-gcc-14.2.1-11.el8_10.x86_64
gcc-toolset-14-gcc-c++-14.2.1-11.el8_10.x86_64
libedit-devel-3.1-23.20170329cvs.el8.x86_64
libxml2-devel-2.9.7-21.el8_10.4.x86_64
ncurses-devel-6.1-10.20180224.el8.x86_64
xz-devel-5.2.4-4.el8_6.x86_64
zlib-devel-1.2.11-25.el8.x86_64
pkgconf-pkg-config-1.4.2-1.el8.x86_64
perl-interpreter-5.26.3-423.el8_10.x86_64
```

The active tools used for the successful build were not the base EL8 tool versions:

```text
/usr/local/bin/cmake       cmake 4.3.2
/home/mylesp/.local/bin/ninja  1.11.1.git.kitware.jobserver-1
/home/mylesp/.local/bin/python3  local Python 3.14.4
```

EL8 RPMs for `cmake` and `ninja-build` were installed too, but the PATH resolved to the newer local tools. If reproducing on a clean system, make sure `cmake --version`, `ninja --version`, and `python3 --version` are adequate before configuring.

Optional features that were missing and did not block this build:

```text
OCaml bindings
SWIG-generated LLDB bindings
LLDB Python scripting
LLDB Lua scripting
Tree-sitter syntax highlighting
Doxygen docs
```

## Environment

Activate GCC Toolset 14 before configuring:

```bash
source /opt/rh/gcc-toolset-14/enable
gcc --version
g++ --version
```

Expected compiler:

```text
gcc (GCC) 14.2.1 20250110 (Red Hat 14.2.1-11)
g++ (GCC) 14.2.1 20250110 (Red Hat 14.2.1-11)
```

## Source

Start from a fresh `llvm-project` checkout:

```bash
git clone https://github.com/llvm/llvm-project.git
cd llvm-project
```

Do not delete `.git` from the checkout. CMake and the LLVM version machinery use Git metadata to stamp versions and revisions. If `.git` is gone, use a fresh clone.

The revision that was built here was:

```text
e6c316e374e7380415e7abb15e8816b9027307b1
```

## Configure

From the repo root:

```bash
source /opt/rh/gcc-toolset-14/enable

cmake -S llvm -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DLLVM_ENABLE_PROJECTS='clang;clang-tools-extra;lldb;lld;bolt' \
  -DLLVM_ENABLE_RUNTIMES='compiler-rt' \
  -DLLVM_TARGETS_TO_BUILD='X86;AArch64;RISCV'
```

Notes:

- `compiler-rt` is enabled through `LLVM_ENABLE_RUNTIMES`, not `LLVM_ENABLE_PROJECTS`.
- CMake may still print `compiler-rt project is disabled`; that is expected when it is configured as a runtime.
- The configured targets are X86, AArch64, and RISCV.
- The configured projects are Clang, clang-tools-extra, LLDB, LLD, and BOLT.

## Build

Use a capped job count. `-j8` worked with 24 GB WSL memory:

```bash
ninja -C build -j8
```

Build compiler-rt explicitly:

```bash
ninja -C build compiler-rt -j8
```

Build the stats runtime explicitly before install:

```bash
ninja -C build/runtimes/runtimes-bins stats -j8
```

This matters because the compiler-rt install manifest expects `libclang_rt.stats.a` and `libclang_rt.stats_client.a`, but the broad `compiler-rt` target did not build them in this environment.

## Install

Use CMake install, not Ninja install:

```bash
sudo cmake --install build --prefix /usr/local
sudo cmake --install build/runtimes/runtimes-bins --prefix /usr/local
```

The first command installs LLVM, Clang, LLD, LLDB, BOLT, headers, CMake package files, and normal project artifacts.

The second command installs compiler-rt runtime headers and archives, including:

```text
libclang_rt.profile.a
libclang_rt.builtins.a
libclang_rt.asan.a
libclang_rt.ubsan_standalone.a
libclang_rt.tsan.a
libclang_rt.fuzzer.a
```

## Verify

Run:

```bash
/usr/local/bin/clang --version
/usr/local/bin/ld.lld --version
/usr/local/bin/lldb --version
/usr/local/bin/llvm-bolt --version
/usr/local/bin/clang -print-file-name=libclang_rt.profile.a
test -f /usr/local/lib/clang/23/lib/x86_64-unknown-linux-gnu/libclang_rt.profile.a
```

Expected versions:

```text
clang version 23.0.0git
LLD 23.0.0
lldb version 23.0.0git
LLVM version 23.0.0git
```

## Reproduction Script

This repo also contains:

```bash
./reproduce-llvm-build.sh
```

For a clean rebuild without install:

```bash
./reproduce-llvm-build.sh --clean --jobs 8
```

For a clean rebuild and install:

```bash
sudo ./reproduce-llvm-build.sh --clean --install --jobs 8
```

The script activates GCC Toolset 14 if `/opt/rh/gcc-toolset-14/enable` exists, configures the same projects/runtimes/targets, builds `compiler-rt`, builds the missing `stats` target, and uses CMake install.

## Things That Did Not Work

### Deleting `.git`

Problem: `.git` was deleted to save disk space.

Why it failed: LLVM's build uses Git metadata for revision/version information. Removing `.git` makes the checkout less reproducible and can break build/version logic.

Resolution: start over from a fresh GitHub clone and keep `.git`.

### Building with the Base EL8 Compiler

Problem: base EL8 provides GCC 8.5.

Why it failed: this LLVM checkout needs a newer C++ compiler.

Resolution: install and activate GCC Toolset 14:

```bash
source /opt/rh/gcc-toolset-14/enable
```

### Running Out of WSL Disk/Memory

Problem: the build repeatedly failed or could not proceed while the WSL virtual disk/root filesystem and memory were constrained.

Why it failed: LLVM plus Clang, LLDB, LLD, BOLT, and compiler-rt is a large build. Linking and generated artifacts need substantial disk and memory.

Resolution: move the WSL VHDX to a large D: backed location and raise WSL memory to about 24 GB. Use `-j8`; reduce to `-j4` if linking or compiler-rt memory pressure appears.

### `ninja -C build -t targets install`

Problem: attempted to inspect/install with an invalid Ninja tool invocation.

Why it failed: `-t targets` takes Ninja tool options, not a build target named `install`.

Resolution: use `ninja -C build -t targets` only to list targets. Use CMake install for installation.

### `sudo ninja -C build install`

Problem: Ninja install failed with:

```text
multiple outputs aren't (yet?) supported by depslog
```

Why it failed: the generated Ninja graph hit a Ninja depslog limitation on this build.

Resolution: install with CMake's install driver:

```bash
sudo cmake --install build --prefix /usr/local
```

### Installing Compiler-RT Before Building `stats`

Problem: `sudo cmake --install build/runtimes/runtimes-bins --prefix /usr/local` initially failed because it could not find:

```text
libclang_rt.stats.a
```

Why it failed: the compiler-rt install manifest expected the stats archives, but the broad `compiler-rt` target did not build them.

Resolution: build the stats target first, then rerun install:

```bash
ninja -C build/runtimes/runtimes-bins stats -j8
sudo cmake --install build/runtimes/runtimes-bins --prefix /usr/local
```

### Expecting `libclang_rt.profile.a` Without Compiler-RT

Problem: the first successful LLVM install did not include `libclang_rt.profile.a`.

Why it failed: the original configure used:

```text
LLVM_ENABLE_PROJECTS=clang;clang-tools-extra;lldb;lld;bolt
LLVM_ENABLE_RUNTIMES=
```

`libclang_rt.profile.a` is part of compiler-rt, not the core Clang project.

Resolution: reconfigure with:

```text
LLVM_ENABLE_RUNTIMES=compiler-rt
```

then build and install the runtime tree.
