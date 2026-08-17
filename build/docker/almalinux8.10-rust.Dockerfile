FROM almalinux:8.10

# bzip2/tar/which/findutils: loadout bootstrap + archive extraction.
# gcc + glibc-devel: rustc shells out to `cc`/`ld` for the final link, exactly
# like any rust install -- a C toolchain is the one host prerequisite an offline
# rust store cannot remove. (Network is only used HERE, at image-build time;
# the actual compile test runs with --network none.)
RUN dnf install -y \
        bzip2 \
        file \
        findutils \
        gcc \
        git \
        glibc-devel \
        glibc-langpack-en \
        tar \
        which \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Bake an actual loadout rust tool's source into the image at BUILD time (the
# only place network is allowed). At RUN time (--network none) the entrypoint
# rebuilds it with `cargo build --offline` against the bundled superset store,
# proving the store can reconstruct loadout's own rust binaries offline.
#
# The version is passed in from payload/packages.json rather than written here.
# It was hardcoded to 15.1.0 while the registry and build/rust-tool-locks.txt
# moved to 15.2.0 on 2026-08-04, so the store carried 15.2.0's closure while the
# test tried to build 15.1.0 -- whose globset needs crate versions the store no
# longer had. The test failed for 13 days without anyone noticing, because it is
# not in tests/run-all's default tiers. Same family as failure-catalogue entry
# 10 (stale version literals in tests).
ARG RIPGREP_VERSION
ENV RIPGREP_VERSION=${RIPGREP_VERSION}
RUN test -n "$RIPGREP_VERSION" || { echo "RIPGREP_VERSION build-arg is required" >&2; exit 1; }
RUN git clone --depth 1 --branch "$RIPGREP_VERSION" https://github.com/BurntSushi/ripgrep \
        /opt/ripgrep-src \
    && rm -rf /opt/ripgrep-src/.git

RUN useradd --create-home --uid 1000 --shell /bin/bash loadout
RUN chown -R loadout:loadout /opt/ripgrep-src

COPY almalinux8.10-rust-entrypoint /usr/local/bin/loadout-rust-test
RUN chmod 0755 /usr/local/bin/loadout-rust-test

USER loadout
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/loadout-rust-test"]
