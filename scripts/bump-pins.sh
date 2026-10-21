#!/usr/bin/env bash
# Bump the tool pins in setup.sh to the latest release of each tool, and write a
# versions.json describing the new pins (version + release date + min-PHP note) for
# update-readme.py. Needs `gh` authenticated (GH_TOKEN). Run from the repo root.
#
#   scripts/bump-pins.sh [out.json]   # default: versions.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/setup.sh"
OUT="${1:-$ROOT/versions.json}"

# tool key -> "setup.sh var|github repo|min-PHP note"
# the min-PHP note is static per tool and carried into the README Versions table.
TOOLS=(
  "phpstan|PHPSTAN_VERSION|phpstan/phpstan|7.4 (\`php: ^7.4\\\\|^8.0\`)"
  "mago|MAGO_VERSION|carthage-software/mago|none - standalone Rust binary"
  "ecs|ECS_VERSION|ecsphp/ecs|7.2 (\`php: >=7.2\`; \`--blink\` Go binary is runtime-independent)"
  "php-cs-fixer|PHP_CS_FIXER_VERSION|PHP-CS-Fixer/PHP-CS-Fixer|7.4 (\`php: ^7.4\\\\|^8.0\`)"
)

# latest <repo> -> "tag_name<TAB>published_date" of the newest non-prerelease release
latest() {
  gh api "repos/$1/releases?per_page=20" \
    --jq '[.[] | select(.prerelease == false and .draft == false)][0] | "\(.tag_name)\t\(.published_at)"'
}

echo "{" > "$OUT"
first=1
for entry in "${TOOLS[@]}"; do
  IFS='|' read -r key var repo note <<<"$entry"
  read -r tag published < <(latest "$repo")
  version="${tag#v}"
  released="${published%%T*}"   # YYYY-MM-DD

  # rewrite the pin default in setup.sh: VAR="${VAR:-x.y.z}"
  sed -i -E "s|^${var}=\"\\\$\{${var}:-[0-9]+\.[0-9]+\.[0-9]+\}\"|${var}=\"\${${var}:-${version}}\"|" "$SETUP"
  echo ">>> $key pinned to $version (released $released)" >&2

  [ "$first" = 1 ] || echo "," >> "$OUT"
  first=0
  printf '  "%s": {"version": "%s", "released": "%s", "repo": "%s", "min_php": "%s"}' \
    "$key" "$version" "$released" "$repo" "$note" >> "$OUT"
done
echo "" >> "$OUT"
echo "}" >> "$OUT"

echo ">>> wrote $OUT" >&2
cat "$OUT" >&2
