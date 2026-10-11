#!/usr/bin/env bash
# Speed comparison: PHPStan vs Mago, analyzing Laravel and Symfony framework source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools"
RESULTS="$ROOT/results"
RUNS="${RUNS:-3}"
PROJECTS=(laravel symfony)
# PHPStan phar needs PHP 8.x; prefer php8.4 when the default php is older.
PHP_BIN="${PHP_BIN:-$(command -v php8.4 || command -v php)}"

mkdir -p "$RESULTS"
TIME_BIN=/usr/bin/time
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# median <values...> -> median of the elapsed seconds (float)
median() {
    printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END {n=NR; print (n%2) ? a[(n+1)/2] : (a[n/2]+a[n/2+1])/2}'
}

# run_once <maxrss_out_file> <command...> -> prints elapsed seconds, writes peak RSS (KB) to file
run_once() {
    local rss_file="$1"; shift
    "$TIME_BIN" -f '%e %M' -o "$TMP/t" "$@" >/dev/null 2>&1 || true
    read -r elapsed rss <<<"$(tail -1 "$TMP/t")"
    echo "${rss:-0}" > "$rss_file"
    echo "${elapsed:-0}"
}

phpstan_cmd() { "$PHP_BIN" "$TOOLS/phpstan/vendor/bin/phpstan" analyse -c phpstan.neon --no-progress --error-format=raw; }
mago_cmd() { "$TOOLS/mago" analyze; }
ecs_cmd() { "$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" check --no-progress-bar "$@"; }
csfixer_cmd() { "$PHP_BIN" "$TOOLS/php-cs-fixer/vendor/bin/php-cs-fixer" check "$@"; }

# bench <tool> <mode> : prints "median_seconds peak_mb"
bench() {
    local tool="$1" mode="$2"
    local times=() rss_max=0
    for _ in $(seq "$RUNS"); do
        # cold mode: wipe the PHP engines' result caches before each run
        # (Mago and ECS `--blink` keep none)
        if [ "$mode" = cold ] && [ "$tool" = phpstan ]; then rm -rf .phpstan-cache; fi
        if [ "$mode" = cold ] && [ "$tool" = php-cs-fixer ]; then rm -f .php-cs-fixer.cache; fi
        if [ "$tool" = phpstan ]; then
            t=$(run_once "$TMP/rss" "$PHP_BIN" "$TOOLS/phpstan/vendor/bin/phpstan" analyse -c phpstan.neon --no-progress --error-format=raw)
        elif [ "$tool" = mago ]; then
            t=$(run_once "$TMP/rss" "$TOOLS/mago" analyze)
        elif [ "$tool" = ecs ]; then
            # PHP engine: clear the result cache on cold, reuse it on hot
            if [ "$mode" = cold ]; then
                t=$(run_once "$TMP/rss" "$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" check --no-progress-bar --clear-cache)
            else
                t=$(run_once "$TMP/rss" "$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" check --no-progress-bar)
            fi
        elif [ "$tool" = ecs-blink ]; then
            # the ecs-go Go binary, keeps no cache (cold == hot)
            t=$(run_once "$TMP/rss" "$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" check --blink --no-progress-bar --clear-cache)
        else
            # php-cs-fixer: cold wiped the cache above, hot reuses .php-cs-fixer.cache
            t=$(run_once "$TMP/rss" "$PHP_BIN" "$TOOLS/php-cs-fixer/vendor/bin/php-cs-fixer" check)
        fi
        times+=("$t")
        r=$(cat "$TMP/rss")
        if [ "${r:-0}" -gt "$rss_max" ]; then rss_max="$r"; fi
    done
    local med; med=$(median "${times[@]}")
    awk -v s="$med" -v m="$rss_max" 'BEGIN{printf "%.2f %.0f\n", s, m/1024}'
}

PS_VER=$("$PHP_BIN" "$TOOLS/phpstan/vendor/bin/phpstan" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
MG_VER=$("$TOOLS/mago" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
ES_VER=$("$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
CF_VER=$("$PHP_BIN" "$TOOLS/php-cs-fixer/vendor/bin/php-cs-fixer" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

OUT="$RESULTS/results.md"
{
    echo "# Results"
    echo
    echo "- Host: \`$(uname -sr)\`, PHP \`$("$PHP_BIN" -r 'echo PHP_VERSION;')\`"
    echo "- PHPStan \`$PS_VER\` (level 8), Mago \`$MG_VER\` (analyze, strict toggles)"
    echo "- ECS \`$ES_VER\` (PER-CS): PHP engine (\`check\`) and Go binary (\`check --blink\`)"
    echo "- PHP-CS-Fixer \`$CF_VER\` (@PER-CS)"
    echo "- All pinned to 24 threads/processes. Runs per cell: $RUNS (median). Time in seconds, peak memory in MB."
    echo
    echo "| Project | Files (src) | Tool | Version | Cold (s) | Hot (s) | Peak mem (MB) |"
    echo "|---------|------------:|------|---------|---------:|--------:|--------------:|"
} > "$OUT"

for proj in "${PROJECTS[@]}"; do
    cd "$ROOT/projects/$proj"
    files=$(find src -name '*.php' | wc -l | tr -d ' ')
    echo ">>> $proj: PHPStan"
    read -r ps_cold ps_mem_c < <(bench phpstan cold)
    read -r ps_hot ps_mem_h < <(bench phpstan hot)
    ps_mem=$(( ps_mem_c > ps_mem_h ? ps_mem_c : ps_mem_h ))
    echo ">>> $proj: Mago"
    read -r mg_cold mg_mem_c < <(bench mago cold)
    read -r mg_hot mg_mem_h < <(bench mago hot)
    mg_mem=$(( mg_mem_c > mg_mem_h ? mg_mem_c : mg_mem_h ))
    echo ">>> $proj: ECS (PHP engine)"
    read -r es_cold es_mem_c < <(bench ecs cold)
    read -r es_hot es_mem_h < <(bench ecs hot)
    es_mem=$(( es_mem_c > es_mem_h ? es_mem_c : es_mem_h ))
    echo ">>> $proj: ECS --blink (Go binary)"
    read -r eb_cold eb_mem_c < <(bench ecs-blink cold)
    read -r eb_hot eb_mem_h < <(bench ecs-blink hot)
    eb_mem=$(( eb_mem_c > eb_mem_h ? eb_mem_c : eb_mem_h ))
    echo ">>> $proj: PHP-CS-Fixer"
    read -r cf_cold cf_mem_c < <(bench php-cs-fixer cold)
    read -r cf_hot cf_mem_h < <(bench php-cs-fixer hot)
    cf_mem=$(( cf_mem_c > cf_mem_h ? cf_mem_c : cf_mem_h ))
    {
        echo "| $proj | $files | PHPStan | $PS_VER | $ps_cold | $ps_hot | $ps_mem |"
        echo "| $proj | $files | Mago | $MG_VER | $mg_cold | $mg_hot | $mg_mem |"
        echo "| $proj | $files | ECS | $ES_VER | $es_cold | $es_hot | $es_mem |"
        echo "| $proj | $files | ECS --blink | $ES_VER | $eb_cold | $eb_hot | $eb_mem |"
        echo "| $proj | $files | PHP-CS-Fixer | $CF_VER | $cf_cold | $cf_hot | $cf_mem |"
    } >> "$OUT"
done

cd "$ROOT"
echo
cat "$OUT"
