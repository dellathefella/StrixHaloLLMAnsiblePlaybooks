# =============================================================================
# ornith15-ciru-halo-agent-vllm.Containerfile
# Wraps Ciru's bundled runtime installer (from
# jcbtc/Ornith1.5-Ciru-Halo-Agent-vllm-strix-halo) into a Podman image.
#
# Ciru publishes no container image — the HF repo ships the pinned vLLM/
# AITER wheels, native kernels, DFlash2 drafter and an installer
# (runtime/INSTALL-ORNITH-RUNTIME.sh). Stock `pip install vllm` cannot
# serve these weights, so the installer runs HERE at build time and the
# engine lands in /opt/ciru/installed-runtime.
#
# The WEIGHTS are NOT baked in: the deploy playbook bind-mounts the
# downloaded bundle/ at /bundle (read-write — the server needs
# bundle/cache writable) and passes ORNITH_RUNTIME_ROOT so the launcher
# finds the baked runtime. Build context is the downloaded repo dir;
# .containerignore (written by the playbook) keeps bundle/ out of it.
#
# Build (done by ornith15-ciru-halo-agent-vllm-podman.yml, not by hand):
#   podman build -t localhost/ornith15-ciru-halo-agent-vllm:1.0.2 \
#     -f <base>/ornith15-ciru-halo-agent-vllm.Containerfile <base>
#
# Run (see the track's _podman_common_args):
#   podman run -d --device=/dev/kfd --device=/dev/dri --group-add keep-groups \
#     --ipc=host --ulimit memlock=-1:-1 -v <base>/bundle:/bundle \
#     -e ORNITH_RUNTIME_ROOT=/opt/ciru/installed-runtime -p 8741:8741 \
#     localhost/ornith15-ciru-halo-agent-vllm:1.0.2 \
#     /bundle/serve-vision.sh --host 0.0.0.0 --port 8741
# =============================================================================

FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu prerequisites from the Ciru INSTALL.md (the installer obtains the
# pinned ROCm SDK + Python packages itself; no distro vLLM/ROCm needed).
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      cmake \
      ninja-build \
      pkg-config \
      xxd \
      curl \
      ca-certificates \
      tar \
      libnuma-dev \
      libdrm-dev \
      libelf-dev \
      libssl-dev \
      zlib1g-dev \
      libvulkan-dev \
    && rm -rf /var/lib/apt/lists/*

# uv — required on PATH by the Ciru runtime installer.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH=/root/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# The bundled runtime (installer + pinned wheel/source archives) comes from
# the build context = the downloaded HF repo dir.
COPY runtime/ /opt/ciru/runtime/

# Install the pinned Ciru runtime (vLLM 0.1.0rc2.dev9+rocm100, AITER,
# PyTorch 2.13 rocm10.0.0, ROCm SDK 10.0.0, Python 3.14). The installer
# refuses to overwrite — fine here, the layer is always fresh.
RUN cd /opt/ciru && bash runtime/INSTALL-ORNITH-RUNTIME.sh /opt/ciru/installed-runtime

ENV ORNITH_RUNTIME_ROOT=/opt/ciru/installed-runtime

WORKDIR /bundle

# The serve scripts (/bundle/serve.sh, /bundle/serve-vision.sh) come from
# the bind-mounted bundle and take --host/--port at run time.
ENTRYPOINT ["/bin/bash"]
