# CP-G2a Staged Build Proof

**Date:** 2026-07-30

**Verified staged tree:** `07d4f14e4ce70aa45a3041cf84fd56a5827d63f6`

**Verified and final `Sources` subtree:** `af29be28ed05b6a0aaf3c8bda1f526baef2ac322`

**Detached verification commit:** `c78ec9386087c4d6af1cb689a3fdf9fe5a64aaae`

**Destination:** iOS Simulator `A59055F8-1354-4936-97B8-7033DF90B0BB` (iPadOS 26.5)

The verification used a detached temporary worktree created from the staged index. It
did not use the unrelated dirty files in the main checkout.

```text
/Users/prateekranka/.codex/bin/disk-preflight.sh
Result: sufficient free disk space. 60.85 GiB free.

./scripts/agent-build.sh cp-g2a-staged
warning: UIRequiresFullScreen has been deprecated starting in iOS 26.0.
warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

The final staged index has the same `Sources` subtree as the detached verification
commit. This proves compilation of the committed CP-G2a source snapshot. It does not
prove the focused behavior matrix or close the independent review findings.
