#!/bin/bash
# Implementation for /sync-claude command
# Syncs .claude directory across all branches, keeping newest versions

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

# Get all branches (local only, exclude current)
BRANCHES=($(git branch --format='%(refname:short)' | grep -v '^\*'))
echo -e "Branches to sync: ${BRANCHES[*]}\n"

# Create temporary directory for tracking file versions
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Function to get last commit timestamp for a file on a branch
get_file_timestamp() {
    local branch=$1
    local file=$2
    git log -1 --format=%ct "$branch" -- "$file" 2>/dev/null || echo "0"
}

# Scan all branches and collect .claude files with their timestamps
echo "Scanning .claude files across branches..."
declare -A FILE_NEWEST_BRANCH
declare -A FILE_NEWEST_TIME

for branch in "${BRANCHES[@]}" "$ORIGINAL_BRANCH"; do
    # Get list of .claude files on this branch
    files=$(git ls-tree -r --name-only "$branch" .claude/ 2>/dev/null || echo "")

    for file in $files; do
        timestamp=$(get_file_timestamp "$branch" "$file")

        # If this is the first time seeing this file, or if this version is newer
        if [[ ! ${FILE_NEWEST_TIME[$file]+_} ]] || [[ $timestamp -gt ${FILE_NEWEST_TIME[$file]} ]]; then
            FILE_NEWEST_BRANCH[$file]=$branch
            FILE_NEWEST_TIME[$file]=$timestamp
        fi
    done
done

echo -e "Found ${#FILE_NEWEST_BRANCH[@]} unique .claude files\n"

# For each branch, determine what needs updating
declare -A BRANCH_UPDATES

for branch in "${BRANCHES[@]}" "$ORIGINAL_BRANCH"; do
    updates=0
    for file in "${!FILE_NEWEST_BRANCH[@]}"; do
        newest_branch=${FILE_NEWEST_BRANCH[$file]}

        # Skip if this branch already has the newest version
        if [[ "$newest_branch" == "$branch" ]]; then
            continue
        fi

        # Check if file exists on this branch
        current_timestamp=$(get_file_timestamp "$branch" "$file")
        newest_timestamp=${FILE_NEWEST_TIME[$file]}

        if [[ $current_timestamp -lt $newest_timestamp ]]; then
            ((updates++))
        fi
    done

    if [[ $updates -gt 0 ]]; then
        BRANCH_UPDATES[$branch]=$updates
    fi
done

# Report changes to apply
if [[ ${#BRANCH_UPDATES[@]} -eq 0 ]]; then
    echo -e "${GREEN}✅ All branches are already in sync!${NC}"
    exit 0
fi

echo -e "${YELLOW}Changes to apply:${NC}"
for branch in "${!BRANCH_UPDATES[@]}"; do
    echo "  $branch: ${BRANCH_UPDATES[$branch]} file(s) to update"
done
echo ""

# Apply updates to each branch
for branch in "${!BRANCH_UPDATES[@]}"; do
    echo -ne "Syncing $branch... "

    git checkout "$branch" -q

    # Copy newest version of each file
    for file in "${!FILE_NEWEST_BRANCH[@]}"; do
        newest_branch=${FILE_NEWEST_BRANCH[$file]}

        if [[ "$newest_branch" != "$branch" ]]; then
            current_timestamp=$(get_file_timestamp "$branch" "$file")
            newest_timestamp=${FILE_NEWEST_TIME[$file]}

            if [[ $current_timestamp -lt $newest_timestamp ]]; then
                # Copy the newest version
                git checkout "$newest_branch" -- "$file" 2>/dev/null || true
            fi
        fi
    done

    # Check if there are changes to commit
    if [[ -n $(git status --porcelain .claude/) ]]; then
        git add .claude/
        git commit -m "[CONFIG] Sync .claude from all branches" -q
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${BLUE}(no changes)${NC}"
    fi
done

# Return to original branch
git checkout "$ORIGINAL_BRANCH" -q

echo -e "\n${GREEN}✅ Sync complete! All branches now have latest .claude files.${NC}"
