<?php

$sup=allrows("
    SELECT *
    FROM proveedores
    ORDER BY nombre
");


$cur=allrows("
    SELECT *
    FROM monedas
    WHERE activo=1
    ORDER BY codigo
");


$prod=allrows("
    SELECT
        id_producto,
        codigo,
        nombre,
        imagen,
        stock_actual AS stock,
        costo_promedio
    FROM productos
    WHERE activo=1
    ORDER BY nombre
");


$purchases=allrows("
    SELECT
        c.*,
        p.nombre AS proveedor,
        m.codigo AS moneda
    FROM compras c
    JOIN proveedores p
        ON p.id_proveedor=c.id_proveedor
    JOIN monedas m
        ON m.id_moneda=c.id_moneda
    ORDER BY c.id_compra DESC
    LIMIT 30
");

?>

<script>
window.products=<?=json_encode($prod)?>;

window.currencies=<?=json_encode(
    $cur,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
)?>;
</script>


<section class="panel">

    <h2>Registrar compra</h2>

    <form
        id="purchaseForm"
        method="post"
        action="actions.php"
    >

        <input
            type="hidden"
            name="csrf"
            value="<?=e(csrf())?>"
        >

        <input
            type="hidden"
            name="action"
            value="purchase_save"
        >

        <input
            type="hidden"
            name="return_page"
            value="purchases"
        >


        <div class="form-grid">


            <label>
                Proveedor

                <select
                    name="proveedor"
                    required
                >

                    <option value="">
                        Seleccione
                    </option>

                    <?php foreach($sup as $s): ?>

                        <option
                            value="<?=$s['id_proveedor']?>"
                        >
                            <?=e($s['nombre'])?>
                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Moneda

                <select
                    name="moneda"
                    required
                >

                    <option value="">
                        Seleccione
                    </option>

                    <?php foreach($cur as $c): ?>

                        <option
                            value="<?=$c['id_moneda']?>"
                        >
                            <?=e($c['codigo'].' - '.$c['nombre'])?>
                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Factura

                <input
                    name="factura"
                    required
                >

            </label>


            <label>
                Descuento

                <input
                    name="descuento"
                    type="number"
                    step="0.01"
                    min="0"
                    value="0"
                >

            </label>


            <label>
                Impuesto

                <input
                    name="impuesto"
                    type="number"
                    step="0.01"
                    min="0"
                    value="0"
                >

            </label>


        </div>


        <table id="purchaseTable">

            <thead>

                <tr>
                    <th>Producto</th>
                    <th>Costo</th>
                    <th>Cantidad</th>
                    <th>Total</th>
                    <th></th>
                </tr>

            </thead>

            <tbody></tbody>

        </table>


        <button
            type="button"
            class="btn"
            onclick="addPurchaseRow()"
        >
            + Producto
        </button>


                <div class="summary">

            <span>
                Subtotal
                <b id="purchaseSubtotal">
                    $0.00
                </b>
            </span>

            <span>
                Total
                <b id="purchaseTotal">
                    $0.00
                </b>
            </span>

        </div>


        <div
            id="purchaseConversions"
            class="muted"
            style="margin:-8px 0 18px;display:flex;gap:16px;flex-wrap:wrap;justify-content:flex-end;"
        ></div>


        <button
            class="btn primary"
            type="submit"
        >
            Registrar compra
        </button>


    </form>

</section>


<section class="panel">

    <h2>Compras recientes</h2>

    <table>

        <tr>
            <th>Fecha</th>
            <th>Factura</th>
            <th>Proveedor</th>
            <th>Total</th>
            <th>Moneda</th>
        </tr>


        <?php foreach($purchases as $r): ?>

            <tr>

                <td>
                    <?=e($r['fecha'])?>
                </td>

                <td>
                    <?=e($r['numero_factura'])?>
                </td>

                <td>
                    <?=e($r['proveedor'])?>
                </td>

                <td>
                    <?=money(
                        $r['total'],
                        $r['moneda']==='USD'
                            ? '$'
                            : $r['moneda'].' '
                    )?>
                </td>

                <td>
                    <?=e($r['moneda'])?>
                </td>

            </tr>

        <?php endforeach; ?>

    </table>

</section>
