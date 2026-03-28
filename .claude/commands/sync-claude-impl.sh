#!/bin/bash
# Implementation for /sync-claude command
# Syncs .claude directory across all branches, keeping newest versions
# Compatible with bash 3.2+ (macOS default)

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Syncing .claude across all branches...${NC}\n"

# Save current branch
ORIGINAL_BRANCH=$(git branch --show-current)
echo "Current branch: $ORIGINAL_BRANCH"

# Get all local branches
BRANCHES=($(git branch --format='%(refname:short)'))
echo -e "Branches to sync: ${BRANCHES[*]}\n"

# Create temporary directory for tracking
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# File to track newest versions: format is "filepath|branch|timestamp"
NEWEST_FILE="$TEMP_DIR/newest_versions.txt"
touch "$NEWEST_FILE"

echo "Scanning .claude files across branches..."

# Scan all branches and collect .claude files with their timestamps
for branch in "${BRANCHES[@]}"; do
    # Get list of .claude files on this branch
    git ls-tree -r --name-only "$branch" .claude/ 2>/dev/null | while read -r file; do
        # Get last commit timestamp for this file on this branch
        timestamp=$(git log -1 --format=%ct "$branch" -- "$file" 2>/dev/null || echo "0")

        # Check if we've seen this file before
        if grep -q "^${file}|" "$NEWEST_FILE"; then
            # Get current newest timestamp
            current_newest=$(grep "^${file}|" "$NEWEST_FILE" | cut -d'|' -f3)

            if [[ $timestamp -gt $current_newest ]]; then
                # This version is newer, replace it
                grep -v "^${file}|" "$NEWEST_FILE" > "$TEMP_DIR/tmp" || true
                echo "${file}|${branch}|${timestamp}" >> "$TEMP_DIR/tmp"
                mv "$TEMP_DIR/tmp" "$NEWEST_FILE"
            fi
        else
            # First time seeing this file
            echo "${file}|${branch}|${timestamp}" >> "$NEWEST_FILE"
        fi
    done
done

# Count unique files
file_count=$(wc -l < "$NEWEST_FILE" | tr -d ' ')
echo -e "Found $file_count unique .claude files\n"

# For each branch, determine what needs updating
changes_needed=0

for branch in "${BRANCHES[@]}"; do
    updates=0
    update_list="$TEMP_DIR/updates_${branch}.txt"
    touch "$update_list"

    while IFS='|' read -r file newest_branch newest_timestamp; do
        # Skip if this branch already has the newest version
        if [[ "$newest_branch" == "$branch" ]]; then
            continue
        fi

        # Get current timestamp on this branch
        current_timestamp=$(git log -1 --format=%ct "$branch" -- "$file" 2>/dev/null || echo "0")

        if [[ $current_timestamp -lt $newest_timestamp ]]; then
            echo "${file}|${newest_branch}" >> "$update_list"
            ((updates++)) || true
        fi
    done < "$NEWEST_FILE"

    if [[ $updates -gt 0 ]]; then
        echo "$branch|$updates" >> "$TEMP_DIR/branch_updates.txt"
        ((changes_needed++)) || true
    fi
done

# Report changes to apply
if [[ $changes_needed -eq 0 ]]; then
    echo -e "${GREEN}✅ All branches are already in sync!${NC}"
    exit 0
fi

echo -e "${YELLOW}Changes to apply:${NC}"
while IFS='|' read -r branch updates; do
    echo "  $branch: $updates file(s) to update"
done < "$TEMP_DIR/branch_updates.txt"
echo ""

# Apply updates to each branch
while IFS='|' read -r branch updates; do
    echo -ne "Syncing $branch... "

    git checkout "$branch" -q

    # Apply each update
    update_list="$TEMP_DIR/updates_${branch}.txt"
    while IFS='|' read -r file source_branch; do
        # Copy the newest version from source_branch
        git checkout "$source_branch" -- "$file" 2>/dev/null || true
    done < "$update_list"

    # Check if there are changes to commit
    if [[ -n $(git status --porcelain .claude/) ]]; then
        git add .claude/
        git commit -m "[CONFIG] Sync .claude from all branches" -q
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${BLUE}(no changes)${NC}"
    fi
done < "$TEMP_DIR/branch_updates.txt"

# Return to original branch
git checkout "$ORIGINAL_BRANCH" -q

echo -e "\n${GREEN}✅ Sync complete! All branches now have latest .claude files.${NC}"
