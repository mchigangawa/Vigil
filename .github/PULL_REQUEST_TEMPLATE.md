## What changed

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. -->

## Testing

- [ ] `./Tests/run-tests.sh` passes
- [ ] Built and ran in Xcode
- [ ] If Cleaning Mode changed: verified all three exits still work
      (auto-exit timer, hold gesture, permission revoked mid-session)
- [ ] If Keep Awake changed: `pmset -g assertions | grep -i vigil` is empty
      after quitting

## Risk

<!-- Anything that could lock a user out, leak an assertion, or need a
     permission re-grant deserves a note here. -->
