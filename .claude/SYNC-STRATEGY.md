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

## Exception: Branch-Specific Configuration

If you need branch-specific Claude configuration (rare), document it here:

- (none currently)
