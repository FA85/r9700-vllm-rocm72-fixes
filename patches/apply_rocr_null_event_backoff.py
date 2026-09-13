#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Back off BLOCKED InterruptSignal waits that have no KFD event."""

from __future__ import annotations

import sys
from pathlib import Path


MARKER = "R9700_ROCR_NULL_EVENT_BACKOFF"

STATE_ANCHOR = """  const uint32_t &signal_abort_timeout =
    core::Runtime::runtime_singleton_->flag().signal_abort_timeout();
"""

STATE_REPLACEMENT = """  const uint32_t &signal_abort_timeout =
    core::Runtime::runtime_singleton_->flag().signal_abort_timeout();

  // R9700_ROCR_NULL_EVENT_BACKOFF
  // EventPool exhaustion leaves a valid userspace signal without a KFD event.
  // Back off while polling so idle listeners do not consume a complete core.
  uint32_t no_event_poll_nap_us = 20;
"""

WAIT_ANCHOR = """    auto remaining_ms = timer::duration_cast<std::chrono::milliseconds>(
      fast_timeout - (now - start_time)).count();
"""

WAIT_REPLACEMENT = """    if (event_ == nullptr) {
      // hsaKmtWaitOnEvent_Ext(nullptr, ...) returns INVALID_HANDLE immediately.
      auto remaining_us = timer::duration_cast<std::chrono::microseconds>(
        fast_timeout - (now - start_time)).count();
      if (remaining_us > 0) {
        const uint32_t nap_us = static_cast<uint32_t>(std::min<uint64_t>(
          no_event_poll_nap_us, static_cast<uint64_t>(remaining_us)));
        os::uSleep(nap_us);
        no_event_poll_nap_us = std::min<uint32_t>(no_event_poll_nap_us * 2, 200);
      }
      continue;
    }

    auto remaining_ms = timer::duration_cast<std::chrono::milliseconds>(
      fast_timeout - (now - start_time)).count();
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
    if (
        result.count(MARKER) != 1
        or "if (event_ == nullptr)" not in result
        or "os::uSleep(nap_us);" not in result
    ):
        raise SystemExit("post-patch verification failed")
    print("null-event backoff patch verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
