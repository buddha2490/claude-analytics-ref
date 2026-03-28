# .claude Directory Sync Strategy

The `.claude` directory contains all Claude Code configuration (rules, skills, commands, agents) and should be **consistent across all branches** in this repository.

## Current Status

All branches (`main`, `cohort`, `qa-reviews`) currently have identical `.claude` directories as of commit `66d0290`.

## Keeping Branches in Sync

When you make changes to `.claude` on one branch, propagate them to others:

### Option 1: Cherry-pick (Recommended for selective changes)

```bash
# Make changes to .claude on main
git checkout main
# ... edit .claude files ...
git add .claude/
git commit -m "[CONFIG] Update <rule/skill/agent> description"

# Apply the same change to cohort
git checkout cohort
git cherry-pick <commit-hash>

# Apply the same change to qa-reviews
git checkout qa-reviews
git cherry-pick <commit-hash>
```

### Option 2: Merge main into feature branches (For multiple .claude changes)

```bash
# After making several .claude changes on main
git checkout cohort
git merge main --no-ff -m "Merge main .claude updates into cohort"

git checkout qa-reviews
git merge main --no-ff -m "Merge main .claude updates into qa-reviews"
```

### Option 3: Subtree merge (Most surgical)

```bash
# Merge ONLY .claude directory from main into cohort
git checkout cohort
git checkout main -- .claude/
git commit -m "[CONFIG] Sync .claude from main"

git checkout qa-reviews
git checkout main -- .claude/
git commit -m "[CONFIG] Sync .claude from main"
```

## Best Practices

1. **Make .claude changes on main first**, then propagate to feature branches
2. **Document changes** in commit messages with `[CONFIG]` prefix
3. **Sync regularly** - don't let branches drift
4. **Test after sync** - ensure skills/agents work on each branch

## Verification

Check if branches are in sync:

```bash
# Should show no differences
git diff main cohort -- .claude/
git diff main qa-reviews -- .claude/
```

## Files to Keep Synchronized

```
.claude/
├── agents/          # 4 agents (planner, programmer, reviewer, ads-qa-reviewer)
├── commands/        # 4 commands (r-project, onboard, ct-lookup, ads-qa-review)
├── rules/           # 9 rules (style, CDISC, git, data safety, etc.)
├── skills/          # 4 skills (r-code, databricks, ads-data, cohort-cascade)
└── settings.local.json
```

## What If You Create New .claude Files on a Branch?

If you create new files on a branch other than main (e.g., `cohort` or `qa-reviews`):

1. **The file only exists on that branch** - other branches won't see it
2. **Claude Code recognizes it immediately** - the command/skill/agent is available when on that branch
3. **Branches are now out of sync** - decide how to handle it:

### Decision Tree

**Is this useful for all branches?**

✅ **YES** → Promote to all branches:
```bash
# Bring the file from feature branch to main
git checkout main
git checkout cohort -- .claude/path/to/new-file.md
git add .claude/path/to/new-file.md
git commit -m "[CONFIG] Promote new-file from cohort"

# Sync to other branches
git checkout qa-reviews && git cherry-pick main
git checkout cohort && git cherry-pick main
git checkout main
```

❌ **NO** → Keep it branch-specific:
- Do nothing! It stays on the one branch
- Good for: experimental features, branch-specific workflows
- Document it in the "Branch-Specific Configuration" section below

### Example: Branch-Specific Command

If you create `/cohort-report` on the `cohort` branch that only makes sense in that context:
1. Create it on `cohort` branch
2. Commit it
3. Leave it there - don't sync to other branches
4. Document it below

## Exception: Branch-Specific Configuration

If you need branch-specific Claude configuration (rare), document it here:

- (none currently)
