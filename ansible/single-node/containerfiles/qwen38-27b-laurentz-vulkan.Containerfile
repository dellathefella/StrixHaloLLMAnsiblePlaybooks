# =============================================================================
# qwen38-27b-laurentz-vulkan.Containerfile
# Builds LaurentZuijdwijk/llama.cpp (https://github.com/LaurentZuijdwijk/llama.cpp)
# with the Vulkan backend, pinned to a commit SHA via --build-arg.
#
# This fork adds adaptive speculative decoding (--spec-type draft-dflash,
# --spec-draft-adaptive) tuned for AMD Strix Halo/gfx1151. It publishes NO
# runnable container image of its own — its only GHCR package
# (ghcr.io/laurentzuijdwijk/llama.cpp) contains just `buildcache-*` CI layer
# caches for CUDA/ROCm, not a bootable server image, and has no Vulkan tag at
# all despite Vulkan being the fork's primary target for this hardware. So we
# build it ourselves, on the target host, from source.
#
# Package names (glslc, libvulkan-dev, mesa-vulkan-drivers, spirv-headers,
# spirv-tools) verified against the real Ubuntu 24.04 "noble" archive
# (packages.ubuntu.com) — NOT the WSL dev box's Ubuntu 26.04, whose repos
# still had a spirv-tools-dev split that doesn't exist on noble. On noble the
# base spirv-tools package itself ships every SPIRV-Tools*.cmake config (no
# -dev split), which is what ggml-vulkan/CMakeLists.txt's
# find_package(SPIRV-Headers) / find_package(SPIRV-Tools) chain needs — not
# satisfied by libvulkan-dev/glslc/vulkan-tools alone. The kisak-mesa PPA in
# the runtime stage mirrors julianmb/haloq38flash's own Dockerfile for the
# same gfx1151 target — stock Ubuntu 24.04 mesa-vulkan-drivers is likely too
# old for reliable RDNA3.5/gfx1151 support.
#
# kisak-mesa PPA: the slug is ppa:kisak/kisak-mesa, NOT ppa:kisak/kisak — the
# latter isn't a real PPA under that Launchpad account (owner "kisak" hosts
# kisak-mesa, kisak-mesa-build-deps, steamvr, and turtle; no PPA is literally
# named "kisak"). Using the bare name failed with
# "ERROR: ppa 'kisak/kisak' not found" during the runtime-stage apt step.
#
# UNVERIFIED: the fork's README only documents loading the DFlash2 draft
# model via the auto-download `-hfd <hf-repo>` shorthand, never a local-file
# flag. This uses --model-draft (upstream llama.cpp's flag for --spec-type
# draft-mtp, and the same flag the qwen38-27b-ud-q4-k-xl track already uses
# successfully) on the assumption --spec-type draft-dflash reads the draft
# model the same way. If the coordinator fails to pick up the drafter, run
# `podman exec <container> llama-server --help` to find the actual flag name.
# =============================================================================

FROM docker.io/library/ubuntu:24.04 AS build
ARG LLAMA_CPP_COMMIT=5e085d123eead2e89b5c19f824fccb05727da6a2
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ccache \
      libvulkan-dev glslc vulkan-tools spirv-headers spirv-tools \
      libcurl4-openssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/LaurentZuijdwijk/llama.cpp /src/engine \
    && cd /src/engine \
    && git checkout "${LLAMA_CPP_COMMIT}"

RUN cmake -B /src/engine/build -S /src/engine -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_CURL=ON \
    && cmake --build /src/engine/build --parallel "$(nproc)" \
      --target llama-server llama-cli llama-bench

# -----------------------------------------------------------------------------
FROM docker.io/library/ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# kisak-mesa PPA for a Mesa build current enough for gfx1151 Vulkan (RADV) —
# same driver-currency reasoning as julianmb/haloq38flash's own Dockerfile.
RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common gpg-agent \
    && add-apt-repository -y ppa:kisak/kisak-mesa \
    && apt-get update && apt-get install -y --no-install-recommends \
      mesa-vulkan-drivers vulkan-tools libvulkan1 libcurl4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/engine/build/bin/llama-server /app/llama-server
COPY --from=build /src/engine/build/bin/llama-cli /app/llama-cli
COPY --from=build /src/engine/build/bin/llama-bench /app/llama-bench
COPY --from=build /src/engine/build/bin/libggml*.so* /app/
COPY --from=build /src/engine/build/bin/libllama*.so* /app/
RUN ldconfig /app 2>/dev/null; true

ENV LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH}
VOLUME /models
WORKDIR /app
EXPOSE 8080
