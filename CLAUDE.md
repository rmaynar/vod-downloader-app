<!-- rtk-instructions v2 -->
## Token Optimization (RTK)
- Prefix heavy terminal commands with `rtk` when running arbitrary inspections (e.g., `rtk git log`, `rtk cargo test`).
- Keep command outputs concise and favor quiet flags (`--quiet`, `-q`) alongside RTK filtering.
# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk proxy <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
<!-- /rtk-instructions -->
