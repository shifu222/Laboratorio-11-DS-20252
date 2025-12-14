#!/usr/bin/env bash
export TAG="$(./scripts/tag.sh)"
export SERVICE="${SERVICE:-order-service}"
export IMAGE_NAME="${SERVICE}"
export IMAGE_REPO="${IMAGE_REPO:-${IMAGE_NAME}}"
export IMAGE="${IMAGE_REGISTRY:+${IMAGE_REGISTRY}/}${IMAGE_REPO}:${TAG}"
echo "SERVICE=$SERVICE TAG=$TAG IMAGE=$IMAGE"
