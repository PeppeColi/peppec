<?php

declare(strict_types=1);

namespace Fixture\Tests;

use Fixture\Calculator;
use PHPUnit\Framework\TestCase;

final class CalculatorTest extends TestCase
{
    public function testSum(): void
    {
        self::assertSame(5, (new Calculator())->sum(2, 3));
    }
}
