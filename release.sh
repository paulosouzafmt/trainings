#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="release.conf"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "Arquivo release.conf não encontrado."
  exit 1
fi

# Lê versão atual
source "$CONF_FILE"

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

# Incrementa PATCH
PATCH=$((PATCH + 1))

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TIMESTAMP="$(date +%Y.%m.%d.%H%M)"
NEW_RELEASE="${NEW_VERSION} - ${TIMESTAMP}"
NEW_TAG="v${NEW_VERSION}"

echo "==> Nova versão: ${NEW_RELEASE}"

# Atualiza arquivo conf
cat > "$CONF_FILE" <<EOF
VERSION=${NEW_VERSION}
LAST_RELEASE="${NEW_RELEASE}"
EOF

# Garante que está tudo commitado antes
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Há alterações não commitadas. Commit antes da release."
  exit 1
fi

echo "==> Atualizando branches"
git checkout develop
git pull origin develop

git checkout main
git pull origin main

echo "==> Merge develop -> main"
git merge --no-ff develop -m "chore(release): ${NEW_RELEASE}"

echo "==> Commit do release.conf"
git add "$CONF_FILE"
git commit -m "chore: bump version to ${NEW_RELEASE}"

echo "==> Criando tag ${NEW_TAG}"
git tag -a "${NEW_TAG}" -m "Release ${NEW_RELEASE}"

echo "==> Push main + tag"
git push origin main
git push origin "${NEW_TAG}"

echo "✅ Release criada com sucesso:"
echo "   ${NEW_RELEASE}"
