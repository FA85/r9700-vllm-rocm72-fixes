#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Backport ROCm/rocm-systems#7898 to the ROCr 1.18.0 source layout."""

from __future__ import annotations

import sys
from pathlib import Path


MARKER = "R9700_ROCR_POLL_BACKOFF_BACKPORT"

STATE_ANCHOR = """      bool finish = false;
      bool polling = false;
      bool init_age = true;
"""

STATE_REPLACEMENT = """      bool finish = false;
      bool polling = false;
      bool init_age = true;

      // R9700_ROCR_POLL_BACKOFF_BACKPORT
      // Backport of ROCm/rocm-systems#7898. Reset for every new wait batch.
      // Keep mixed interrupt/polling batches at the interrupt path's 200 us
      // active-poll window; a fully polling runtime may back off to 2 ms.
      const int poll_nap_ceiling_us = g_use_interrupt_wait ? 200 : 2000;
      int poll_nap_us = 20;
"""

WAIT_ANCHOR = """        if (interrupt_wait) {
          WaitForInterrupt();
          init_age = false;
        }
"""

WAIT_REPLACEMENT = """        if (interrupt_wait) {
          WaitForInterrupt();
          init_age = false;
        } else if (polling && !finish) {
          // At least one pending signal has no interrupt-backed event. Without
          // this sleep AsyncEventsLoop continuously rescans userspace state.
          os::uSleep(poll_nap_us);
          poll_nap_us = std::min(poll_nap_us * 2, poll_nap_ceiling_us);
        }
"""


def replace_once(source: str, old: str, new: str, description: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one {description} anchor, found {count}")
    return source.replace(old, new, 1)


def patch(path: Path) -> bool:
    source = path.read_text()
    if MARKER in source:
        print(f"already patched: {path}")
        return False
    source = replace_once(source, STATE_ANCHOR, STATE_REPLACEMENT, "state")
    source = replace_once(source, WAIT_ANCHOR, WAIT_REPLACEMENT, "wait")
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
    result = path.read_text()
    if result.count(MARKER) != 1 or "os::uSleep(poll_nap_us);" not in result:
        raise SystemExit("post-patch verification failed")
    print("backport verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
