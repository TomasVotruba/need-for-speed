# need-for-speed

Speed comparisons of the PHP toolchain on real framework source, in two groups:

- **[Static analyzers and code modifiers](#static-analyzers-and-code-modifiers)** - PHPStan, Mago, ECS and PHP-CS-Fixer checking/fixing Laravel and Symfony `src/`.
- **[PHP parsing](#php-parsing)** - raw parser speed (nikic, php-ast, Go parsers, Mago) over a full Laravel corpus.

Inspired by [php-toolchain-benchmarks](https://github.com/carthage-software/php-toolchain-benchmarks), kept minimal.

---

## Static analyzers and code modifiers

Speed comparison of PHP code-quality tools on real framework source:
static analysis with **[PHPStan](https://phpstan.org/)** (PHP) vs **[Mago](https://github.com/carthage-software/mago)** (Rust),
and coding-standard checks with **[ECS](https://github.com/ecsphp/ecs)**
in both engines - the PHP engine (`check`) and the bundled Go binary (`check --blink`) -
plus **[PHP-CS-Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer)** (the fixer ECS wraps).
All run against Laravel and Symfony `src/`.

### Results

PHP 8.4, all tools pinned to 24 threads/processes, median of 3 runs.
PHPStan at level 8; Mago `analyze` with strict toggles (Mago has no numeric levels); ECS and PHP-CS-Fixer at PER-CS.
**Cold** = fresh run; **Hot** = immediate re-run (PHPStan, ECS and PHP-CS-Fixer reuse a result cache; Mago and ECS `--blink` keep none).
Measured in CI on GitHub Actions `ubuntu-latest` (4 vCPU) by the `Benchmark` workflow, so the run is
reproducible in one environment - the 24-thread pinning oversubscribes the 4 cores, so absolute numbers
run higher than on a many-core host, but tools compare fairly against each other.

#### On PHP 8.4

| Project | Files | Tool | Version | Cold (s) | Hot (s) |
|---------|------:|------|---------|---------:|--------:|
| Laravel 13.35 | 1742 | PHPStan | 2.3.1 | 25.87 | **1.07** |
| Laravel 13.35 | 1742 | Mago | 1.55.0 | **1.51** |  |
| Laravel 13.35 | 1742 | ECS | 13.3.4 | 11.26 | 10.34 |
| Laravel 13.35 | 1742 | ECS --blink | 13.3.4 | **0.59** |  |
| Laravel 13.35 | 1742 | PHP-CS-Fixer | 3.95.27 | 12.88 | 11.89 |
| Symfony 8.2 | 12247 | PHPStan | 2.3.1 | 114.63 | 3.37 |
| Symfony 8.2 | 12247 | Mago | 1.55.0 | 5.28 |  |
| Symfony 8.2 | 12247 | ECS | 13.3.4 | 110.92 | 62.99 |
| Symfony 8.2 | 12247 | ECS --blink | 13.3.4 | 4.70 |  |
| Symfony 8.2 | 12247 | PHP-CS-Fixer | 3.95.27 | 125.80 | 79.08 |

#### On PHP 7.4 (Laravel 8.x)

| Project | Files | Tool | Version | Cold (s) | Hot (s) |
|---------|------:|------|---------|---------:|--------:|
| Laravel 8.83 | 1084 | PHPStan | 2.3.1 | 27.62 | **1.01** |
| Laravel 8.83 | 1084 | Mago | 1.55.0 | **0.39** |  |
| Laravel 8.83 | 1084 | ECS | 13.3.4 | 6.38 | 5.56 |
| Laravel 8.83 | 1084 | ECS --blink | 13.3.4 | **0.36** |  |
| Laravel 8.83 | 1084 | PHP-CS-Fixer | 3.95.27 | 7.52 | 6.82 |

Mago is ~20x faster than PHPStan on a cold run (Symfony 114.6s -> 5.3s). PHPStan's cache - now via the
Turbo extension - makes the hot re-run near-instant on both frameworks (Laravel 25.9s -> 1.1s, Symfony
114.6s -> 3.4s), while Mago keeps no cache so its cold and hot runs match. Mago trades memory for speed -
it holds `vendor/` in memory, so peak RSS runs ~2-3x higher.

ECS runs the same PER-CS rules through two engines. The Go binary (`--blink`) is ~20x faster than
the PHP engine (Symfony 110.9s -> 4.7s) and, like Mago, trades memory for speed - it loads sources
into memory, so peak RSS jumps while the PHP engine stays lean. ECS's PHP-engine cache mainly helps
on Symfony (110.9s -> 63.0s); on the small Laravel `src/` the parallel startup dominates, so hot and
cold roughly match. `--blink` keeps no cache, so its cold and hot runs match.

PHP-CS-Fixer is the fixer ECS wraps, so its PHP-engine numbers land in the same ballpark as ECS's
(Symfony 125.8s cold, Laravel ~13s). Its cache helps most on Symfony (125.8s -> 79.1s). On Symfony the config
also enables the 9 risky rules that Symfony's own `@php-cs-fixer-ignore` annotations reference - without
them PHP-CS-Fixer refuses to run; they are cheap and do not move the timing.

Note the coding-standard rows use PER-CS, which is broader than PSR-12 - so these numbers run higher
than an equivalent PSR-12 pass, and under PER-CS the ECS `--blink` Go binary is the fastest tool overall
(Laravel 0.59s, Symfony 4.70s cold), edging out Mago.

The PHP 7.4 rows use **Laravel 8.x** (the last line supporting PHP 7.4; current Laravel needs 8.2+).
PHPStan runs under `php7.4` and Mago targets 7.4, so these are a real 7.4 pass. They are not directly
comparable to the 8.4 rows - different Laravel version and a smaller `src/` (1084 vs 1742 files). Mago is
a standalone Rust binary, so the PHP runtime does not affect it. The Laravel 8.x project installs under
`php7.4` with `require-dev` dropped, so Composer resolves 7.4-compatible dependency versions (its 8.x dev
tools need php8); ECS and PHP-CS-Fixer run the checker under `php8.4` against the 7.4 code.

### Run

Needs `php8.4` (plus `php7.4` for the Laravel 8.x rows), `composer`, `git`, `curl`, GNU `time`.

```bash
./setup.sh   # install tools, clone + composer-install the frameworks
./bench.sh   # benchmark -> results/results.md   (median of RUNS=3; set RUNS=1 for a quick pass)
```

`tools/` and `projects/` are gitignored and recreated by `setup.sh`.

### Versions

| Tool | Version | Released | Min PHP to run |
|------|---------|----------|----------------|
| [PHPStan](https://phpstan.org/) | 2.3.1 | 2026-10-08 | 7.4 (`php: ^7.4\|^8.0`) |
| [Mago](https://github.com/carthage-software/mago) | 1.55.0 | 2026-10-09 | none - standalone Rust binary |
| [ECS](https://github.com/ecsphp/ecs) | 13.3.4 | 2026-10-09 | 7.2 (`php: >=7.2`; `--blink` Go binary is runtime-independent) |
| [PHP-CS-Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer) | 3.95.27 | 2026-09-22 | 7.4 (`php: ^7.4\|^8.0`) |

Not a scientific benchmark: the tools run different checks and numbers are host-dependent.

---

## PHP parsing

Speed comparison of PHP parsers, run automatically in CI every 12 hours.

Each parser walks the same corpus - a freshly cloned [Laravel framework](https://github.com/laravel/framework) with **all Composer dependencies installed** (`src/` + `vendor/`) - and parses every `.php` file. Each tool runs **5 times** and the **average** wall-clock time is reported.

### Parsers

| Subproject | Parser | Language |
|---|---|---|
| `nikic-PHP-Parser` | [nikic/php-parser](https://github.com/nikic/PHP-Parser) v5.7 / v5.8 / v5.9 | PHP |
| `ext-ast` | [php-ast](https://github.com/nikic/php-ast) extension | PHP (C ext) |
| `z7zmey-php-parser-dev` | [z7zmey/php-parser](https://github.com/z7zmey/php-parser) | Go |
| `rector-php-parser-in-go` | [rectorphp/php-parser-in-go](https://github.com/rectorphp/php-parser-in-go) | Go |
| `halleck45-go-php-parser` | [halleck45/go-php-parser](https://github.com/Halleck45/go-php-parser) | Go + embedded PHP (cgo) |
| `mago-syntax` | [mago-syntax](https://github.com/carthage-software/mago) v1.50 | Rust |

### Latest results

Each run produces two tables - every parser pinned to a single core, vs all runner cores available. `nikic/php-parser` is benchmarked at three versions (v5.7, v5.8, v5.9); they land within run-to-run noise of each other - no version got measurably faster, the library has no perf changes between them.

#### Single core (`taskset -c 0`)

```
Rank | Parser                        | Avg (5 runs) | vs slowest
   1 | mago-syntax (single-threaded) |     1,19 s    |      26.5x
   2 | ext-ast                       |     1,93 s    |      16.4x
   3 | z7zmey/php-parser             |     3,55 s    |       8.9x
   4 | halleck45/go-php-parser       |     5,37 s    |       5.9x
   5 | rectorphp/php-parser-in-go    |     6,02 s    |       5.2x
   6 | nikic/php-parser (v5.7)       |    30,63 s    |       1.0x
   7 | nikic/php-parser (v5.9)       |    30,65 s    |       1.0x
   8 | nikic/php-parser (v5.8)       |    31,58 s    |       1.0x
```

#### All cores

```
Rank | Parser                     | Avg (5 runs) | vs slowest
   1 | mago-syntax (parallel)     |     0,57 s    |      56.7x
   2 | ext-ast                    |     2,00 s    |      16.1x
   3 | z7zmey/php-parser          |     2,49 s    |      12.9x
   4 | halleck45/go-php-parser    |     2,82 s    |      11.4x
   5 | rectorphp/php-parser-in-go |     4,78 s    |       6.7x
   6 | nikic/php-parser (v5.7)    |    30,34 s    |       1.1x
   7 | nikic/php-parser (v5.8)    |    31,03 s    |       1.0x
   8 | nikic/php-parser (v5.9)    |    32,05 s    |       1.0x
```

### Sample AST dump

Separate CI jobs (`dump-*`) parse one small fixture - [`sample-class.php`](sample-class.php), a ~25-line class - with each parser and print the resulting node tree to that job's **Summary** page. This shows the *shape* of each parser's output (each emits a different format) without wading through the full corpus. Run locally with `make dump` in any subproject.

Timings come from shared GitHub-hosted runners - good for rough ranking, not precise benchmarking. Live numbers appear in every run's **Summary** page.

**Core count matters.** The `ubuntu-latest` standard runner has only **4 vCPUs** (16 GB RAM). How each parser reacts to extra cores:

- **`mago-syntax (parallel)`** - the only one that actually parses files across cores. Scales **~2.1x** (1193->565 ms) and stays fastest in absolute terms.
- **`nikic`, `ext-ast`** - single-threaded PHP. Single-core and all-core numbers match.
- **`halleck45`, `z7zmey`, `rectorphp/php-parser-in-go`** - parse sequentially, but the Go runtime (GC, scheduler, sysmon) uses extra cores anyway, so pinning to one core (`taskset -c 0`) slows them down. The speedup tracks `GOMAXPROCS`, not the workload - neither does any parallel parsing:
    - `halleck45` gains the most (**~1.9x**: 5371->2819 ms) - Go + cgo around an embedded PHP, so more runtime/allocation work to offload.
    - `z7zmey` is pure Go with less heap churn, so its gain is smaller (**~1.4x**: 3553->2485 ms).
    - `rectorphp/php-parser-in-go` shares the z7zmey lineage and behaves similarly (**~1.25x**: 6017->4780 ms).

Absolute numbers reflect a noisy-neighbour VM, not bare metal; only the *relative* ranking is meaningful, and even that can shift with runner contention.
