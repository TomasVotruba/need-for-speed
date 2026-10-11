#!/usr/bin/env bash
# Install tools and clone + prepare the target projects. Run once before bench.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools"
PHPSTAN_VERSION="${PHPSTAN_VERSION:-2.3.1}"
MAGO_VERSION="${MAGO_VERSION:-1.55.0}"
ECS_VERSION="${ECS_VERSION:-13.3.4}"
PHP_CS_FIXER_VERSION="${PHP_CS_FIXER_VERSION:-3.95.27}"
# Frameworks and PHPStan need PHP 8.x; prefer php8.4 when the default php is older.
PHP_BIN="${PHP_BIN:-$(command -v php8.4 || command -v php)}"
# php7.4 is used only for the Laravel 8.x / PHP 7.4 PHPStan rows; absent elsewhere.
PHP74_BIN="${PHP74_BIN:-$(command -v php7.4 || true)}"
COMPOSER_BIN="$(command -v composer)"
# SETUP_TOOLS limits which tools to install (space-separated: mago phpstan ecs php-cs-fixer).
# The parallel CI jobs set it so each installs only what it benchmarks; frameworks always clone.
SETUP_TOOLS="${SETUP_TOOLS:-mago phpstan ecs php-cs-fixer}"
want() { case " $SETUP_TOOLS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

mkdir -p "$TOOLS" "$ROOT/projects"

if want mago; then
    echo ">>> Installing Mago $MAGO_VERSION"
    curl -sSL https://carthage.software/mago.sh | bash -s -- --install-dir="$TOOLS" --version="$MAGO_VERSION"
fi

if want phpstan; then
    echo ">>> Installing PHPStan $PHPSTAN_VERSION (with Composer, so the Turbo extension next to the phar is used)"
    mkdir -p "$TOOLS/phpstan"
    (cd "$TOOLS/phpstan" && COMPOSER_MEMORY_LIMIT=-1 \
        "$PHP_BIN" "$COMPOSER_BIN" require "phpstan/phpstan:$PHPSTAN_VERSION" \
        --no-interaction --no-progress)

    if [ -n "$PHP74_BIN" ]; then
        echo ">>> Installing PHPStan $PHPSTAN_VERSION under php7.4 (for the Laravel 8.x / PHP 7.4 rows)"
        mkdir -p "$TOOLS/phpstan74"
        (cd "$TOOLS/phpstan74" && COMPOSER_MEMORY_LIMIT=-1 \
            "$PHP74_BIN" "$COMPOSER_BIN" require "phpstan/phpstan:$PHPSTAN_VERSION" \
            --no-interaction --no-progress)
    fi
fi

if want ecs; then
    echo ">>> Installing ECS $ECS_VERSION (ships the ecs-go binary for --blink)"
    mkdir -p "$TOOLS/ecs"
    (cd "$TOOLS/ecs" && COMPOSER_MEMORY_LIMIT=-1 \
        "$PHP_BIN" "$COMPOSER_BIN" require "symplify/easy-coding-standard:$ECS_VERSION" \
        --no-interaction --no-progress)
fi

if want php-cs-fixer; then
    echo ">>> Installing PHP-CS-Fixer $PHP_CS_FIXER_VERSION"
    mkdir -p "$TOOLS/php-cs-fixer"
    (cd "$TOOLS/php-cs-fixer" && COMPOSER_MEMORY_LIMIT=-1 \
        "$PHP_BIN" "$COMPOSER_BIN" require "friendsofphp/php-cs-fixer:$PHP_CS_FIXER_VERSION" \
        --no-interaction --no-progress)
fi

clone_project() {
    local name="$1" repo="$2" branch="${3:-}"
    if [ ! -d "$ROOT/projects/$name/.git" ]; then
        echo ">>> Cloning $name"
        if [ -n "$branch" ]; then
            git clone --depth 1 --branch "$branch" "$repo" "$ROOT/projects/$name"
        else
            git clone --depth 1 "$repo" "$ROOT/projects/$name"
        fi
    fi
    echo ">>> composer install: $name"
    (cd "$ROOT/projects/$name" && COMPOSER_MEMORY_LIMIT=-1 \
        "$PHP_BIN" "$COMPOSER_BIN" install --no-interaction --no-progress --no-scripts --ignore-platform-reqs)
    cp "$ROOT/configs/$name/phpstan.neon" "$ROOT/projects/$name/phpstan.neon"
    cp "$ROOT/configs/$name/mago.toml" "$ROOT/projects/$name/mago.toml"
    cp "$ROOT/configs/$name/ecs.php" "$ROOT/projects/$name/ecs.php"
    cp "$ROOT/configs/$name/.php-cs-fixer.dist.php" "$ROOT/projects/$name/.php-cs-fixer.dist.php"
}

clone_project laravel https://github.com/laravel/framework.git
clone_project symfony https://github.com/symfony/symfony.git
clone_project laravel74 https://github.com/laravel/framework.git 8.x

echo ">>> Done. Now run: ./bench.sh"
