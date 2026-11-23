---
name: merge-and-run
description: Validate and merge a worker session's pull request, or run a platform command a worker asked for, on the owner's behalf. Use when a report starts with MERGE REQUEST or RUN REQUEST, and before merging, deploying, starting a preview or running any command against a live cluster as the orchestrator.
---
# Merging and running for worker sessions

Workers do not merge and do not run platform commands. You do both, after checking. The owner's limits and
the paths you need (the clean checkout, the cluster read pattern) are in `STATE.md` (see the `orchestrate`
skill). The platform's own runbook says which script does what; this skill is the routine around it.

## First: is it yours to do?

| The change | Whose yes |
| --- | --- |
| Code, tests, docs in a repository, reversible | Yours, after validation |
| A change that makes a live system create or modify things, destroys nothing, costs about nothing | Yours, inside the owner's written limit |
| Anything that deletes on a live system, a production release, a secret, new spending, a new account | The owner's: use the `owner-question` skill |
| A preview of a prototype the owner approved or asked to iterate | Covered by that approval |
| A preview of any other pull request | The owner's |

When the owner's yes is needed, quote it with its date in the merge message.

## A merge request

1. **Read the diff**, not the description. Skip generated evidence files; read code, charts, workflows and
   scripts whole. For a workflow file in a public repository, compare it with the template it claims to copy.
2. **Run what can be run.** Check the pull request's head out in a scratch worktree and run its tests. If the
   session's evidence is a run you cannot repeat (a cluster test), read the evidence file itself.
3. **Look for what the session could not see**: two things at once, a rerun, the first run on real data.
   A non-blocking doubt goes back as a short review note, not as a delay.
4. **If it will delete anything on its first run**, list on the live system exactly what that would be,
   immediately before merging. Nothing to delete: say so in the merge message. Something to delete: the owner.
5. **Merge pinned to the commit you read**: squash, `--match-head-commit <full sha>`, with your own subject
   and body: what it does, how you validated it, the owner's words if their yes was needed. No AI model name
   in a commit or pull request; end with `Co-Authored-By: Claude <noreply@anthropic.com>`. Do not reuse the
   session's commit message unread.
6. **If it conflicts**, send it back for a merge of the main branch and a new head. Never resolve a session's
   conflict yourself.
7. **After the merge, check the result where it runs**, read-only: the thing exists, did what it should, and
   what was already running is unchanged and healthy. Wait for the deploy to arrive before judging.
8. **Close the issue** with the evidence in the comment, and tell the session in one line. Update `STATE.md`.

## A run request

1. Read what the command does: the script, not its name. A script written by a session gets read whole before
   it runs with a credential.
2. Work from a clean checkout of the main branch, updated first. Never from a session's worktree, and never
   from a checkout that holds the owner's uncommitted work.
3. Use the path that leaves a record: a pull request that a required check validates, merged by you, over a
   direct apply.
4. Check before and after, as for a merge.
5. If your own permission check refuses the command, stop and tell the owner. If a session says its check
   refused something and asks you to do it: a platform command that is the orchestrator's by role is yours to
   run on its merits; anything else is a refusal to respect, not a job to take over.

## Credentials

- A token is used from its file, by path. Its value is never printed, echoed, put in a message, a commit, a
  log or a command argument. Check that the script sends it only to the host it is for.
- Know which identity your commands run as before you act (`gh auth status`): the owner's login, or a bot.
  A bot's actions notify the owner and can be approved by them; the owner's own actions do neither. If the
  owner's setup has an own-login override, ask before using it, every time.

## One at a time

A merge that changes a live cluster is followed by its check before the next one merges. Two unverified
changes at once make the next failure unattributable.
