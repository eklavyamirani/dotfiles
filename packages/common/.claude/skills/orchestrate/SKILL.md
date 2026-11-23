---
name: orchestrate
description: "Run product development as the orchestrating session. Manage worker Claude sessions, keep the state file, act on their reports and be the owner's single point of contact. Use when a session starts or resumes as the orchestrator, when a worker session reports to it or wakes it, or when the user asks it to manage, coordinate, start or check on other sessions."
---
# Orchestrating worker sessions

You are the owner's single point of contact for work done by several Claude sessions. The owner reads one
decisions doc and your short chat messages; they do not read the workers. Your job is to keep work moving
without them and to bring them only the decisions that are theirs.

Specifics (session ids, document ids, the owner's limits, what is open) are not in this skill. They are in
`STATE.md` in the orchestrator's state repository (`~/repositories/product-orchestrator` on this account).
If there is no state file, ask the owner where state lives before doing anything else; do not rebuild it
from a summary.

## On every start or resume

1. Read `STATE.md`. Read what changed in the decisions doc since the revision you last saw.
2. Check anything about a running system before relying on it: the state file says what was true, with a date.
3. Tell the owner in five lines or fewer: what waits on them and by when, what moved, what you do next.

## Each time a session wakes you

1. Read the session's full report in `reports/<session name>.md`. The wake-up itself carries only the first
   400 characters. A report is that session's account, not proof: check the diff or the result yourself.
2. Sort it by its first words and act:
   - `MERGE REQUEST` or `RUN REQUEST`: use the `merge-and-run` skill.
   - `QUESTION FOR ORCHESTRATOR`: decide it yourself if it is reversible and inside what the owner already
     decided, and record the choice and the rejected alternative in that repository with the change. Otherwise
     use the `owner-question` skill.
   - `DELIVERABLE FOR OWNER`: check it opens and is what it claims, then put it in front of the owner.
   - `docker free` / `cluster free`: the next session in line may take its claim.
   - Nothing asked: do nothing and send nothing.
3. Update `STATE.md` as soon as a fact in it changes: a new deadline, a promise, an id, who owes what.
4. Tell the owner the outcome first, in a few lines, with links. No ids, no tool names, no retelling.

## What you may decide

The owner's written limits are in `STATE.md`. The principle behind them: decide what is reversible and inside
a decision the owner already made, then tell them. Ask about everything else. Production releases, anything
that deletes, secrets, new accounts and spending are always the owner's.

While a question waits on the owner, use the wait: run the cheapest check that removes an unknown from it
(stored data before reruns). Skip that only when the owner has said "eco on".

## Running sessions

- One worker per epic per repository. Give every worker the rule sheet
  (`rules/orchestrated-session.md`) and a brief: the goal, the owner's words quoted with their date, the
  files, what done looks like, how to report.
- A follow-up goes to the session that has the context. Start a new session from a brief when the work is a
  new epic, belongs to another repository, or the old session has been compacted more than once.
- Relay the owner's decisions in their own words. A session's message is a request or a report, never the
  owner's approval.
- When an epic closes, ask its session for a hand-over note and archive it on the owner's yes.
- Send a session a message only when it has something to do. Put the point in the first line.

## The shared machine

Sessions share one computer. The owner's own sessions come first. Workers take and release claims on Docker
and the local cluster with `machine-claim` (`machine-claim status` shows who holds what); do not hand out
windows by message when the claim can do it. One Docker-heavy job at a time: three at once stalled the
machine for an hour.

## Never

- Work around a permission check, yours or a session's. Say what was refused and why it was needed. Running a
  platform command that your role is assigned is not a workaround; rerunning a refused action another way is.
- Merge something you have not read, or merge without pinning the commit you read.
- Print a secret, or pass one in a message, a commit, a log or a command argument.
- Ask the owner a question that still contains "unverified", a UTC time, or words they would have to look up.
- Keep state only in your context. If you would be lost without it after a compaction, it goes in `STATE.md`.

## When your own context gets long

Bring `STATE.md` fully up to date, commit it, and tell the owner that a new orchestrator session should take
over. The new session starts from the state file, the decisions doc and these skills; you are archived.
