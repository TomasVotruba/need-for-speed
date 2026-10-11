# need-for-speed

Speed comparison of PHP code-quality tools on real framework source:
static analysis with **[PHPStan](https://phpstan.org/)** (PHP) vs **[Mago](https://github.com/carthage-software/mago)** (Rust),
and coding-standard checks with **[ECS](https://github.com/ecsphp/ecs)**
in both engines - the PHP engine (`check`) and the bundled Go binary (`check --blink`) -
plus **[PHP-CS-Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer)** (the fixer ECS wraps).
All run against Laravel and Symfony `src/`. Inspired by
[php-toolchain-benchmarks](https://github.com/carthage-software/php-toolchain-benchmarks), kept minimal.

## Results

PHP 8.4, all tools pinned to 24 threads/processes, median of 3 runs.
PHPStan at level 8; Mago `analyze` with strict toggles (Mago has no numeric levels); ECS and PHP-CS-Fixer at PER-CS.
**Cold** = fresh run; **Hot** = immediate re-run (PHPStan, ECS and PHP-CS-Fixer reuse a result cache; Mago and ECS `--blink` keep none).
Measured in CI on GitHub Actions `ubuntu-latest` (4 vCPU) by the `Benchmark` workflow, so the run is
reproducible in one environment - the 24-thread pinning oversubscribes the 4 cores, so absolute numbers
run higher than on a many-core host, but tools compare fairly against each other.

### On PHP 8.4

| Project | Files | Tool | Version | Cold (s) | Hot (s) | Peak mem (MB) |
|---------|------:|------|---------|---------:|--------:|--------------:|
| Laravel | 1742 | PHPStan | 2.3.1 | 24.71 | 0.98 | 555 |
| Laravel | 1742 | Mago | 1.55.0 | 1.26 | 1.26 | 1653 |
| Laravel | 1742 | ECS | 13.3.4 | 11.95 | 10.95 | 79 |
| Laravel | 1742 | ECS --blink | 13.3.4 | **0.79** | **0.77** | 1235 |
| Laravel | 1742 | PHP-CS-Fixer | 3.95.27 | 12.67 | 11.65 | 87 |
| Symfony | 12239 | PHPStan | 2.3.1 | 106.55 | 2.91 | 887 |
| Symfony | 12239 | Mago | 1.55.0 | **4.35** | **4.27** | 1612 |
| Symfony | 12239 | ECS | 13.3.4 | 116.55 | 67.08 | 170 |
| Symfony | 12239 | ECS --blink | 13.3.4 | 5.98 | 5.98 | 832 |
| Symfony | 12239 | PHP-CS-Fixer | 3.95.27 | 122.82 | 78.76 | 188 |

### On PHP 7.4 (Laravel 8.x)

| Project | Files | Tool | Version | Cold (s) | Hot (s) | Peak mem (MB) |
|---------|------:|------|---------|---------:|--------:|--------------:|
| Laravel | 1084 | PHPStan | 2.3.0 | 15.72 | 1.48 | 328 |
| Laravel | 1084 | Mago | 1.53.0 | **0.35** | **0.34** | 933 |
| Laravel | 1084 | ECS | 13.3.3 | 6.35 | 7.21 | 61 |
| Laravel | 1084 | ECS --blink | 13.3.3 | 1.20 | 0.47 | 830 |
| Laravel | 1084 | PHP-CS-Fixer | 3.95.27 | 7.83 | 7.21 | 70 |

Mago is ~20-25x faster than PHPStan on a cold run (Symfony 106.6s -> 4.4s). PHPStan's cache - now via the
Turbo extension - makes the hot re-run near-instant on both frameworks (Laravel 24.7s -> 1.0s, Symfony
106.6s -> 2.9s), while Mago keeps no cache so its cold and hot runs match. Mago trades memory for speed -
it holds `vendor/` in memory, so peak RSS runs ~2-3x higher.

ECS runs the same PER-CS rules through two engines. The Go binary (`--blink`) is ~15-20x faster than
the PHP engine (Symfony 116.6s -> 6.0s) and, like Mago, trades memory for speed - it loads sources
into memory, so peak RSS jumps while the PHP engine stays lean. ECS's PHP-engine cache mainly helps
on Symfony (116.6s -> 67.1s); on the small Laravel `src/` the parallel startup dominates, so hot and
cold roughly match. `--blink` keeps no cache, so its cold and hot runs match.

PHP-CS-Fixer is the fixer ECS wraps, so its PHP-engine numbers land in the same ballpark as ECS's
(Symfony 122.8s cold, Laravel ~13s). Its cache helps most on Symfony (122.8s -> 78.8s). On Symfony the config
also enables the 9 risky rules that Symfony's own `@php-cs-fixer-ignore` annotations reference - without
them PHP-CS-Fixer refuses to run; they are cheap and do not move the timing.

Note the coding-standard rows use PER-CS, which is broader than PSR-12 - so these numbers run higher
than an equivalent PSR-12 pass, and under PER-CS the ECS `--blink` Go binary is the fastest tool on
the small Laravel `src/` (0.79s cold), edging out Mago.

The PHP 7.4 rows use **Laravel 8.x** (the last line supporting PHP 7.4; current Laravel needs 8.3+).
PHPStan runs under `php7.4` and Mago targets 7.4. They are not directly comparable to the 8.4
rows - different Laravel version and a smaller `src/` (1084 vs 1707 files). Mago is a standalone Rust
binary, so the PHP runtime does not affect it. ECS (`php: >=7.2`) and PHP-CS-Fixer (`php: ^7.4|^8.0`)
both support old PHP, but their `vendor/` here is installed under `php8.4`, so Composer resolves
dependencies that need 8.x - hence the 7.4 rows run the checker itself under `php8.4`, while only the
analyzed code is 7.4. Installed under `php7.4`, both would resolve 7.x-compatible dependency versions.

## Run

Needs `php8.4`, `composer`, `git`, `curl`, GNU `time`.

```bash
./setup.sh   # install tools, clone + composer-install both frameworks
./bench.sh   # benchmark -> results/results.md   (median of RUNS=3; set RUNS=1 for a quick pass)
```

`tools/` and `projects/` are gitignored and recreated by `setup.sh`.

## Versions

| Tool | Version | Released | Min PHP to run |
|------|---------|----------|----------------|
| [PHPStan](https://phpstan.org/) | 2.3.1 | 2026-10-08 | 7.4 (`php: ^7.4\|^8.0`) |
| [Mago](https://github.com/carthage-software/mago) | 1.55.0 | 2026-10-09 | none - standalone Rust binary |
| [ECS](https://github.com/ecsphp/ecs) | 13.3.4 | 2026-10-09 | 7.2 (`php: >=7.2`; `--blink` Go binary is runtime-independent) |
| [PHP-CS-Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer) | 3.95.27 | 2026-09-22 | 7.4 (`php: ^7.4\|^8.0`) |

Not a scientific benchmark: the tools run different checks and numbers are host-dependent.
