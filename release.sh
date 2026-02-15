#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="release.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "Arquivo release.conf não encontrado na raiz do repo."
  exit 1
fi

# Exigir working tree limpa
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Você tem alterações não commitadas. Commit/stash antes de criar release."
  exit 1
fi

# shellcheck disable=SC1090
# shellcheck disable=SC1090
source "$CONF_FILE"

CURRENT_VERSION="${VERSION}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Incrementa PATCH corretamente
NEW_PATCH=$((PATCH + 1))

NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
TIMESTAMP="$(date +%Y.%m.%d.%H%M)"
NEW_RELEASE="${NEW_VERSION} - ${TIMESTAMP}"
NEW_TAG="v${NEW_VERSION}"


echo "==> Release: ${NEW_RELEASE}"

echo "==> Atualizando develop"
git fetch origin
git checkout develop
git pull

echo "==> Atualizando main"
git checkout main
git pull

echo "==> Merge develop -> main"
git merge --no-ff develop -m "chore(release): ${NEW_RELEASE}"

echo "==> Atualizando release.conf"
cat > "$CONF_FILE" <<EOF
VERSION=${NEW_VERSION}
LAST_RELEASE="${NEW_RELEASE}"
EOF

git add "$CONF_FILE"
git commit -m "chore: bump version to ${NEW_RELEASE}"

echo "==> Criando tag ${NEW_TAG}"
git tag -a "${NEW_TAG}" -m "Release ${NEW_RELEASE}"

echo "==> Push main + tag"
git push origin main
git push origin "${NEW_TAG}"

echo "✅ Release criada: ${NEW_RELEASE}"
