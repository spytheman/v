# Strings Module Agent Hints

- First run: `./vnew -silent test vlib/strings/`
- Rebuild `./vnew` after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Validate edge cases: unicode, slicing boundaries, and interpolation behavior.
- Keep performance-sensitive paths simple; avoid extra allocations in hot code.
