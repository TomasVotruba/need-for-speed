# Results

- Host: `Linux 7.0.0-38-generic`, PHP `8.4.26`
- PHPStan `2.3.0` (level 8), Mago `1.53.0` (analyze, strict toggles)
- ECS `13.3.3` (PER-CS): PHP engine (`check`) and Go binary (`check --blink`)
- PHP-CS-Fixer `3.95.27` (@PER-CS)
- All pinned to 24 threads/processes. Runs per cell: 3 (median). Time in seconds.

| Project | Files (src) | Tool | Version | Cold (s) | Hot (s) |
|---------|------------:|------|---------|---------:|--------:|
| laravel | 1707 | PHPStan | 2.3.0 | 33.75 | **1.69** |
| laravel | 1707 | Mago | 1.53.0 | **1.04** |  |
| laravel | 1707 | ECS | 13.3.3 | 10.82 | 11.77 |
| laravel | 1707 | ECS --blink | 13.3.3 | 2.06 |  |
| laravel | 1707 | PHP-CS-Fixer | 3.95.27 | 15.89 | 13.55 |
| symfony | 12098 | PHPStan | 2.3.0 | 173.80 | 151.19 |
| symfony | 12098 | Mago | 1.53.0 | 4.03 |  |
| symfony | 12098 | ECS | 13.3.3 | 126.77 | 69.37 |
| symfony | 12098 | ECS --blink | 13.3.3 | 3.53 |  |
| symfony | 12098 | PHP-CS-Fixer | 3.95.27 | 147.06 | 93.12 |

## Older PHP: Laravel 8.x on PHP 7.4

PHPStan runs under `php7.4`; Mago targets PHP 7.4. ECS `13.3.3` and PHP-CS-Fixer run under `php8.4`
(their `vendor/` is platform-locked to the install PHP), checking the 7.4-era source; only the
analyzed code is 7.4. Median of 3 runs, 24 threads.

| Project | Files (src) | Tool | Version | Cold (s) | Hot (s) |
|---------|------------:|------|---------|---------:|--------:|
| laravel8 | 1084 | PHPStan | 2.3.0 | 15.72 | **1.48** |
| laravel8 | 1084 | Mago | 1.53.0 | **0.35** |  |
| laravel8 | 1084 | ECS | 13.3.3 | 6.35 | 7.21 |
| laravel8 | 1084 | ECS --blink | 13.3.3 | **1.20** |  |
| laravel8 | 1084 | PHP-CS-Fixer | 3.95.27 | 7.83 | 7.21 |
