#!/bin/bash
# Unit-only lock stub for disposable legacy updater installations. Native
# contention is covered separately and requires an unrestricted process probe.
_update_acquire_lock() {
    UPDATE_LOCK_CONTROL=""
    UPDATE_LOCK_HOLDER_PID=""
    UPDATE_LOCK_ACQUIRED=true
}

_update_release_lock() {
    UPDATE_LOCK_CONTROL=""
    UPDATE_LOCK_HOLDER_PID=""
    UPDATE_LOCK_ACQUIRED=false
}
