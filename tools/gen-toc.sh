#!/usr/bin/env bash
# Génère les 6 fichiers .toc depuis un seul template pour éviter toute divergence.
# Usage : tools/gen-toc.sh            écrit les fichiers
#         tools/gen-toc.sh --check    échoue si un .toc diffère de ce qui serait généré
# Numéros d'Interface : à mettre à jour à chaque patch client (mêmes valeurs que MyBossSuite).
# Un numéro périmé n'empêche pas le chargement si « Charger les addons obsolètes » est coché.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
declare -A INTERFACE=(
  [Vanilla]=11508
  [Forever]=16001
  [TBC]=20505
  [Wrath]=30405
  [Cata]=40402
  [Mists]=50500
  [Mainline]=120100
)

render() {
  cat <<TOC
## Interface: ${INTERFACE[$1]}
## Title: KickAlert
## Notes: Alerte texte, halo d'écran et son quand la cible lance un sort interruptible et que ton kick est disponible. Gratuit, code source ouvert.
## Version: ${VERSION}
## SavedVariables: KickAlertDB
## OptionalDeps: LibSharedMedia-3.0
## X-Flavor: $1
## X-License: GPL-3.0-or-later

# ATTENTION : fichier généré par tools/gen-toc.sh — ne pas éditer à la main.
# L'ordre de load est le seul mécanisme de dépendance : Locale -> Compat -> Core -> Alerts -> Detector -> Nameplates -> Config

Locale\enUS.lua
Locale\frFR.lua
Locale\deDE.lua
Locale\esES.lua
Locale\esMX.lua
Locale\itIT.lua
Locale\ptBR.lua
Locale\ruRU.lua
Locale\koKR.lua
Locale\zhCN.lua
Locale\zhTW.lua
Compat.lua
Core.lua
Alerts.lua
Detector.lua
Nameplates.lua
Config.lua
TOC
}

if [ -n "${1:-}" ] && [ "$1" != "--check" ]; then
  echo "argument inconnu : $1 (seul --check est accepté)" >&2
  exit 2
fi

status=0
for flavor in Vanilla Forever TBC Wrath Cata Mists Mainline; do
  file="KickAlert_${flavor}.toc"
  if [ "${1:-}" = "--check" ]; then
    if ! diff -q <(render "$flavor") "$file" >/dev/null 2>&1; then
      echo "périmé : $file"
      status=1
    fi
  else
    render "$flavor" > "$file"
    echo "$file"
  fi
done
exit "$status"
