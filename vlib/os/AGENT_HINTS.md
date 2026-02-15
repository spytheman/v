# OS Module Agent Hints

- First run: `./vnew -silent test vlib/os/`
- Add focused file tests when a single area regresses.
- Rebuild `./vnew` after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Watch for platform-specific files (`*_windows*`, `*_linux*`, `*_nix*`).
- Prefer minimal cross-platform changes unless the bug requires wider edits.
