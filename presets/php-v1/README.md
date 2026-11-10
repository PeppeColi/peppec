# php-v1

Preset for PHP projects that manage their dependencies with Composer.

| | |
| --- | --- |
| Setup | PHP, Composer 2, `composer install`, with the Composer download cache |
| Checks | `composer validate`, `vendor/bin/phpunit` |
| Agent tools | `composer`, `php`, and the usual tools under `vendor/bin` (PHPUnit, Pest, PHPStan, Psalm, Pint, PHP-CS-Fixer, PHP_CodeSniffer) |
| Not allowed | `php -S`, `php artisan serve`, `composer global` |
| Protected paths | `.php-version` and the configuration files of the tools above |

## Use it

```yaml
# .github/peppec.yml
preset: php-v1
```

## PHP version

The first one found wins:

1. `options.php-version` in `.github/peppec.yml`
2. the `.php-version` file
3. `config.platform.php` in `composer.json`
4. the lowest version allowed by `require.php` in `composer.json` (`^8.2` gives 8.2)
5. 8.4

## Options

```yaml
preset: php-v1
options:
  php-version: "8.3"
  extensions: intl, pdo_pgsql
```

## Other tools and services

The default checks only run PHPUnit. If the project has a formatter, a static analyser or another test runner, override `check`:

```yaml
preset: php-v1
check: |
  composer validate --no-check-publish
  vendor/bin/pint --test
  vendor/bin/phpstan analyse --no-progress
  vendor/bin/pest
```

A database or another service needed by the tests is started with `extra_setup`: see the setup guide.

## Limits

- `composer install` runs the scripts and the plugins the project declares in `composer.json`.
- `composer.json` is not protected, because adding a dependency changes it. Keep the check commands in `.github/peppec.yml`, not in Composer scripts the agent could rewrite.
