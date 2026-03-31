#!/usr/bin/env bash
# Day-of stage reset: GKE demo Deployment, Cloud Run service, Artifact Registry packages.
# Does NOT run terraform destroy (use destroy-demo-infra.sh for full infra teardown).
#
# Required environment variables:
#   PROJECT_ID — <YOUR_PROJECT_ID>
#   REGION     — <YOUR_REGION>
#
# Optional (defaults shown — align with terraform.tfvars / your naming):
#   REPO_NAME, CLOUD_RUN_SERVICE, K8S_DEPLOYMENT, GKE_CLUSTER
#
# Example:
#   export PROJECT_ID="<YOUR_PROJECT_ID>"
#   export REGION="<YOUR_REGION>"
#   ./reset-demo.sh
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID to your GCP project id}"
: "${REGION:?Set REGION (e.g. us-central1)}"

REPO_NAME="${REPO_NAME:-secure-supply-chain-repo}"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-trusted-good-app}"
K8S_DEPLOYMENT="${K8S_DEPLOYMENT:-bad-app}"
GKE_CLUSTER="${GKE_CLUSTER:-demo-cluster}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${YELLOW}${BOLD}WARNING:${NC} ${YELLOW}This will delete demo runtime artifacts:${NC}"
echo "  - GKE Deployment: ${K8S_DEPLOYMENT} (cluster ${GKE_CLUSTER}, project ${PROJECT_ID})"
echo "  - Cloud Run service: ${CLOUD_RUN_SERVICE} (region ${REGION})"
echo "  - All Docker packages in Artifact Registry repo: ${REPO_NAME}"
echo ""
read -r -p "Are you sure? Type 'y' to continue: " ans
case "${ans}" in
  y|Y|yes|YES) ;;
  *)
    echo -e "${RED}Aborted. No changes made.${NC}"
    exit 1
    ;;
esac

echo ""
echo -e "${BOLD}--- Cleaning Kubernetes (GKE) ---${NC}"
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${YELLOW}No kubectl context or cluster unreachable. Fetching credentials...${NC}"
  gcloud container clusters get-credentials "${GKE_CLUSTER}" \
    --region "${REGION}" \
    --project "${PROJECT_ID}"
fi
echo -e "${RED}Deleting Deployment/${K8S_DEPLOYMENT}${NC} (ignore-not-found)..."
if kubectl delete deployment "${K8S_DEPLOYMENT}" --ignore-not-found=true; then
  echo -e "${GREEN}OK: Kubernetes Deployment cleared.${NC}"
else
  echo -e "${YELLOW}Warning: kubectl delete returned non-zero (context wrong?).${NC}"
fi

echo ""
echo -e "${BOLD}--- Cleaning Cloud Run ---${NC}"
echo -e "${RED}Deleting Cloud Run service: ${CLOUD_RUN_SERVICE}${NC}"
if gcloud run services delete "${CLOUD_RUN_SERVICE}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --quiet 2>/dev/null; then
  echo -e "${GREEN}OK: Cloud Run service removed.${NC}"
else
  echo -e "${YELLOW}Note: Service may not exist (already deleted or wrong name/region).${NC}"
fi

echo ""
echo -e "${BOLD}--- Cleaning Artifact Registry (${REPO_NAME}) ---${NC}"
REPO_ROOT="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
mapfile -t PACKAGES < <(gcloud artifacts docker packages list "${REPO_ROOT}" \
  --project "${PROJECT_ID}" \
  --format="value(name)" 2>/dev/null || true)

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No docker packages listed under ${REPO_ROOT} (empty or API delay).${NC}"
else
  for pkg in "${PACKAGES[@]}"; do
    [[ -z "${pkg}" ]] && continue
    echo -e "${RED}Deleting package:${NC} ${pkg}"
    gcloud artifacts docker packages delete "${pkg}" \
      --project "${PROJECT_ID}" \
      --quiet || echo -e "${YELLOW}Skip/fail: ${pkg}${NC}"
  done
  echo -e "${GREEN}OK: Artifact Registry packages removed.${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}Stage Ready:${NC} ${GREEN}Demo runtime artifacts cleared. Re-run Cloud Build and deploy scripts for the next rehearsal.${NC}"
echo -e "${YELLOW}Infra (GKE cluster, KMS, policies) is unchanged. Full teardown: ./destroy-demo-infra.sh${NC}"
