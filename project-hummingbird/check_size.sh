#!/bin/bash

# Script to dynamically check sizes of Project Hummingbird container images
# Usage: ./check_size.sh [--pull]

REGISTRY="quay.io"
NAMESPACE="hummingbird"
PULL_IMAGES=false

# Parse arguments
if [ "$1" == "--pull" ]; then
    PULL_IMAGES=true
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

echo "Discovering Project Hummingbird images from $REGISTRY/$NAMESPACE..."
echo ""

# Fetch the list of repositories from Quay.io API
API_URL="https://quay.io/api/v1/repository?namespace=$NAMESPACE&public=true"
repos=$(curl -s "$API_URL" | jq -r '.repositories[].name' 2>/dev/null)

if [ -z "$repos" ]; then
    echo "Error: Could not fetch repository list from Quay.io"
    echo "Falling back to checking locally available images..."
    $CONTAINER_CMD images --format "{{.Repository}}:{{.Tag}}" | grep "^$REGISTRY/$NAMESPACE/" | sort
    exit 0
fi

# For each repository, check for common tags
tags=("latest" "latest-builder")
count=0

for repo in $repos; do
    for tag in "${tags[@]}"; do
        image="$REGISTRY/$NAMESPACE/$repo:$tag"
        
        # Check if tag exists on Quay.io
        tag_check=$(curl -s "https://quay.io/api/v1/repository/$NAMESPACE/$repo/tag/?specificTag=$tag" | jq -r '.tags[]?.name' 2>/dev/null)
        
        if [ -z "$tag_check" ]; then
            continue
        fi
        
        # Pull image if requested
        if [ "$PULL_IMAGES" = true ]; then
            echo "Pulling $image..."
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
            printf "%-60s %s MB\n" "$image" "$size_mb"
            count=$((count + 1))
        else
            if [ "$PULL_IMAGES" = false ]; then
                printf "%-60s Not pulled locally\n" "$image"
            fi
        fi
    done
done

echo ""
echo "Found $count images locally"
echo ""

if [ "$PULL_IMAGES" = false ]; then
    echo "To pull all available images and check their sizes, run:"
    echo "  $0 --pull"
fi

echo ""
echo "To pull specific images manually:"
echo "  $CONTAINER_CMD pull quay.io/hummingbird/<image-name>:latest"
