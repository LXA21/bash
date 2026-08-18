<?php

$clients = allrows("
    SELECT *
    FROM clientes
    WHERE activo=1
    ORDER BY nombre
");

$cur = allrows("
    SELECT *
    FROM monedas
    WHERE activo=1
    ORDER BY codigo
");

$prod = allrows("
    SELECT
        id_producto,
        codigo,
        nombre,
        imagen,
        stock_actual AS stock,
        precio_venta,
        costo_promedio
    FROM productos
    WHERE activo=1
    ORDER BY nombre
");

$methods = allrows("
    SELECT
        mp.*,
        m.codigo AS moneda,
        m.tasa_referencia AS tasa
    FROM metodos_pago mp
    JOIN monedas m
        ON m.id_moneda=mp.id_moneda
    WHERE mp.activo=1
    ORDER BY mp.nombre
");

?>

<script>
window.products = <?=json_encode(
    $prod,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
)?>;

window.paymentMethods = <?=json_encode(
    $methods,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
)?>;

window.currencies = <?=json_encode(
    $cur,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
)?>;
</script>





<section class="panel">

    <h2>Nueva venta</h2>


    <form
        method="post"
        action="actions.php"
        id="saleForm"
    >

        <input
            type="hidden"
            name="csrf"
            value="<?=e(csrf())?>"
        >

        <input
            type="hidden"
            name="action"
            value="sale_save"
        >

        <input
            type="hidden"
            name="return_page"
            value="sales"
        >


        <div class="form-grid">

            <label>
                Cliente

                <select name="cliente">

                    <option value="0">
                        Consumidor final
                    </option>

                    <?php foreach($clients as $c): ?>

                        <option value="<?=$c['id_cliente']?>">
                            <?=e($c['nombre'])?>
                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Moneda

                <select name="moneda" required>

                    <option value="">
                        Seleccione
                    </option>

                    <?php foreach($cur as $c): ?>

                        <option value="<?=$c['id_moneda']?>">

                            <?=e(
                                $c['codigo'].' - '.$c['nombre']
                            )?>

                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Descuento

                <input
                    id="saleDiscount"
                    name="descuento"
                    type="number"
                    step="0.01"
                    value="0"
                >

            </label>


            <label>
                Impuesto

                <input
                    id="saleTax"
                    name="impuesto"
                    type="number"
                    step="0.01"
                    value="0"
                >

            </label>

        </div>


        <table id="saleTable">

            <thead>

                <tr>

                    <th>
                        Producto
                    </th>

                    <th>
                        Stock
                    </th>

                    <th>
                        Precio
                    </th>

                    <th>
                        Cantidad
                    </th>

                    <th>
                        Total
                    </th>

                    <th>
                    </th>

                </tr>

            </thead>


            <tbody></tbody>

        </table>


        <button
            type="button"
            class="btn"
            onclick="addSaleRow()"
        >
            + Producto
        </button>


        <div class="summary">

            <span>
                Subtotal
                <b id="saleSubtotal">$0.00</b>
            </span>

            <span>
                Total
                <b id="saleTotal">$0.00</b>
            </span>

        </div>


        <div
            id="saleConversions"
            class="muted"
            style="margin:-8px 0 18px;display:flex;gap:16px;flex-wrap:wrap;justify-content:flex-end;"
        ></div>


        <h3>
            Pagos
        </h3>


        <table id="paymentsTable">

            <thead>

                <tr>

                    <th>
                        Método
                    </th>

                    <th>
                        Monto
                    </th>

                    <th>
                        Tasa
                    </th>

                    <th>
                        Base
                    </th>

                    <th>
                    </th>

                </tr>

            </thead>


            <tbody></tbody>

        </table>


        <button
            type="button"
            class="btn"
            onclick="addPaymentRow()"
        >
            + Método
        </button>


        <br>
        <br>


        <button
            type="submit"
            class="btn primary"
        >
            Guardar venta y factura
        </button>


    </form>

</section>