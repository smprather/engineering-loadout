# Real-NFS image for build/delete-nfs-check (a manual dev check, not in run-all).
#
# One image, two roles, two containers (the test starts both):
#   server -- kernel nfsd (NFSv4.2 only) exporting a tmpfs on 127.0.0.1
#   client -- shares the server's network namespace, mounts it, and runs
#             `delete` from the bash, zsh and tcsh envs against real
#             silly-renamed .nfs files
# Both need --privileged (nfsd's filesystem, mount). The kernel is the host's:
# its nfs/nfsd modules load on demand.
#
# Built by the check itself (`docker build`, network allowed at build time);
# the containers run with --network=none.
FROM almalinux:8.10

RUN dnf install -y \
        findutils \
        nfs-utils \
        procps-ng \
        psmisc \
        tcsh \
        util-linux \
        zsh \
    && dnf clean all \
    && rm -rf /var/cache/dnf

RUN useradd --create-home --uid 1000 --shell /bin/bash loadout
