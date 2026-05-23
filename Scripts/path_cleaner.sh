#!/usr/bin/env bash

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Files to search for PATH modifications
CONFIG_FILES=(
    ~/.bashrc
    ~/.bash_profile
    ~/.profile
    ~/.zshrc
    ~/.zprofile
    /etc/environment
    /etc/profile.d/*.sh
    /etc/profile
    /etc/bash.bashrc
    /etc/zsh/zshrc
    /etc/skel/*
)

# Create array from PATH using tr command
mapfile -t PATH_DIRS < <(echo "$PATH" | tr ':' '\n')

declare -A PATH_MAP
declare -A NONEXISTENT_DIRS
declare -a DUPLICATE_DIRS

echo
echo "=== PATH Directory Analysis ==="
echo

# First pass: collect all directories and check for existence
for dir in "${PATH_DIRS[@]}"; do
    [ -z "$dir" ] && continue  # skip empty entries
    
    # Check if the directory exists and print with color
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} $dir"
    else
        echo -e "${RED}✗${NC} $dir"
        NONEXISTENT_DIRS["$dir"]=1
    fi
    
    # Track duplicates
    if [[ -n "${PATH_MAP[$dir]}" ]]; then
        PATH_MAP["$dir"]=$((${PATH_MAP[$dir]} + 1))
        # Add to duplicates array if not already there
        if [[ ! " ${DUPLICATE_DIRS[@]} " =~ " ${dir} " ]]; then
            DUPLICATE_DIRS+=("$dir")
        fi
    else
        PATH_MAP["$dir"]=1
    fi
done

echo
echo "=== Non-existent Directories ==="
echo

# Check where non-existent directories are added to PATH
if [ ${#NONEXISTENT_DIRS[@]} -gt 0 ]; then
    for dir in "${!NONEXISTENT_DIRS[@]}"; do
        echo -e "${RED}Directory: $dir${NC}"
        
        # Find where it's defined
        LOCATIONS=()
        for file in "${CONFIG_FILES[@]}"; do
            # Handle wildcards in file patterns
            for expanded_file in $file; do
                if [ -f "$expanded_file" ]; then
                    if grep -q "$dir" "$expanded_file" 2>/dev/null; then
                        LOCATIONS+=("$expanded_file")
                    fi
                fi
            done
        done

        if [ ${#LOCATIONS[@]} -gt 0 ]; then
            echo "  Added to PATH in:"
            for loc in "${LOCATIONS[@]}"; do
                echo -e "    ${BLUE}- $loc${NC}"
                # Show the actual lines
                echo -e "      ${YELLOW}$(grep --color=never "$dir" "$loc" | sed 's/^/      /')${NC}"
            done
        else
            echo "  Not explicitly found in known config files (may be system default)"
        fi
        echo
    done
else
    echo "No non-existent directories found!"
    echo
fi

echo "=== Duplicate Directories ==="
echo

# Check where duplicate directories are added to PATH
if [ ${#DUPLICATE_DIRS[@]} -gt 0 ]; then
    for dir in "${DUPLICATE_DIRS[@]}"; do
        echo -e "${YELLOW}Directory: $dir (appears ${PATH_MAP[$dir]} times)${NC}"
        
        # Find where it's defined
        LOCATIONS=()
        for file in "${CONFIG_FILES[@]}"; do
            # Handle wildcards in file patterns
            for expanded_file in $file; do
                if [ -f "$expanded_file" ]; then
                    if grep -q "$dir" "$expanded_file" 2>/dev/null; then
                        LOCATIONS+=("$expanded_file")
                    fi
                fi
            done
        done

        if [ ${#LOCATIONS[@]} -gt 0 ]; then
            echo "  Added to PATH in:"
            for loc in "${LOCATIONS[@]}"; do
                echo -e "    ${BLUE}- $loc${NC}"
                # Show the actual lines
                echo -e "      ${YELLOW}$(grep --color=never "$dir" "$loc" | sed 's/^/      /')${NC}"
            done
        else
            echo "  Not explicitly found in known config files (may be added dynamically)"
        fi
        echo
    done
else
    echo "No duplicate directories found!"
    echo
fi

echo "✅ PATH analysis completed."
