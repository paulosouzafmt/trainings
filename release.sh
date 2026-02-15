#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="release.conf"

usage() {
  cat <<'EOF'
Uso:
  ./release.sh [--patch|--minor|--major] [--dry-run]

Opções:
  --patch   incrementa PATCH (default)
  --minor   incrementa MINOR e zera PATCH
  --major   incrementa MAJOR e zera MINOR e PATCH
  --dry-run apenas mostra o que faria (não comita, não dá push, não cria tag)
EOF
}

# ---------------------------
# Parse args
# ---------------------------
BUMP="patch"
DRY_RUN=false

for arg in "${@:-}"; do
  case "${arg}" in
    --patch)   BUMP="patch" ;;
    --minor)   BUMP="minor" ;;
    --major)   BUMP="major" ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Argumento inválido: ${arg}"
      usage
      exit 1
      ;;
  esac
done

# ---------------------------
# Checks
# ---------------------------
if [[ ! -f "${CONF_FILE}" ]]; then
  echo "Arquivo ${CONF_FILE} não encontrado na raiz do repo."
  exit 1
fi

# Exigir working tree limpa
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Você tem alterações não commitadas. Commit/stash antes de criar release."
  exit 1
fi

echo "==> Atualizando refs remotas"
git fetch origin --tags

# ---------------------------
# 1) Garantir develop atualizado e sincronizado com origin/develop
# ---------------------------
echo "==> Atualizando develop"
git checkout develop >/dev/null

# Sempre puxar do remoto (fast-forward) e garantir que local == remoto
git fetch origin develop >/dev/null
LOCAL_DEV="$(git rev-parse develop)"
REMOTE_DEV="$(git rev-parse origin/develop)"
BASE_DEV="$(git merge-base develop origin/develop)"

if [[ "${LOCAL_DEV}" != "${REMOTE_DEV}" ]]; then
  if [[ "${LOCAL_DEV}" == "${BASE_DEV}" ]]; then
    # local atrás do remoto -> fast-forward
    echo "==> develop está atrás do origin/develop: fazendo fast-forward"
    if [[ "${DRY_RUN}" == true ]]; then
      echo "DRY RUN: git merge --ff-only origin/develop"
    else
      git merge --ff-only origin/develop
    fi
  elif [[ "${REMOTE_DEV}" == "${BASE_DEV}" ]]; then
    # local à frente do remoto -> abortar (evita release com develop local “solto”)
    echo "❌ develop local está à frente do origin/develop."
    echo "   Publique primeiro (git push origin develop) ou alinhe seu fluxo antes do release."
    exit 1
  else
    # divergiu
    echo "❌ develop divergiu do origin/develop."
    echo "   Resolva o merge/rebase manualmente antes de criar release."
    exit 1
  fi
else
  echo "==> develop já está alinhado com origin/develop"
fi

# ---------------------------
# 2) Ler versão e calcular nova versão conforme bump
# ---------------------------
# shellcheck disable=SC1090
source "${CONF_FILE}"
CURRENT_VERSION="${VERSION:?VERSION não definida no release.conf}"

IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}"

case "${BUMP}" in
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

# Proteção: não permitir tag já existente
if git rev-parse "${NEW_TAG}" >/dev/null 2>&1; then
  echo "❌ Tag ${NEW_TAG} já existe. Abortando."
  exit 1
fi

cat <<EOF

============================================
Tipo de release : ${BUMP}
Versão atual    : ${CURRENT_VERSION}
Nova versão     : ${NEW_VERSION}
Tag             : ${NEW_TAG}
Release string  : ${NEW_RELEASE}
Dry run         : ${DRY_RUN}
============================================

EOF

# ---------------------------
# 3) Atualizar release.conf na develop (bump primeiro na develop)
# ---------------------------
echo "==> Atualizando release.conf"
if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: escrever ${CONF_FILE} com VERSION=${NEW_VERSION} e LAST_RELEASE=\"${NEW_RELEASE}\""
else
  cat > "${CONF_FILE}" <<EOF
VERSION=${NEW_VERSION}
LAST_RELEASE="${NEW_RELEASE}"
EOF

  git add "${CONF_FILE}"
  git commit -m "chore(release): bump version to ${NEW_RELEASE}"
  git push origin develop
fi

# ---------------------------
# 4) Promover develop -> main e criar tag na main
# ---------------------------
echo "==> Atualizando main"
if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: git checkout main"
  echo "DRY RUN: git fetch origin main"
  echo "DRY RUN: garantir main alinhada com origin/main (ff-only) ou abortar"
else
  git checkout main >/dev/null
  git fetch origin main >/dev/null

  LOCAL_MAIN="$(git rev-parse main)"
  REMOTE_MAIN="$(git rev-parse origin/main)"
  BASE_MAIN="$(git merge-base main origin/main)"

  if [[ "${LOCAL_MAIN}" != "${REMOTE_MAIN}" ]]; then
    if [[ "${LOCAL_MAIN}" == "${BASE_MAIN}" ]]; then
      echo "==> main está atrás do origin/main: fazendo fast-forward"
      git merge --ff-only origin/main
    elif [[ "${REMOTE_MAIN}" == "${BASE_MAIN}" ]]; then
      echo "❌ main local está à frente do origin/main. Abortando para evitar tag inconsistente."
      exit 1
    else
      echo "❌ main divergiu do origin/main. Resolva manualmente antes do release."
      exit 1
    fi
  fi
fi

echo "==> Merge develop -> main"
if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: git merge --no-ff develop -m \"chore(release): ${NEW_RELEASE}\""
else
  git merge --no-ff develop -m "chore(release): ${NEW_RELEASE}"
fi

echo "==> Criando tag ${NEW_TAG}"
if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: git tag -a \"${NEW_TAG}\" -m \"Release ${NEW_RELEASE}\""
else
  git tag -a "${NEW_TAG}" -m "Release ${NEW_RELEASE}"
fi

echo "==> Push main + tag"
if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: git push origin main"
  echo "DRY RUN: git push origin \"${NEW_TAG}\""
else
  git push origin main
  git push origin "${NEW_TAG}"
fi

echo
echo "✅ Release criada: ${NEW_RELEASE}"
