# =============================================================================
# qwen38-flash-next-haloq38.Containerfile
# Port of julianmb/haloq38flash's own Dockerfile
# (https://github.com/julianmb/haloq38flash) — it has no published registry
# image (only `docker compose up --build`, building `.` locally), so this
# reproduces its build steps directly under `podman build` instead of compose.
# One deviation from that Dockerfile: it doesn't install spirv-headers/
# spirv-tools, but the qwen38-27b-laurentz-vulkan Containerfile's build (same
# ggml-vulkan CMake machinery, different llama.cpp fork) failed with
# `Could not find a package configuration file provided by "SPIRV-Headers"`
# without them — added here too since Nathanw1014's fork almost certainly has
# the same ggml-vulkan CMakeLists.txt requiring it. Package name is
# spirv-tools, not spirv-tools-dev — the latter doesn't exist on Ubuntu 24.04
# "noble" (only on newer releases); noble's base spirv-tools package ships
# every SPIRV-Tools*.cmake config itself, no -dev split needed.
#
# kisak-mesa PPA: the slug is ppa:kisak/kisak-mesa, NOT ppa:kisak/kisak — the
# latter isn't a real PPA under that Launchpad account (owner "kisak" hosts
# kisak-mesa, kisak-mesa-build-deps, steamvr, and turtle; no PPA is literally
# named "kisak"). Same bug hit both from-source Containerfiles since both
# copied the same runtime-stage apt step.
#
# Builds Nathanw1014's own llama.cpp fork (branch strix-halo-vulkan — the
# same source lineage as the ghcr.io/nathanw1014/strix-halo-llamacpp:vulkan
# image several other tracks in this repo pull prebuilt), with the Vulkan
# backend, for julianmb's bugfixed Qwen3.8-Flash-Next-IQ4_XS-GGUF quant.
#
# CAUTION: the previously-removed qwen38-flash-next-ud-iq4-xs track (same
# qwen4exp architecture, same Nathanw1014 image, unsloth's quant instead of
# julianmb's) hit "quantized KV cache asserts and dies on qwen4exp" and had
# to stay on f16 KV. julianmb's README claims a "fixed converter bug" and
# recommends -ctk q8_0 -ctv q8_0 anyway — if that assert is in llama.cpp's
# qwen4exp handling itself rather than the old quant's conversion, it could
# still crash here despite the model-side fix. cache_type_k/cache_type_v are
# exposed as vars specifically so you can drop to f16 without editing flags
# if it does.
# =============================================================================

FROM docker.io/library/ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ccache \
      libvulkan-dev glslc vulkan-tools spirv-headers spirv-tools \
      libcurl4-openssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 -b strix-halo-vulkan https://github.com/Nathanw1014/llama.cpp /src/engine

RUN cmake -B /src/engine/build -S /src/engine \
      -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_CURL=ON \
    && cmake --build /src/engine/build --parallel "$(nproc)" \
      --target llama-server llama-cli llama-bench

# -----------------------------------------------------------------------------
FROM docker.io/library/ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common gpg-agent \
    && add-apt-repository -y ppa:kisak/kisak-mesa \
    && apt-get update && apt-get install -y --no-install-recommends \
      mesa-vulkan-drivers vulkan-tools libvulkan1 libcurl4 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/engine/build/bin/llama-server /app/llama-server
COPY --from=build /src/engine/build/bin/llama-cli /app/llama-cli
COPY --from=build /src/engine/build/bin/llama-bench /app/llama-bench
# Use *.so* (not libggml* + libllama*) — modern llama.cpp also builds libmtmd.so
# (multimodal/MTMD library) which is required at runtime but doesn't match
# the libggml*/libllama* glob. CMAKE_LIBRARY_OUTPUT_DIRECTORY is build/bin/
# so all .so files land there regardless of name prefix.
COPY --from=build /src/engine/build/bin/*.so* /app/
RUN ldconfig /app 2>/dev/null; true

ENV LD_LIBRARY_PATH=/app:${LD_LIBRARY_PATH}
VOLUME /models
WORKDIR /app
EXPOSE 8080
