#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Backport only the gfx1201 LDS guard to amd-aiter 0.1.19."""

from __future__ import annotations

import sys
from pathlib import Path


MARKER = "_r9700_unified_3d_lds_footprint"

HELPER = r'''

def _r9700_unified_3d_lds_footprint(
    tile_size: int,
    head_size_padded: int,
    kv_elem_bytes: int,
    q_elem_bytes: int,
    block_m: int,
    num_stages: int,
) -> int:
    """Conservative LDS model for AITER unified attention on gfx1201."""
    return (
        2 * tile_size * head_size_padded * kv_elem_bytes * num_stages
        + block_m * head_size_padded * q_elem_bytes
    )
'''


GUARD = r'''

    # gfx1201: keep the 3D unified-attention configuration within the device
    # LDS budget. This is the minimal amd-aiter 0.1.19 backport of AITER #5035.
    if DEVICE_ARCH == "gfx1201":
        head_size_padded = triton.next_power_of_2(head_size)
        kv_elem_bytes = 1 if kv_cache_dtype == e4m3_dtype else 2
        q_elem_bytes = 1 if q_dtype == e4m3_dtype else 2
        block_m = 16

        try:
            lds_budget = int(
                torch.cuda.get_device_properties(0).shared_memory_per_block
            )
        except Exception:
            lds_budget = 65536
        if lds_budget <= 0:
            lds_budget = 65536

        lds_footprint = _r9700_unified_3d_lds_footprint(
            TILE_SIZE,
            head_size_padded,
            kv_elem_bytes,
            q_elem_bytes,
            block_m,
            attn_stages,
        )

        if lds_footprint > lds_budget:
            if attn_stages > 1:
                attn_stages = 1
                lds_footprint = _r9700_unified_3d_lds_footprint(
                    TILE_SIZE,
                    head_size_padded,
                    kv_elem_bytes,
                    q_elem_bytes,
                    block_m,
                    attn_stages,
                )

            if (
                lds_footprint > lds_budget
                and not shuffled_kv_cache
                and NUM_BLOCKS_GATHER_PER_TILE == 1
            ):
                while lds_footprint > lds_budget and TILE_SIZE > 16:
                    TILE_SIZE //= 2
                    lds_footprint = _r9700_unified_3d_lds_footprint(
                        TILE_SIZE,
                        head_size_padded,
                        kv_elem_bytes,
                        q_elem_bytes,
                        block_m,
                        attn_stages,
                    )

            if lds_footprint > lds_budget:
                raise ValueError(
                    "gfx1201 unified-attention 3D config exceeds the LDS budget: "
                    f"requires {lds_footprint} B, budget {lds_budget} B, "
                    f"TILE_SIZE={TILE_SIZE}, head_size={head_size}, "
                    f"num_stages={attn_stages}"
                )
'''


def patch(path: Path) -> bool:
    source = path.read_text()
    if MARKER in source:
        print(f"already patched: {path}")
        return False

    function_anchor = "\ndef select_3d_config("
    if function_anchor not in source:
        raise SystemExit(f"cannot find select_3d_config in {path}")
    source = source.replace(function_anchor, HELPER + function_anchor, 1)

    function_start = source.index(function_anchor)
    config_anchor = "\n    attn_config = {"
    config_pos = source.find(config_anchor, function_start)
    if config_pos < 0:
        raise SystemExit(f"cannot find attn_config insertion point in {path}")
    source = source[:config_pos] + GUARD + source[config_pos:]
    path.write_text(source)
    print(f"patched: {path}")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 1
    patch(path)
    compile(path.read_text(), str(path), "exec")
    print(f"syntax ok: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
