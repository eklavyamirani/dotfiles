---
name: owner-question
description: Put a decision to the owner, or act on the owner's answer, through the shared decisions doc. Use when something needs the owner's decision, when the owner says they responded or answered in the doc, when they add a question of their own there, or when writing anything about open questions that the owner will read.
---
# Questions for the owner

The owner answers from a phone, in one doc, in a few words. A good question can be answered with "A", "yes"
or "all recommended" without opening anything else. The doc's link and ids are in `STATE.md` (see the
`orchestrate` skill).

## Before you ask

Do not ask what you can decide (see the owner's limits in `STATE.md`) or what you can find out.

- **No unknowns left in it.** If an option says "unverified" or "should work", run the check first. Test a
  thing by doing the actual thing once: a search that works says nothing about opening the page.
- **Plain words.** No ids, flags, file paths or internal names unless the owner has to type them. If a term
  needs explaining, use the explanation instead of the term.
- **Pacific time**, with the weekday: "Tuesday, Nov 24 at 11:30 PM PT".
- **One decision per row.** Related choices may share a row as "1, 2, 3" if "all recommended" can answer them.
- **Options with their cost**, at most three, and your recommendation with the reason. Say so when you have
  no recommendation and why.
- **What happens with no answer**, and by when.
- **What it blocks.** Say "blocks nothing" when that is true.

## The row

Open questions are a table: number, question, what you need to know, options and my recommendation, your
answer. Numbers are stable and never reused; use the same number in chat. New questions go at the top. The
paragraph above the table always says how many questions are open, which matter first, and what expires when.

## When the owner has answered

1. Read only what changed since the revision you last saw.
2. Take the answer literally. If it settles less than the row asked (for example one part of three), act on
   that part and keep the rest open in the same row, saying what you took.
3. The owner asks about a row in a comment on it, not in the answer cell (owner, 2026-11-23: "use comments for my
   questions that I am putting in the open questions table to separate answers from commenting"). Reply in that
   comment thread with the checked answer, update the row's facts or options if they changed, and ask again. A
   question still typed into an answer cell: reply in a comment on it and leave the cell as it is.
4. Act on it. Quote their exact words, with the date, to any session that needs them.
5. Record the closed decision in the repository of the change it belongs to, with the rejected alternative
   (a decision record or the repository's decisions file). Add the row's discussion as a detail reference (owner,
   2026-11-23: "When we close on a decision, we should also add the comment thread as a detail reference that
   agents and I can use for extra context"): the comment thread, and any back-and-forth in the row, verbatim and
   in order with who said it and the doc revision, as an issue comment or in the record, linked from the
   record. Then remove the row from the doc. The doc holds
   what is open; the repositories hold what was decided.
6. Tell the owner in chat what their answer set in motion, in a few lines.

The doc also has a section where the owner adds questions of their own. Answer in the second column, briefly,
with a checked fact, and say in chat that you did.

## Editing the doc (Claude Docs connector)

Load the connector's guide (`topic.index`) once per session before the first edit. These shapes work:

- What changed: read the body node with `{"kind":"view","sinceRev":<last revision you saw>}`.
- Reword text: `{"op":"replace","target":{"kind":"find","text":"<words as they stand>"},"with":{"from":{"kind":"inline","content":"<new words>"},"as":"text"}}`.
  A find cannot cross a date chip; quote the words after it.
- Add a row: `{"op":"insert","target":{"kind":"blocks","ids":["<header row id>"]},"side":"after","source":{"as":"blocks","from":{"kind":"inline","content":[{"type":"row","content":[{"type":"cell","content":[{"type":"paragraph","content":[{"type":"text","text":"…"}]}]}, …]}]}}}`.
  Spell every cell; an empty one is `{"type":"paragraph"}`.
- Remove a row: `{"op":"delete","target":{"kind":"blocks","ids":["<row id>"]},"ifRev":<revision of your read>,"ifHash":"<the row's hash>"}`.
- A new section or table: an `insert` whose source is markdown, `"as":"markdown"`.
- A refused call changed nothing: fix the one key it names and resend the whole call.
- Never overwrite the owner's cell. Their questions about a row are comments: list them with `query` on the body
  node, reply with `create` (an utterance whose parent is the thread's first comment), and never resolve a thread
  the owner wrote in.

## Writing to the owner in chat

Lead with what they need: the result, or the decision required. A few lines. Links to pull requests and to
the doc, no ids. If something went wrong or you got something wrong, say it first and plainly.
