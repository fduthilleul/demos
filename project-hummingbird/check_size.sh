#!/bin/bash

# Script to dynamically check sizes of Project Hummingbird container images
# Usage: ./check_size.sh [--pull]

REGISTRY="quay.io"
NAMESPACE="hummingbird"
PULL_IMAGES=false

# Parse arguments
if [ "$1" == "--pull" ]; then
    PULL_IMAGES=true
    echo "⚠️  Warning: Pulling all images may take several minutes depending on your connection..."
    echo ""
    # Start timer
    start_time=$(date +%s)
fi

# Check for required tools
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "On Linux: sudo dnf install jq"
    exit 1
fi

# Determine which container tool to use
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
else
    echo "Error: Neither podman nor docker found."
    exit 1
fi

# Fetch the list of repositories from Quay.io API
API_URL="https://quay.io/api/v1/repository?namespace=$NAMESPACE&public=true"
repos=$(curl -s "$API_URL" | jq -r '.repositories[].name' 2>/dev/null)

if [ -z "$repos" ]; then
    echo "Error: Could not fetch repository list from Quay.io"
    exit 1
fi

# Temporary file to store results
tmpfile=$(mktemp)

# For each repository, check for common tags
tags=("latest" "latest-builder")

for repo in $repos; do
    for tag in "${tags[@]}"; do
        image="$REGISTRY/$NAMESPACE/$repo:$tag"
        
        # Check if tag exists on Quay.io
        tag_check=$(curl -s "https://quay.io/api/v1/repository/$NAMESPACE/$repo/tag/?specificTag=$tag" | jq -r '.tags[]?.name' 2>/dev/null)
        
        if [ -z "$tag_check" ]; then
            continue
        fi
        
        # Pull image if requested (silently)
        if [ "$PULL_IMAGES" = true ]; then
            $CONTAINER_CMD pull "$image" &> /dev/null
        fi
        
        # Get size from local image
        size=$($CONTAINER_CMD image inspect "$image" 2>/dev/null | jq -r '.[0].Size // empty' 2>/dev/null)
        
        if [ -n "$size" ] && [ "$size" != "null" ]; then
            # Convert bytes to MB
            if command -v bc &> /dev/null; then
                size_mb=$(echo "scale=1; $size / 1024 / 1024" | bc)
            else
                size_mb=$(($size / 1024 / 1024))
            fi
            # Store in temp file: size_in_bytes|size_mb|image_name
            echo "$size|$size_mb|$image" >> "$tmpfile"
        fi
    done
done

# Sort by size (numeric sort on first field) and display
if [ -s "$tmpfile" ]; then
    sort -t'|' -n "$tmpfile" | while IFS='|' read -r bytes size_mb image; do
        printf "%-60s %s MB\n" "$image" "$size_mb"
    done
    echo ""
    echo "Total images: $(wc -l < "$tmpfile")"
    
    # Show elapsed time if pulling
    if [ "$PULL_IMAGES" = true ]; then
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))
        minutes=$((elapsed / 60))
        seconds=$((elapsed % 60))
        
        if [ $minutes -gt 0 ]; then
            echo "Time taken: ${minutes}m ${seconds}s"
        else
            echo "Time taken: ${seconds}s"
        fi
    fi
else
    echo "No images found locally."
    if [ "$PULL_IMAGES" = false ]; then
        echo "Run with --pull flag to download images first."
    fi
fi

# Cleanup
rm -f "$tmpfile"
