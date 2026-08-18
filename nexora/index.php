<?php

require_once __DIR__.'/functions.php';

require_login();


$page = $_GET['page'] ?? 'dashboard';


$allowed = [
    'dashboard',
    'products',
    'inventory',
    'sales',
    'invoices',
    'clients',
    'purchases',
    'suppliers',
    'payments',
    'reports',
    'backups',
    'users',
    'settings'
];


if(!in_array($page, $allowed, true)) {

    $page = 'dashboard';

}


if(
    in_array(
        $page,
        [
            'users',
            'backups',
            'settings'
        ]
    )
    &&
    user()['rol'] !== 'Administrador'
) {

    $page = 'dashboard';

}


$flash = flash();


/*
|--------------------------------------------------------------------------
| ENCABEZADO
|--------------------------------------------------------------------------
*/

include __DIR__.'/pages/_header.php';


/*
|--------------------------------------------------------------------------
| CONTENIDO DE LA PÁGINA
|--------------------------------------------------------------------------
*/

include __DIR__.'/pages/'.$page.'.php';


/*
|--------------------------------------------------------------------------
| PIE DE PÁGINA
|--------------------------------------------------------------------------
|
| El modal para seleccionar productos (usado en Ventas y
| Compras) YA NO se define aquí en PHP. Se elimina de este
| archivo a propósito porque generaba un modal duplicado
| con clases distintas (modal-overlay / modal-box) que no
| coincidían con las clases reales de style.css
| (.product-modal / .product-modal-box), lo que impedía
| que se mostrara correctamente.
|
| Ahora el modal lo crea automáticamente app.js mediante
| la función ensureProductModal(), usando siempre las
| clases correctas y quedando disponible en cualquier
| página que tenga tablas de venta o compra.
|
*/

include __DIR__.'/pages/_footer.php';

?>