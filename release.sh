#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="release.conf"
BUMP="patch"
DRY_RUN=false

############################################
# Parse argumentos
############################################
for arg in "$@"; do
  case "$arg" in
    patch|--patch)
      BUMP="patch"
      ;;
    minor|--minor)
      BUMP="minor"
      ;;
    major|--major)
      BUMP="major"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "Argumento inválido: $arg"
      echo "Uso: ./release.sh [patch|minor|major|--patch|--minor|--major] [--dry-run]"
      exit 1
      ;;
  esac
done

############################################
# Validações iniciais
############################################
if [[ ! -f "$CONF_FILE" ]]; then
  echo "Arquivo release.conf não encontrado na raiz do repo."
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Você tem alterações não commitadas. Commit/stash antes de criar release."
  exit 1
fi

echo "==> Atualizando refs remotas"
git fetch origin --tags

############################################
# 1) Atualizar develop
############################################
echo "==> Atualizando develop"
git checkout develop
git pull origin develop

# shellcheck disable=SC1090
source "$CONF_FILE"
CURRENT_VERSION="${VERSION:?VERSION não definida no release.conf}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Validar versão
for n in "$MAJOR" "$MINOR" "$PATCH"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "Versão inválida em ${CONF_FILE}: ${CURRENT_VERSION}"
    exit 1
  fi
done

############################################
# 2) Aplicar BUMP
############################################
case "$BUMP" in
  patch)
    PATCH=$((PATCH + 1))
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TIMESTAMP="$(date +%Y.%m.%d.%H%M)"
NEW_RELEASE="${NEW_VERSION} - ${TIMESTAMP}"
NEW_TAG="v${NEW_VERSION}"

if git rev-parse "${NEW_TAG}" >/dev/null 2>&1; then
  echo "Tag ${NEW_TAG} já existe. Abortando."
  exit 1
fi

echo
echo "============================================"
echo "Tipo de release : $BUMP"
echo "Versão atual    : $CURRENT_VERSION"
echo "Nova versão     : $NEW_VERSION"
echo "Tag             : $NEW_TAG"
echo "Release string  : $NEW_RELEASE"
echo "Dry run         : $DRY_RUN"
echo "============================================"
echo

if [[ "$DRY_RUN" == true ]]; then
  echo "🟡 DRY RUN - Nenhuma alteração foi aplicada."
  exit 0
fi

############################################
# 3) Atualizar release.conf na develop
############################################
echo "==> Atualizando release.conf"
cat > "$CONF_FILE" <<EOF
VERSION=${NEW_VERSION}
LAST_RELEASE="${NEW_RELEASE}"
EOF

git add "$CONF_FILE"
git commit -m "chore(release): bump version to ${NEW_RELEASE}"
git push origin develop

############################################
# 4) Merge develop -> main
############################################
echo "==> Atualizando main"
git checkout main
git pull origin main

echo "==> Merge develop -> main"
git merge --no-ff develop -m "chore(release): ${NEW_RELEASE}"

############################################
# 5) Criar TAG
############################################
echo "==> Criando tag ${NEW_TAG}"
git tag -a "${NEW_TAG}" -m "Release ${NEW_RELEASE}"

echo "==> Push main + tag"
git push origin main
git push origin "${NEW_TAG}"

echo
echo "✅ Release criada: ${NEW_RELEASE}"
