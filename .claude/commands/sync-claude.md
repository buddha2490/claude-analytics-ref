# /sync-claude

**Description:** Sync .claude directory across all branches, keeping newest versions

This command merges `.claude` directories across all branches in the repository, automatically detecting the newest version of each file and applying it to all branches.

## What It Does

1. **Discovers all branches** in the repository
2. **Scans `.claude/` on each branch** to find all configuration files
3. **Determines newest version** of each file by commit timestamp
4. **Updates all branches** with the latest version of each file
5. **Reports changes** made to each branch

## Usage

```bash
/sync-claude
```

When invoked, this command executes `.claude/commands/sync-claude-impl.sh`.

The command will:
- Save your current branch and return to it when done
- Process all branches automatically (main, cohort, qa-reviews, etc.)
- Skip branches that are already up-to-date
- Create a single commit per branch: `[CONFIG] Sync .claude from all branches`

## Example Output

```
🔄 Syncing .claude across all branches...

Branches found: main, cohort, qa-reviews
Scanning .claude files across branches...

Changes to apply:
  main:        3 files to update
  cohort:      1 file to update
  qa-reviews:  2 files to update

Syncing main... ✓
Syncing cohort... ✓
Syncing qa-reviews... ✓

✅ Sync complete! All branches now have latest .claude files.
```

## When to Use

- After creating new skills/commands/agents/rules on any branch
- After modifying .claude files on multiple branches
- Before starting new work (ensure you have latest tools)
- As part of your regular workflow (weekly/monthly)

## Safety Features

- **Non-destructive:** Uses newest version based on git commit timestamp
- **Automatic backup:** Git history preserves all versions
- **Branch isolation:** Changes are committed separately per branch
- **Current branch restored:** Returns you to starting branch when done

## Technical Details

The command determines "newest" by:
1. Finding the most recent commit that touched each file across all branches
2. Using that commit's timestamp as the version indicator
3. In case of ties (same timestamp), uses alphabetical branch order

Files are compared by path, so `.claude/rules/r-style.md` on different branches are treated as the same file.
