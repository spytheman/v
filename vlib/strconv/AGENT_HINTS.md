# Strconv Module Agent Hints

- First run: `./vnew -silent test vlib/strconv/`
- Rebuild `./vnew` after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Prioritize numeric parsing/formatting regressions with narrow test additions.
- Check boundary values and sign/precision behavior explicitly.
