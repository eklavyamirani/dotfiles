# Container the apply scenarios run in: a bare Linux account with only the
# things a fresh machine already has (git, python3, a shell), plus stow and zsh,
# which bootstrap.sh would otherwise install through Homebrew. Homebrew itself
# is stubbed (tests/stubs/homebrew) -- see tests/README.md.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      python3 \
      stow \
      zsh \
 && rm -rf /var/lib/apt/lists/*

# Never run the scenarios as root: the deployment under test is explicitly a
# non-admin account, and root would mask permission mistakes.
RUN useradd --create-home --shell /bin/bash --uid 1001 dev
USER dev
WORKDIR /home/dev

ENTRYPOINT ["/bin/bash"]
