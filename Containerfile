ARG BASE_IMAGE=docker.io/vllm/vllm-openai-rocm:v0.29.0@sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1

FROM ${BASE_IMAGE} AS aiter-patched

USER root

COPY patches/apply_aiter_lds_backport.py /tmp/apply_aiter_lds_backport.py

RUN AITER_FILE="$(python3 -c \
      'import importlib.util; from pathlib import Path; \
       p=Path(importlib.util.find_spec("aiter").origin).resolve().parent / "ops/triton/attention/unified_attention.py"; \
       print(p)')" \
    && python3 /tmp/apply_aiter_lds_backport.py "$AITER_FILE" \
    && python3 -m py_compile "$AITER_FILE" \
    && rm -f /tmp/apply_aiter_lds_backport.py

LABEL io.github.fa85.r9700-vllm.aiter-lds="aiter-0.1.19-gfx1201-minimal-backport"
LABEL io.github.fa85.r9700-vllm.aiter-lds-upstream="https://github.com/ROCm/aiter/pull/5035"

FROM aiter-patched AS rocr-builder

ARG ROCR_REPO=https://github.com/mawong-amd/rocm-systems.git
ARG ROCR_COMMIT=c7e40e16bca10311af72aee09cfa0cd1726f70a7
ARG EXPECTED_ORIGINAL_HSA_SHA256=bec3c44c469d79c79c70bded96ac1c88d1c5c5e0e4b7abfa26096029075090f7

COPY patches/apply_rocr_async_events_backoff.py /tmp/apply_rocr_async_events_backoff.py
COPY patches/apply_rocr_null_event_backoff.py /tmp/apply_rocr_null_event_backoff.py

RUN test "$(sha256sum /opt/rocm-7.2.3/lib/libhsa-runtime64.so.1.18.0 | awk '{print $1}')" = \
      "$EXPECTED_ORIGINAL_HSA_SHA256"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      git cmake ninja-build g++ pkg-config python3-pip \
      libelf-dev libdrm-dev libnuma-dev libdw-dev xxd \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m pip install --no-cache-dir CppHeaderParser

RUN git init -q /tmp/rocm-systems \
    && git -C /tmp/rocm-systems remote add origin "$ROCR_REPO" \
    && git -C /tmp/rocm-systems config core.sparseCheckout true \
    && git -C /tmp/rocm-systems config remote.origin.promisor true \
    && git -C /tmp/rocm-systems config remote.origin.partialclonefilter blob:none \
    && git -C /tmp/rocm-systems sparse-checkout init --cone \
    && git -C /tmp/rocm-systems sparse-checkout set \
      projects/rocr-runtime projects/clr projects/hip shared cmake \
    && git -C /tmp/rocm-systems fetch --filter=blob:none --depth=1 \
      origin "$ROCR_COMMIT" \
    && git -C /tmp/rocm-systems checkout -q --detach FETCH_HEAD \
    && test "$(git -C /tmp/rocm-systems rev-parse HEAD)" = "$ROCR_COMMIT"

# The release image contains the LLVM executables, but not their CMake package
# files. ROCr only needs these imported executable targets during its build.
RUN mkdir -p /opt/rocm-cmake-shim \
    && printf 'if(NOT TARGET clang)\n  add_executable(clang IMPORTED GLOBAL)\n  set_target_properties(clang PROPERTIES IMPORTED_LOCATION "/opt/rocm/llvm/bin/clang")\nendif()\nset(Clang_PACKAGE_VERSION "rocm-image-shim")\n' \
      > /opt/rocm-cmake-shim/ClangConfig.cmake \
    && printf 'if(NOT TARGET llvm-objcopy)\n  add_executable(llvm-objcopy IMPORTED GLOBAL)\n  set_target_properties(llvm-objcopy PROPERTIES IMPORTED_LOCATION "/opt/rocm/llvm/bin/llvm-objcopy")\nendif()\nset(LLVM_FOUND TRUE)\nset(LLVM_PACKAGE_VERSION "rocm-image-shim")\n' \
      > /opt/rocm-cmake-shim/LLVMConfig.cmake

RUN python3 /tmp/apply_rocr_async_events_backoff.py \
      /tmp/rocm-systems/projects/rocr-runtime/runtime/hsa-runtime/core/runtime/runtime.cpp \
    && python3 /tmp/apply_rocr_async_events_backoff.py \
      /tmp/rocm-systems/projects/rocr-runtime/runtime/hsa-runtime/core/runtime/runtime.cpp \
    && python3 /tmp/apply_rocr_null_event_backoff.py \
      /tmp/rocm-systems/projects/rocr-runtime/runtime/hsa-runtime/core/runtime/interrupt_signal.cpp \
    && python3 /tmp/apply_rocr_null_event_backoff.py \
      /tmp/rocm-systems/projects/rocr-runtime/runtime/hsa-runtime/core/runtime/interrupt_signal.cpp \
    && cmake -S /tmp/rocm-systems/projects/rocr-runtime -B /tmp/rocr-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/rocm \
      -DCMAKE_PREFIX_PATH=/opt/rocm \
      -DClang_DIR=/opt/rocm-cmake-shim \
      -DLLVM_DIR=/opt/rocm-cmake-shim \
    && cmake --build /tmp/rocr-build --parallel "$(nproc)" \
    && cmake --install /tmp/rocr-build --prefix /rocr-install --strip \
    && test -f /rocr-install/lib/libhsa-runtime64.so.1.18.0 \
    && test "$(sha256sum /rocr-install/lib/libhsa-runtime64.so.1.18.0 | awk '{print $1}')" != \
      "$EXPECTED_ORIGINAL_HSA_SHA256" \
    && readelf -d /rocr-install/lib/libhsa-runtime64.so.1.18.0 \
      | grep -q 'SONAME.*libhsa-runtime64.so.1'

FROM aiter-patched AS final

ARG ROCR_COMMIT=c7e40e16bca10311af72aee09cfa0cd1726f70a7

USER root

COPY --from=rocr-builder \
  /rocr-install/lib/libhsa-runtime64.so.1.18.0 \
  /tmp/libhsa-runtime64.so.1.18.0.patched
COPY licenses/ /usr/share/doc/r9700-vllm-rocm72-fixes/licenses/
COPY THIRD_PARTY_NOTICES.md \
  /usr/share/doc/r9700-vllm-rocm72-fixes/THIRD_PARTY_NOTICES.md
COPY DISCLAIMER.md \
  /usr/share/doc/r9700-vllm-rocm72-fixes/DISCLAIMER.md

RUN set -eux; \
    cd /opt/rocm-7.2.3/lib; \
    rm -f libhsa-runtime64.so.1.18.0; \
    install -m 0644 /tmp/libhsa-runtime64.so.1.18.0.patched \
      libhsa-runtime64.so.1.18.0; \
    for file in libhsa-runtime64.so.1.*; do \
      test "$file" = "libhsa-runtime64.so.1.18.0" || \
        ln -f libhsa-runtime64.so.1.18.0 "$file"; \
    done; \
    rm -f libhsa-runtime64.so libhsa-runtime64.so.1; \
    ln -s libhsa-runtime64.so.1.18.0 libhsa-runtime64.so.1; \
    ln -s libhsa-runtime64.so.1 libhsa-runtime64.so; \
    rm -f /tmp/libhsa-runtime64.so.1.18.0.patched; \
    ldconfig; \
    test -L /opt/rocm/lib/libhsa-runtime64.so.1; \
    test "$(sha256sum /opt/rocm/lib/libhsa-runtime64.so.1 | awk '{print $1}')" = \
      "$(sha256sum /opt/rocm-7.2.3/lib/libhsa-runtime64.so.1.18.0 | awk '{print $1}')"

LABEL org.opencontainers.image.title="vLLM 0.29.0 ROCm 7.2 R9700 minimal fixes"
LABEL org.opencontainers.image.description="Official vLLM ROCm image plus three minimal gfx1201 idle/LDS fixes"
LABEL org.opencontainers.image.source="https://github.com/FA85/r9700-vllm-rocm72-fixes"
LABEL org.opencontainers.image.licenses="LicenseRef-See-Third-Party-Notices"
LABEL io.github.fa85.r9700-vllm.fix-set="aiter-lds,rocr-async-events-backoff,rocr-null-event-backoff"
LABEL io.github.fa85.r9700-vllm.rocr-source="${ROCR_COMMIT}"
LABEL io.github.fa85.r9700-vllm.rocr-async-events-backoff="ROCm/rocm-systems#7898-backport"
LABEL io.github.fa85.r9700-vllm.rocr-null-event-backoff="20-200us"
