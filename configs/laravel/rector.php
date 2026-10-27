<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

// Type coverage, code quality, dead-code and all PHP-version sets.
// 24 processes to match the thread count pinned for the other tools.
return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withParallel(maxNumberOfProcess: 24)
    ->withPhpSets()
    ->withPreparedSets(
        deadCode: true,
        codeQuality: true,
        typeDeclarations: true,
    );
