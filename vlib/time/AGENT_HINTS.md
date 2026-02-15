# Time Module Agent Hints

- First run: `./vnew -silent test vlib/time/`
- Rebuild `./vnew` after edits here: `./v -g -keepc -o ./vnew cmd/v`
- Validate timezone/UTC assumptions and date boundary transitions.
- Prefer deterministic tests over wall-clock dependent behavior.
