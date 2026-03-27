---
description: Run an AI-assisted QA review on a cloned ADS branch. Usage: /ads-qa-review <branch-folder-name> [reviewer-name]
---

# ADS QA Review Command

The user wants to run a QA review on a cloned `analytical-datasets` branch. This command orchestrates the setup and hands off to the `ads-qa-reviewer` agent.

## What to Do

### Step 1: Resolve inputs

The user may invoke this command as:
- `/ads-qa-review ADS-402-med-admin-bh-mlh-advent`
- `/ads-qa-review ADS-402-med-admin-bh-mlh-advent "Jane Smith"`
- `/ads-qa-review` (with no arguments — ask for the branch folder name)

If the branch folder name was not provided, ask:
> "Which branch folder should I review? (e.g., `ADS-402-med-admin-bh-mlh-advent`)"

If the reviewer name was not provided, ask:
> "What name should appear as reviewer on the report?"

### Step 2: Locate the branch directory

The branch is always located at:
```
QA reviews/<branch-folder-name>/
```

Verify this directory exists. If it doesn't, stop and tell the user:
> "Could not find `QA reviews/<branch-folder-name>/`. Please confirm the folder name and that the branch has been cloned."

### Step 3: Auto-detect the ticket number

Extract the Jira ticket number from the folder name using the pattern `ADS-###`:

- `ADS-402-med-admin-bh-mlh-advent` → ticket `ADS-402`
- `ADS-391-Add-LVI-from-OC` → ticket `ADS-391`

The ticket number is always the first segment matching `ADS-[0-9]+`.

### Step 4: Locate and extract the ticket document

The ticket is at:
```
QA reviews/tickets/<TICKET-NUMBER>.doc
```

If the ticket file doesn't exist, warn the user and continue without it:
> "Warning: No ticket file found at `QA reviews/tickets/ADS-402.doc`. The review will proceed but ticket fidelity analysis will be limited."

If the ticket file exists, strip the HTML to plain text before passing to the agent:

```bash
python3 -c "
import re, sys
html = sys.stdin.read()
# Decode common HTML entities
html = re.sub('&nbsp;', ' ', html)
html = re.sub('&amp;', '&', html)
html = re.sub('&lt;', '<', html)
html = re.sub('&gt;', '>', html)
html = re.sub('&#[0-9]+;', '', html)
# Strip all tags
text = re.sub('<[^>]+>', '\n', html)
# Compress whitespace
lines = [l.strip() for l in text.split('\n')]
lines = [l for l in lines if l]
print('\n'.join(lines))
" < "QA reviews/tickets/<TICKET-NUMBER>.doc"
```

Pass the extracted plain text to the agent, not the raw HTML.

### Step 5: Gather the git diff

Run these commands inside the branch directory (`QA reviews/<branch-folder-name>/`). The repo is often cloned with `--single-branch`, so `origin/master` may not exist — use the fallback sequence below.

```bash
# Attempt 1: standard remote tracking branch
git -C "QA reviews/<branch-folder-name>" diff origin/master...HEAD --name-only 2>/dev/null

# Attempt 2: origin/main
git -C "QA reviews/<branch-folder-name>" diff origin/main...HEAD --name-only 2>/dev/null

# Attempt 3: single-branch clone fallback
# Find the last merge commit (the point where master was merged into the branch)
# and extract the master parent SHA, then diff from there.
LAST_MERGE=$(git -C "QA reviews/<branch-folder-name>" log --merges -1 --format="%H" 2>/dev/null)
if [ -n "$LAST_MERGE" ]; then
  MASTER_SHA=$(git -C "QA reviews/<branch-folder-name>" cat-file -p "$LAST_MERGE" \
    | awk '/^parent/{print $2}' | tail -1)
  git -C "QA reviews/<branch-folder-name>" diff "${MASTER_SHA}...HEAD" --name-only
fi
```

Use whichever attempt produces output. If all three return nothing, check the branch state and report back to the user before proceeding.

Also run:
```bash
# Commit log for the branch work
git -C "QA reviews/<branch-folder-name>" log "${MASTER_SHA}..HEAD" --oneline
# (or origin/master..HEAD / origin/main..HEAD depending on which worked above)
```

### Step 6: Write the diff to a file

Write the full diff to a staging file so the agent can read it directly (avoids context-window truncation for large diffs):

```bash
git -C "QA reviews/<branch-folder-name>" diff <DIFF_BASE>...HEAD \
  > "QA reviews/output/<branch-folder-name>-diff.patch"
```

Where `<DIFF_BASE>` is whichever base reference worked in Step 5 (`origin/master`, `origin/main`, or `$MASTER_SHA`).

Create the `QA reviews/output/` directory if it does not exist.

### Step 7: Determine the output path

The report will be saved to:
```
QA reviews/output/<branch-folder-name>-qa-review-<YYYY-MM-DD>.md
```

Where `<YYYY-MM-DD>` is today's date.

### Step 8: Read the agent instructions and spawn the reviewer

The `ads-qa-reviewer` agent definition is at `.claude/agents/ads-qa-reviewer.md`. Because custom agent types are not automatically registered as Agent tool subagent types, you must:

1. Read `.claude/agents/ads-qa-reviewer.md`
2. Extract the content after the YAML frontmatter (everything after the second `---`)
3. Prepend those instructions to the agent prompt below
4. Spawn a `general-purpose` agent with `model: opus`

Assemble the agent prompt with this structure:

```
[AGENT INSTRUCTIONS — paste content of ads-qa-reviewer.md after frontmatter here]

---

## Your Task

Branch folder:   QA reviews/<branch-folder-name>/
Ticket number:   <ADS-###>
Reviewer name:   <reviewer-name>
Review date:     <YYYY-MM-DD>
Output path:     QA reviews/output/<branch-folder-name>-qa-review-<YYYY-MM-DD>.md
Model version:   claude-opus-4-6

## Ticket (plain text, HTML stripped)

<paste extracted ticket text>

## Changed Files

<paste --name-only output>

## Commit Log

<paste git log output>

## Full Diff

The full diff is saved at:
  QA reviews/output/<branch-folder-name>-diff.patch

Read it using the Read tool. For large diffs, read the core logic files first,
then tumor-specific programs, then documentation and whitelist changes.
```

### Step 9: Confirm completion

After the agent completes, confirm to the user:
> "QA review complete. Report saved to: `QA reviews/output/<branch-folder-name>-qa-review-<YYYY-MM-DD>.md`"

## Error Handling

| Problem | Response |
|---------|----------|
| Branch folder not found | Stop, report path, ask user to verify clone |
| All diff attempts return nothing | Verify git state, report to user, ask how to proceed |
| Ticket file missing | Warn, continue — pass "Ticket not available" to agent |
| HTML extraction fails | Fall back to passing raw ticket file path; tell agent to strip HTML when reading |
| Large diff (>1000 lines) | Proceed — diff is written to file and agent reads it section by section |
| Reviewer name missing | Ask before proceeding |
