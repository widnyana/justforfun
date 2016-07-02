### Core.php
allow you to nest laravel route groups. 

*which is revoked by Graham. see [this](https://github.com/laravel/lumen-framework/issues/85)*

how to use:
```php
// replace lumen instantiation in bootstrap/app.php with this.
// make sure the namespace is correct.
...
$app = new Widnyana\Lumen\Core(
    realpath(__DIR__.'/../')
);

// and you can do this when defining the route
$app->group([
    'prefix'    => "admin",
    'namespace' => 'App\Http\Controllers\Admin',
], function($route) use ($app) {
    $route->get('/', [
        'as'    => 'admin.index',
        'uses'  => 'AdminHomeController@getIndex'
    ]);

    /* -----------------------------------------------------------------------------------------------------------------
     * | User Management
     * ---------------------------------------------------------------------------------------------------------------*/
    $route->group([
        'prefix'    => "user"
    ], function ($app) use ($route) {
        $route->get("/", [
            'as'    => 'user.index',
            'uses'  => 'UserController@getIndex'
        ]);
    });
});
```
