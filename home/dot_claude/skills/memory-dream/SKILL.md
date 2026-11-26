---
name: memory-dream
description: Consolidate the auto memory of the current project, like the built-in auto-dream. Review recent sessions, merge, fix and prune memory files and tighten MEMORY.md. Proposes a plan first and changes nothing until the user approves it.
argument-hint: "[focus, e.g. a topic or a date range]"
disable-model-invocation: true
---

# Memory dream: consolidate the auto memory

Do a reflective pass over the auto memory of this project. Turn what was
learned recently into durable, well-organised memories, so that future
sessions can orient quickly. The auto-memory section of the system prompt
is the source of truth for the file format, the memory types, what to save
and what not to save. This skill does not restate those rules. Follow them.

If the user gave a focus (`$ARGUMENTS`), weight that topic or period first.
Still do the whole pass.

## Paths

- **Memory directory**: the one the system prompt names, for example
  `~/.claude/projects/<name>/memory/`. If the system prompt names none,
  stop and say that auto memory is off for this session.
- **Transcripts**: the `*.jsonl` files in the parent of the memory
  directory (`~/.claude/projects/<name>/`). That directory can be a
  symlink, so list it with a trailing slash. On some machines it holds no
  transcripts. Then skip the transcript search and say so in the plan.
- **Marker**: `<memory dir>/.dream-last`. It holds the ISO time of the last
  applied dream, and its mtime separates the new sessions from the old
  ones. If it is missing, this is the first dream: review the sessions of
  the last 14 days.

## Hard limits

- **No change before approval.** Phases 1 and 2 read only. Write nothing
  until the user approves the plan from phase 3.
- **Write only inside the memory directory**: `*.md` files and
  `.dream-last`. Never touch code, settings, CLAUDE.md files or the
  transcripts.
- **Read transcripts through the `jq` filter below or a narrow `grep`.**
  Never read a whole `.jsonl` file: each one is large, and most of it is
  tool output.
- **Do not copy MCP or connector output into memory.** The transcripts hold
  what MCP servers and connectors returned. Keep at most a bare pointer
  (a URL, a ticket id). What the user said or decided about it may be saved.
- **Do not copy secrets**: tokens, passwords or keys.

## Phase 1: Orient

1. List the memory directory and read `MEMORY.md`.
2. Read every topic file, or skim it if the directory is large. Know what
   exists before you suggest anything new.
3. List the sessions since the last dream:

   ```sh
   find <transcripts dir>/ -maxdepth 1 -name '*.jsonl' -newer <memory dir>/.dream-last
   ```

   Without a marker, use `-mtime -14` instead of `-newer`.

## Phase 2: Gather the signal

Look for new information worth keeping. Sources in rough priority order:

1. **Memories that drifted**: facts that contradict what the code, the
   config or the system shows now. Check named files, flags, hosts and
   commands before you trust a memory.
2. **The new sessions**: read what the user typed in each of them. The
   filter keeps only messages with `origin.kind == "human"`. That drops
   tool results, command output and system reminders, and cuts each
   message to 400 characters:

   ```sh
   jq -r 'select(.type == "user" and .origin.kind == "human")
     | .timestamp[0:16] + "  " + (
         if (.message.content | type) == "string" then .message.content
         else [.message.content[] | select(.type == "text") | .text] | join(" ") end
         | gsub("\\s+"; " ") | .[0:400])' <session>.jsonl
   ```

   Look there for corrections, decisions ("давай", "оставим", "не берем",
   "parked") and new facts about the user or the setup. A short answer like
   "3 давай" refers to your previous reply. To see what it approved, grep
   that session for a narrow term from the context and read only the hit:

   ```sh
   grep -n '<narrow term>' <session>.jsonl | tail -20 | cut -c1-2000
   ```

   Do not read transcripts end to end.
3. **Expired items**: dated checks, trials and "re-check on <date>" entries
   whose date has passed. Flag them for the user. Do not decide them yourself.
4. **Size limits that Claude Code enforces**: recall shows only the first
   4096 bytes of a memory file. It loads only the first 200 lines and
   25 000 bytes of `MEMORY.md`, and cuts off the rest. Measure both:

   ```sh
   find <memory dir>/ -name '*.md' ! -name MEMORY.md -size +4096c -printf '%s %f\n'
   wc -l -c <memory dir>/MEMORY.md
   ```

## Phase 3: Plan, then wait

Show the user one numbered plan, with one item per change, so they can
answer by number. For each item give:

- the action: **update**, **create**, **merge** (files to one file),
  **delete** or **index** (`MEMORY.md` only);
- the file names;
- one line on the reason, with the evidence: a session id and a short
  quote, or what the code shows now.

Mark items that only need the user's judgement, such as expired trials or
unclear contradictions, as **question**. Do not mark them as changes.

If nothing needs a change, say that the memory is already tight. Then go
to phase 5.

Then stop and wait. Apply only the items the user approves.

## Phase 4: Apply the approved items

- Merge new signal into existing topic files. Do not create near-duplicates.
- Convert relative dates ("yesterday", "last week", "вчера") to absolute
  dates.
- Delete contradicted facts at the source. Do not append a correction
  next to them.
- Split or condense a memory file over 4096 bytes: the rest of it is
  never seen in recall. Put the core facts first.
- Keep `MEMORY.md` an index, not a dump. Each line is
  `- [Title](file.md) — hook`. Do not shorten hooks while the index is
  well inside the limits: a detailed hook helps recall. Once it passes
  150 lines or 20 000 bytes, shorten the longest hooks first and move
  their detail into the topic files.
- Remove index lines for deleted or superseded files. Add lines for new
  files. Check that every file has exactly one index line, and every index
  line has a file.
- Link related memories with `[[name]]`.

## Phase 5: Close

1. Write the current ISO time into `<memory dir>/.dream-last` with the
   Write tool. Do this after an applied plan and after "nothing to
   change". Do not do it when the user rejected the whole plan.
2. Report in a few lines: what was updated, created, merged, deleted and
   re-indexed, and which questions are still open.
