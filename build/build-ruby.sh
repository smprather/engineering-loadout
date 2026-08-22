#!/bin/sh
# Build the loadout's Ruby from AlmaLinux 8's ruby:3.3 module stream ("shanghai"
# -- repack a vendor RPM set rather than build from source, like meld,
# mate-terminal and firefox).
#
# WHY 3.3 AND NOT SOURCE: AlmaLinux ships and security-patches ruby:3.3 for EL8,
# so tracking their stream means CVE fixes arrive with a re-run of this script
# instead of a source-build babysitting job. EL8's DEFAULT ruby stream is 2.5,
# which has been EOL since March 2021 -- never ship that as the user-facing Ruby.
#
# FOUR NON-OBVIOUS FIXUPS, each of which silently breaks the install if skipped:
#
#   1. 83 ABSOLUTE SYMLINKS. The stdlib entries for the default gems are links
#      into /usr, e.g. share/ruby/psych.rb -> /usr/share/gems/gems/psych-5.1.2/
#      lib/psych.rb. They dangle the moment the tree leaves /usr, so `require
#      "psych"` fails in a $HOME install. We MATERIALIZE them (replace each link
#      with a real copy resolved against the extracted tree) rather than rewrite
#      them relative, because add_tree_to_tar's os.walk(followlinks=False) never
#      re-emits symlinks-to-directories -- a re-tarred archive would silently
#      drop the 5 directory links (the firefox lesson, AGENTS.md).
#
#   2. SPLIT GEM EXTENSIONS. Fedora/RHEL put compiled gem .so files in
#      /usr/lib64/gems/ruby/<g>-<v>/ while rubygems (once relocated) looks in
#      <prefix>/share/gems/extensions/x86_64-linux/3.3.0/<g>-<v>/. Left alone,
#      every extension gem reports "Ignoring <gem> because its extensions are
#      not built" on stderr and fails to load. We move them to the canonical
#      location. Do not "fix" this by adding the lib64 path to RUBYLIB -- the
#      gem.build_complete marker is what rubygems actually checks.
#
#   3. NOT RELOCATABLE. Ruby here is NOT built --enable-load-relative: rbconfig's
#      TOPDIR trick sets `prefix`, but rubylibdir/rubyarchdir stay absolute /usr
#      paths, so $LOAD_PATH points into /usr regardless of where the tree lives.
#      The bin/ruby wrapper therefore exports RUBYLIB (+ GEM_HOME/GEM_PATH)
#      derived from its own installed path. bin/{gem,irb,rdbg} ship
#      `#!/usr/bin/ruby` shebangs -- absolute, resolving to the SYSTEM ruby (2.5
#      or absent) -- so they become wrappers too, with the real scripts under
#      libexec/ruby/.
#
# Usage:
#   build/build-ruby.sh --tag 3.3.10-7
#   build/build-ruby.sh --tag 3.3.10-7 --context module_el8.10.0+4210+b037b1ec

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/build/lib.sh"

MIRROR="https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages"
RUNTIME_DIR="$REPO/payload/$LOADOUT_PLATFORM/runtime"
LIB_DIR="$REPO/payload/$LOADOUT_PLATFORM/lib64"
DOWNLOADS_LOG="$REPO/assurance/downloads.log"
RUBY_ABI="3.3.0"          # rubygems' extension dir uses the ABI series, not the patch level
GEM_ARCH="x86_64-linux"

tag=""
context="module_el8.10.0+4210+b037b1ec"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }
            tag="$1" ;;
        --context)
            shift; [ "$#" -gt 0 ] || { echo "missing value for --context" >&2; exit 2; }
            context="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

loadout_require_tag "$tag" "$0" \
    "https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/ (dnf module info ruby:3.3)" \
    "3.3.10-7"
loadout_require_cmds curl rpm2cpio cpio python3.14 tar bzip2

version="${tag%%-*}"                 # 3.3.10-7 -> 3.3.10
series="$(echo "$version" | cut -d. -f1,2)"   # -> 3.3

workdir="$(mktemp -d "${TMPDIR:-/tmp}/loadout-ruby.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT
tree="$workdir/tree"
mkdir -p "$tree"

# The runtime set. rubygem-{json,psych,bigdecimal,io-console} are NOT optional:
# in Ruby 3.3 those moved out of core into default gems, so without them
# `require "json"` fails outright.
gems_rpms="rubygem-irb-1.13.1-${tag##*-} rubygem-json-2.7.2-${tag##*-} rubygem-bigdecimal-3.1.5-${tag##*-} rubygem-io-console-0.7.1-${tag##*-} rubygem-psych-5.1.2-${tag##*-} rubygem-rdoc-6.6.3.1-${tag##*-}"

fetch() {
    _f_nvr=$1
    _f_arch=$2
    _f_url="$MIRROR/${_f_nvr}.${context}.${_f_arch}.rpm"
    _f_out="$workdir/${_f_nvr}.rpm"
    _f_code=$(curl -sSL -w '%{http_code}' -o "$_f_out" "$_f_url")
    if [ "$_f_code" != 200 ]; then
        echo "ERROR: HTTP $_f_code fetching $_f_url" >&2
        echo "  (check --tag/--context against: dnf module info ruby:3.3)" >&2
        exit 1
    fi
    # TOFU provenance, same as ./build/update and build/update-prebuilt.
    printf '%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_f_url" "$(sha256sum "$_f_out" | cut -d' ' -f1)" \
        >> "$DOWNLOADS_LOG"
    echo "  fetched ${_f_nvr}"
}

echo "Fetching ruby $version RPMs from AlmaLinux 8 (ruby:$series stream) ..."
fetch "ruby-${tag}" x86_64
fetch "ruby-libs-${tag}" x86_64
fetch "rubygems-3.5.22-${tag##*-}" noarch
fetch "ruby-bundled-gems-${tag}" x86_64
for g in $gems_rpms; do
    case "$g" in
        rubygem-irb-*|rubygem-rdoc-*) fetch "$g" noarch ;;
        *) fetch "$g" x86_64 ;;
    esac
done

echo "Extracting ..."
( cd "$tree" && for r in "$workdir"/*.rpm; do rpm2cpio "$r" | cpio -idm 2> /dev/null; done )
[ -x "$tree/usr/bin/ruby" ] || { echo "ERROR: no usr/bin/ruby after extract" >&2; exit 1; }

echo "Fixup 1/4: materializing absolute /usr symlinks ..."
python3.14 - "$tree/usr" << 'PYEOF'
import os
import shutil
import sys

root = sys.argv[1]
files = dirs = 0
unresolved = []
for dirpath, dirnames, filenames in os.walk(root):
    for name in list(dirnames) + list(filenames):
        p = os.path.join(dirpath, name)
        if not os.path.islink(p):
            continue
        tgt = os.readlink(p)
        if not tgt.startswith("/usr/"):
            continue
        real = os.path.join(root, tgt[len("/usr/"):].rstrip("/"))
        if not os.path.exists(real):
            unresolved.append(f"{p} -> {tgt}")
            continue
        os.unlink(p)
        if os.path.isdir(real):
            shutil.copytree(real, p, symlinks=False)
            dirs += 1
        else:
            shutil.copy2(real, p)
            files += 1
if unresolved:
    print("ERROR: absolute symlinks that do not resolve inside the tree:", file=sys.stderr)
    for u in unresolved:
        print("  " + u, file=sys.stderr)
    raise SystemExit(1)
left = sum(
    1
    for dp, dn, fn in os.walk(root)
    for n in dn + fn
    if os.path.islink(os.path.join(dp, n)) and os.readlink(os.path.join(dp, n)).startswith("/")
)
if left:
    raise SystemExit(f"ERROR: {left} absolute symlink(s) remain")
print(f"  materialized {files} file + {dirs} directory symlinks; 0 absolute links remain")
PYEOF

echo "Fixup 2/4: moving gem extensions to the canonical rubygems layout ..."
ext_root="$tree/usr/share/gems/extensions/$GEM_ARCH/$RUBY_ABI"
mkdir -p "$ext_root"
moved=0
if [ -d "$tree/usr/lib64/gems/ruby" ]; then
    for d in "$tree"/usr/lib64/gems/ruby/*/; do
        [ -d "$d" ] || continue
        cp -a "$d" "$ext_root/$(basename "$d")"
        moved=$((moved + 1))
    done
fi
rm -rf "${tree:?}/usr/lib64/gems" "${tree:?}/usr/lib/gems"
echo "  moved $moved extension dir(s) to share/gems/extensions/$GEM_ARCH/$RUBY_ABI"

echo "Fixup 3/4: wrappers (ruby is not --enable-load-relative) ..."
mkdir -p "$tree/usr/libexec/ruby"
for s in gem irb rdbg; do
    [ -f "$tree/usr/bin/$s" ] || continue
    mv "$tree/usr/bin/$s" "$tree/usr/libexec/ruby/$s"
done
mv "$tree/usr/bin/ruby" "$tree/usr/bin/ruby.bin"

# Prefix is derived from the launcher's own installed path so --dest-dir installs
# and shared-tree deploys both work; explicit user settings always win.
cat > "$tree/usr/bin/ruby" << 'WRAPEOF'
#!/bin/sh
# loadout ruby launcher. EL8's ruby is not built --enable-load-relative, so its
# compiled-in $LOAD_PATH points at /usr regardless of where this tree lives;
# export RUBYLIB/GEM_* derived from this script's location instead.
prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
_rl="$prefix/lib64/ruby:$prefix/share/ruby:$prefix/share/rubygems"
if [ -n "${RUBYLIB:-}" ]; then
    RUBYLIB="$_rl:$RUBYLIB"
else
    RUBYLIB="$_rl"
fi
export RUBYLIB
[ -n "${GEM_HOME:-}" ] || { GEM_HOME="$prefix/share/gems"; export GEM_HOME; }
[ -n "${GEM_PATH:-}" ] || { GEM_PATH="$prefix/share/gems"; export GEM_PATH; }
exec "$prefix/bin/ruby.bin" "$@"
WRAPEOF
chmod 755 "$tree/usr/bin/ruby"

for s in gem irb rdbg; do
    [ -f "$tree/usr/libexec/ruby/$s" ] || continue
    cat > "$tree/usr/bin/$s" << WRAPEOF
#!/bin/sh
# The stock script carries a #!/usr/bin/ruby shebang, which resolves to the
# SYSTEM ruby (EL8 default stream is 2.5, or absent entirely). Run the real
# script under the loadout ruby instead.
prefix=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd -P)
exec "\$prefix/bin/ruby" "\$prefix/libexec/ruby/$s" "\$@"
WRAPEOF
    chmod 755 "$tree/usr/bin/$s"
done
echo "  wrapped ruby + gem/irb/rdbg"

# libruby lives in lib64 as its own payload artifact so klayout (and anything
# else embedding Ruby) links against exactly this copy.
"$LOADOUT_PATCHELF" --set-rpath '$ORIGIN/../lib64' "$tree/usr/bin/ruby.bin"
strip "$tree/usr/bin/ruby.bin" 2> /dev/null || true

echo "Fixup 4/4: generating the default-gem specs EL8 omits ..."
# EL8 ships share/gems/specifications/default/ EMPTY, so gems like psych and irb
# declare runtime deps (stringio, reline, ...) that rubygems cannot resolve --
# `irb` then dies in activate_bin_path even though every one of those libraries
# is present and `require`s fine from the stdlib. Generate the missing specs.
#
# They go in specifications/, NOT specifications/default/: Gem.default_specifications_dir
# is a compiled-in /usr path that relocation cannot move, so anything written to
# the relocated default/ dir is simply never scanned. specifications/ is resolved
# through GEM_PATH and therefore follows the install.
(
    cd "$tree/usr"
    LD_LIBRARY_PATH="$PWD/lib64" \
    RUBYLIB="$PWD/lib64/ruby:$PWD/share/ruby:$PWD/share/rubygems" \
    GEM_HOME="$PWD/share/gems" GEM_PATH="$PWD/share/gems" \
    ./bin/ruby.bin -e '
      require "fileutils"
      dir = File.join(Gem.dir, "specifications")
      FileUtils.mkdir_p(dir)
      # gem name => the library that provides it (and carries its VERSION)
      {
        "reline" => "reline", "stringio" => "stringio", "date" => "date",
        "forwardable" => "forwardable", "singleton" => "singleton",
        "time" => "time", "net-protocol" => "net/protocol",
      }.each do |gem_name, lib|
        require lib
        const = lib.split("/").map { |s| s.split("_").map(&:capitalize).join }.join("::")
        mod = (Object.const_get(const) rescue nil)
        ver = (mod && mod.const_defined?(:VERSION)) ? mod.const_get(:VERSION).to_s : "3.1.1"
        File.write(File.join(dir, "#{gem_name}-#{ver}.gemspec"), <<~SPEC)
          Gem::Specification.new do |s|
            s.name = #{gem_name.inspect}
            s.version = #{ver.inspect}
            s.summary = "Ruby default gem (spec generated by build-ruby.sh; EL8 ships specifications/default empty)"
            s.authors = ["Ruby core"]
            s.require_paths = ["lib"]
          end
        SPEC
      end
      puts "  generated #{Dir[File.join(dir, "*.gemspec")].size} total gemspec(s)"
    '
) || { echo "ERROR: could not generate default-gem specs" >&2; exit 1; }

# Hard gate: no gem may declare a dependency we cannot satisfy. This is what
# actually breaks `irb`, and it fails silently at runtime rather than at build.
(
    cd "$tree/usr"
    LD_LIBRARY_PATH="$PWD/lib64" \
    RUBYLIB="$PWD/lib64/ruby:$PWD/share/ruby:$PWD/share/rubygems" \
    GEM_HOME="$PWD/share/gems" GEM_PATH="$PWD/share/gems" \
    ./bin/ruby.bin -e '
      require "rubygems"
      have = Gem::Specification.map(&:name)
      missing = Hash.new { |h, k| h[k] = [] }
      Gem::Specification.each do |s|
        s.runtime_dependencies.each { |d| missing[d.name] << s.name unless have.include?(d.name) }
      end
      unless missing.empty?
        missing.sort.each { |k, v| warn "  UNSATISFIED: #{k} (needed by #{v.uniq.join(", ")})" }
        raise "#{missing.size} unsatisfied gem dependency/ies"
      end
      puts "  all gem dependencies satisfied"
    '
) || { echo "ERROR: shipped gems have unsatisfied dependencies" >&2; exit 1; }

echo "Verifying the staged tree before packaging ..."
(
    cd "$tree/usr"
    LD_LIBRARY_PATH="$PWD/lib64" \
    RUBYLIB="$PWD/lib64/ruby:$PWD/share/ruby:$PWD/share/rubygems" \
    GEM_HOME="$PWD/share/gems" GEM_PATH="$PWD/share/gems" \
    ./bin/ruby.bin -e '
      %w[json psych yaml bigdecimal stringio irb digest openssl zlib erb set uri net/http].each { |m| require m }
      raise "version mismatch: #{RUBY_VERSION}" unless RUBY_VERSION.start_with?(ARGV[0])
      puts "  stdlib + default gems OK on ruby #{RUBY_VERSION}"
    ' "$series"
) || { echo "ERROR: staged ruby failed its own smoke" >&2; exit 1; }

# stderr must be clean: a permanent "Ignoring <gem> because its extensions are
# not built" warning is exactly the known-false signal this repo refuses to ship.
noise=$(
    cd "$tree/usr"
    LD_LIBRARY_PATH="$PWD/lib64" \
    RUBYLIB="$PWD/lib64/ruby:$PWD/share/ruby:$PWD/share/rubygems" \
    GEM_HOME="$PWD/share/gems" GEM_PATH="$PWD/share/gems" \
    ./bin/ruby.bin -e 'require "json"; require "yaml"' 2>&1 1> /dev/null || true
)
if [ -n "$noise" ]; then
    echo "ERROR: ruby wrote to stderr on a clean require:" >&2
    echo "$noise" | sed 's/^/    /' >&2
    exit 1
fi
echo "  stderr clean on require"

echo "Packaging ..."
mkdir -p "$RUNTIME_DIR" "$LIB_DIR"

# libruby -> lib64 payload artifact
libruby_real=$(cd "$tree/usr/lib64" && ls libruby.so."$series".* 2> /dev/null | head -1)
[ -n "$libruby_real" ] || { echo "ERROR: libruby.so.$series.* not found" >&2; exit 1; }
cp "$tree/usr/lib64/$libruby_real" "$workdir/libruby.so.$series"
"$LOADOUT_PATCHELF" --set-rpath '$ORIGIN' "$workdir/libruby.so.$series"
strip "$workdir/libruby.so.$series" 2> /dev/null || true
bzip2 -f "$workdir/libruby.so.$series"
cp "$workdir/libruby.so.$series.bz2" "$LIB_DIR/libruby.so.$series.bz2"
chmod 644 "$LIB_DIR/libruby.so.$series.bz2"
echo "  lib64/libruby.so.$series.bz2"

# bin wrappers + the real interpreter
for b in ruby ruby.bin gem irb rdbg; do
    [ -f "$tree/usr/bin/$b" ] || continue
    cp "$tree/usr/bin/$b" "$workdir/$b"
    bzip2 -f "$workdir/$b"
    cp "$workdir/$b.bz2" "$LOADOUT_BIN_DIR/$b.bz2"
    chmod 644 "$LOADOUT_BIN_DIR/$b.bz2"
done
echo "  bin/{ruby,ruby.bin,gem,irb,rdbg}.bz2"

# Everything else (stdlib, gems, rubygems, libexec scripts) rides in the runtime
# archive. lib64/libruby* is excluded -- it ships as a lib64 artifact above.
rm -rf "${tree:?}/usr/lib64"/libruby.so*
rm -rf "${tree:?}/usr/bin"
rm -rf "${tree:?}/usr/share/doc" "${tree:?}/usr/share/man" "${tree:?}/usr/share/systemtap"
# RPM debuginfo cross-links: lib/.build-id/xx/yyyy -> ../../../../usr/lib64/...
# Those escape the archive root, so safe_extract_tar rejects the whole tarball
# (correctly). They are debug metadata with no runtime purpose -- drop them.
rm -rf "${tree:?}/usr/lib/.build-id"
tar cjf "$RUNTIME_DIR/ruby.tar.bz2" -C "$tree/usr" .
echo "  runtime/ruby.tar.bz2 ($(du -h "$RUNTIME_DIR/ruby.tar.bz2" | cut -f1))"

loadout_stamp_version ruby "$version"

echo ""
echo "Next:"
echo "  ./build/strip-all-elf-binaries"
echo "  python3.14 build/gen-content-manifest"
echo "  tests/prebuilt-binaries --keep"
