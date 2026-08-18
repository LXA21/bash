<?php

$titles = [
    'dashboard' => 'Inicio',
    'products' => 'Productos',
    'inventory' => 'Inventario',
    'sales' => 'Ventas',
    'invoices' => 'Facturación',
    'clients' => 'Clientes',
    'purchases' => 'Compras',
    'suppliers' => 'Proveedores',
    'payments' => 'Métodos de pago',
    'reports' => 'Reportes',
    'backups' => 'Respaldo',
    'users' => 'Usuarios',
    'settings' => 'Configuración'
];

?>

<!doctype html>

<html lang="es">

<head>

    <meta charset="utf-8">

    <meta
        name="viewport"
        content="width=device-width,initial-scale=1"
    >

    <title>
        <?= e(APP_NAME) ?> · <?= e($titles[$page]) ?>
    </title>

    <link
        rel="stylesheet"
        href="assets/style.css"
    >

</head>


<body>


<div class="layout">


    <!-- =====================================================
         MENÚ LATERAL
         ===================================================== -->

    <aside class="sidebar">


        <!-- =================================================
             LOGO
             ================================================= -->

       <div class="brand">

    <img
        src="assets/logo.png"
        alt="NEXORA"
        class="brand-logo-img"
    >

    <div class="brand-text">

        <b>
NEXORA        </b>

        <small>
            Sistema de Facturación
        </small>

    </div>

</div>



        <!-- =================================================
             CONTENEDOR DEL MENÚ
             ================================================= -->

        <nav class="sidebar-menu">


            <?php

            foreach ($titles as $k => $v):

                /*
                 * Ocultar módulos administrativos
                 * para usuarios que no sean Administrador.
                 */

                if (
                    in_array(
                        $k,
                        ['users', 'backups', 'settings']
                    )
                    &&
                    user()['rol'] !== 'Administrador'
                ) {

                    continue;

                }

            ?>


                <a
                    class="<?= ($page === $k ? 'active' : '') ?>"
                    href="index.php?page=<?= e($k) ?>"
                >

                    <span class="menu-icon">

                        <?=
                        [
                            'dashboard' => '⌂',
                            'products' => '◇',
                            'inventory' => '▤',
                            'sales' => '🛒',
                            'invoices' => '▧',
                            'clients' => '♙',
                            'purchases' => '🛍',
                            'suppliers' => '♙',
                            'payments' => '💳',
                            'reports' => '▥',
                            'backups' => '☁',
                            'users' => '♙',
                            'settings' => '⚙'
                        ][$k]
                        ?>

                    </span>


                    <span class="menu-text">

                        <?= e($v) ?>

                    </span>

                </a>


            <?php endforeach; ?>


        </nav>


        <!-- =================================================
             CERRAR SESIÓN
             ================================================= -->

        <div class="sidebar-footer">

            <a
                class="logout"
                href="logout.php"
            >

                <span class="menu-icon">
                    ↪
                </span>

                <span class="menu-text">
                    Cerrar sesión
                </span>

            </a>

        </div>


    </aside>


    <!-- =====================================================
         CONTENIDO PRINCIPAL
         ===================================================== -->

    <main class="main">


        <header class="topbar">


            <div>

                <h1>
                    <?= e($titles[$page]) ?>
                </h1>

                <small>
                    Gestión de tu tienda
                </small>

            </div>


            <div>

                <b>
                    <?= e(user()['nombre']) ?>
                </b>

                <small>
                    <?= e(user()['rol']) ?>
                </small>

            </div>


        </header>


        <?php if ($flash): ?>

            <div class="alert <?= e($flash[0]) ?>">

                <?= e($flash[1]) ?>

            </div>

        <?php endif; ?>