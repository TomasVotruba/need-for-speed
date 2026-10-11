#!/usr/bin/env bash
# Speed comparison: PHPStan vs Mago, analyzing Laravel and Symfony framework source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools"
RESULTS="$ROOT/results"
RUNS="${RUNS:-3}"
PROJECTS=(laravel symfony laravel74)
# BENCH_GROUP picks which tools to run: phpstan | mago | ecs (ecs + ecs-blink) | php-cs-fixer | all.
# ROWS_ONLY=1 writes just table rows (prefixed with a sort key) to results/rows-<group>.md,
# for the parallel CI jobs that a merge step stitches back together.
BENCH_GROUP="${BENCH_GROUP:-all}"
ROWS_ONLY="${ROWS_ONLY:-0}"
case "$BENCH_GROUP" in
    phpstan)      GROUP_TOOLS=(phpstan) ;;
    mago)         GROUP_TOOLS=(mago) ;;
    ecs)          GROUP_TOOLS=(ecs ecs-blink) ;;
    php-cs-fixer) GROUP_TOOLS=(php-cs-fixer) ;;
    all)          GROUP_TOOLS=(phpstan mago ecs ecs-blink php-cs-fixer) ;;
    *) echo "unknown BENCH_GROUP: $BENCH_GROUP" >&2; exit 1 ;;
esac
# PHPStan phar needs PHP 8.x; prefer php8.4 when the default php is older.
PHP_BIN="${PHP_BIN:-$(command -v php8.4 || command -v php)}"
# The laravel74 (Laravel 8.x) rows run PHPStan under php7.4; the other checkers stay on php8.4.
PHP74_BIN="${PHP74_BIN:-$(command -v php7.4 || true)}"

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
            t=$(run_once "$TMP/rss" "$PS_PHP_BIN" "$PS_VENDOR" analyse -c phpstan.neon --no-progress --error-format=raw)
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

# tool_display / tool_rank / tool_version map a tool key to its table label, sort order and version
tool_display() {
    case "$1" in
        phpstan) echo "PHPStan" ;;
        mago) echo "Mago" ;;
        ecs) echo "ECS" ;;
        ecs-blink) echo "ECS --blink" ;;
        php-cs-fixer) echo "PHP-CS-Fixer" ;;
    esac
}
tool_rank() {
    case "$1" in
        phpstan) echo 1 ;; mago) echo 2 ;; ecs) echo 3 ;; ecs-blink) echo 4 ;; php-cs-fixer) echo 5 ;;
    esac
}
# project_label prints "Laravel 12.33" / "Symfony 7.4" from the framework's own VERSION constant
project_label() {
    local ver
    case "$1" in
        laravel|laravel74)
            ver=$(grep -oE "VERSION = '[0-9]+\.[0-9]+" src/Illuminate/Foundation/Application.php | grep -oE '[0-9]+\.[0-9]+' | head -n1)
            echo "Laravel $ver" ;;
        symfony)
            ver=$(grep -oE "VERSION = '[0-9]+\.[0-9]+" src/Symfony/Component/HttpKernel/Kernel.php | grep -oE '[0-9]+\.[0-9]+' | head -n1)
            echo "Symfony $ver" ;;
    esac
}
tool_version() {
    case "$1" in
        phpstan) "$PS_PHP_BIN" "$PS_VENDOR" --version ;;
        mago) "$TOOLS/mago" --version ;;
        ecs|ecs-blink) "$PHP_BIN" "$TOOLS/ecs/vendor/bin/ecs" --version ;;
        php-cs-fixer) "$PHP_BIN" "$TOOLS/php-cs-fixer/vendor/bin/php-cs-fixer" --version ;;
    esac | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

if [ "$ROWS_ONLY" = 1 ]; then
    OUT="$RESULTS/rows-$BENCH_GROUP.md"
    : > "$OUT"
else
    OUT="$RESULTS/results.md"
    {
        echo "# Results"
        echo
        echo "- Host: \`$(uname -sr)\`, PHP \`$("$PHP_BIN" -r 'echo PHP_VERSION;')\`"
        echo "- PHPStan level 8; Mago \`analyze\` with strict toggles; ECS and PHP-CS-Fixer at PER-CS."
        echo "- All pinned to 24 threads/processes. Runs per cell: $RUNS (median). Time in seconds, peak memory in MB."
        echo
        echo "| Project | Files (src) | Tool | Version | Cold (s) | Hot (s) | Peak mem (MB) |"
        echo "|---------|------------:|------|---------|---------:|--------:|--------------:|"
    } > "$OUT"
fi

for proj in "${PROJECTS[@]}"; do
    cd "$ROOT/projects/$proj"
    files=$(find src -name '*.php' | wc -l | tr -d ' ')
    label=$(project_label "$proj")
    case "$proj" in
        laravel)   prank=1 ;;
        symfony)   prank=2 ;;
        laravel74) prank=3 ;;
    esac
    # laravel74 runs PHPStan under php7.4 from its own install; the rest use php8.4
    if [ "$proj" = laravel74 ]; then
        PS_PHP_BIN="$PHP74_BIN"; PS_VENDOR="$TOOLS/phpstan74/vendor/bin/phpstan"
    else
        PS_PHP_BIN="$PHP_BIN"; PS_VENDOR="$TOOLS/phpstan/vendor/bin/phpstan"
    fi
    for tool in "${GROUP_TOOLS[@]}"; do
        echo ">>> $proj: $(tool_display "$tool")"
        read -r cold mem_c < <(bench "$tool" cold)
        read -r hot mem_h < <(bench "$tool" hot)
        mem=$(( mem_c > mem_h ? mem_c : mem_h ))
        row="| $label | $files | $(tool_display "$tool") | $(tool_version "$tool") | $cold | $hot | $mem |"
        if [ "$ROWS_ONLY" = 1 ]; then
            # prefix a <project-rank><tool-rank> sort key so the merge step can reorder fragments
            printf '%s%s\t%s\n' "$prank" "$(tool_rank "$tool")" "$row" >> "$OUT"
        else
            echo "$row" >> "$OUT"
        fi
    done
done

cd "$ROOT"
echo
cat "$OUT"
