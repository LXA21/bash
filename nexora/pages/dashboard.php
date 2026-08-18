<?php

$sales=(float)(one("
    SELECT COALESCE(SUM(total),0) n
    FROM ventas
    WHERE estado='COMPLETADA'
      AND DATE(fecha)=CURDATE()
")['n']??0);


$products=(int)(one("
    SELECT COUNT(*) n
    FROM productos
    WHERE activo=1
")['n']??0);


$stock=(float)(one("
    SELECT COALESCE(SUM(stock_actual),0) n
    FROM productos
    WHERE activo=1
")['n']??0);


$low=(int)(one("
    SELECT COUNT(*) n
    FROM productos
    WHERE activo=1
      AND stock_actual<=stock_minimo
")['n']??0);


$profit=(float)(one("
    SELECT COALESCE(
        SUM(
            (dv.precio_unitario-dv.costo_unitario)
            *dv.cantidad
        ),0
    ) n
    FROM detalle_ventas dv
    JOIN ventas v
        ON v.id_venta=dv.id_venta
    WHERE v.estado='COMPLETADA'
      AND DATE(v.fecha)=CURDATE()
")['n']??0);

?>

<div class="stats">

    <div class="card">
        <small>Ventas de hoy</small>
        <b><?=money($sales)?></b>
    </div>

    <div class="card">
        <small>Productos</small>
        <b><?=$products?></b>
    </div>

    <div class="card">
        <small>Unidades en stock</small>
        <b><?=number_format($stock,0)?></b>
    </div>

    <div class="card">
        <small>Stock bajo</small>
        <b class="red"><?=$low?></b>
    </div>

    <div class="card">
        <small>Ganancia de hoy</small>
        <b><?=money($profit)?></b>
    </div>

</div>


<div class="grid2">

    <section class="panel">

        <div class="panel-head">
            <h2>Accesos rápidos</h2>
        </div>

        <div class="quick">

            <a class="btn primary" href="?page=sales">
                Nueva venta
            </a>

            <a class="btn" href="?page=purchases">
                Nueva compra
            </a>

            <a class="btn" href="?page=products">
                Productos
            </a>

            <a class="btn" href="?page=reports">
                Reportes
            </a>

        </div>

    </section>


    <section class="panel">

        <h2>Alertas de inventario</h2>

        <?php

        $lowp=allrows("
            SELECT
                codigo,
                nombre,
                stock_actual,
                stock_minimo
            FROM productos
            WHERE activo=1
              AND stock_actual<=stock_minimo
            ORDER BY stock_actual ASC
            LIMIT 8
        ");

        ?>

        <table>

            <tr>
                <th>Producto</th>
                <th>Stock</th>
                <th>Mínimo</th>
            </tr>

            <?php foreach($lowp as $p): ?>

                <tr>

                    <td>
                        <?=e($p['nombre'])?>
                    </td>

                    <td class="red">
                        <?=e($p['stock_actual'])?>
                    </td>

                    <td>
                        <?=e($p['stock_minimo'])?>
                    </td>

                </tr>

            <?php endforeach; ?>

        </table>

        <?php if(!$lowp): ?>

            <p class="muted">
                No hay productos con stock bajo.
            </p>

        <?php endif; ?>

    </section>

</div>