FROM almalinux:8.10

RUN dnf install -y \
        bzip2 \
        diffutils \
        file \
        findutils \
        glibc-langpack-en \
        ksh \
        strace \
        tar \
        tcsh \
        which \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN useradd --create-home --uid 1000 --shell /bin/bash loadout

COPY almalinux8.10-smoke-entrypoint /usr/local/bin/loadout-smoke
RUN chmod 0755 /usr/local/bin/loadout-smoke

USER loadout
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/loadout-smoke"]
