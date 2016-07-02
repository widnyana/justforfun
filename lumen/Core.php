<?php
namespace Widnyana\Lumen;

use Closure;
use Illuminate\Routing\Router;
use Laravel\Lumen;

class Core extends Lumen\Application
{
    public function group(array $attributes, Closure $callback)
    {
        $router = app(Router::class);

        $attributes = $router->mergeGroup($attributes, (array) $this->groupAttributes);

        parent::group($attributes, $callback);
    }
}

