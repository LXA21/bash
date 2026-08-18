<?php
// =========================================================================
// 1. CONFIGURACIÓN DEL BUSCADOR Y PAGINACIÓN
// =========================================================================
$limit = 10; // Mostrar 10 facturas por página
$page_actual = isset($_GET['p']) ? max(1, (int)$_GET['p']) : 1;
$offset = ($page_actual - 1) * $limit;

$search = isset($_GET['search']) ? trim($_GET['search']) : '';
$where = "1=1";
$params = [];

if ($search !== '') {
    // 1. Convertimos la búsqueda del usuario a minúsculas desde PHP (soporta acentos)
    $search_lower = mb_strtolower($search, 'UTF-8');
    $like = '%' . $search_lower . '%';
    
    // 2. Usamos LOWER() en SQL para convertir el texto de las tablas a minúsculas al comparar
    $where .= " AND (
        LOWER(v.numero_factura) LIKE ? 
        OR LOWER(c.nombre) LIKE ? 
        OR v.fecha LIKE ? 
        OR CAST(v.total AS CHAR) LIKE ? 
        OR EXISTS (
            SELECT 1 FROM detalle_ventas dv 
            JOIN productos pr ON dv.id_producto = pr.id_producto 
            WHERE dv.id_venta = v.id_venta AND LOWER(pr.nombre) LIKE ?
        )
    )";
    
    // Se inserta la variable ya en minúsculas para los 5 parámetros
    $params = [$like, $like, $like, $like, $like];
}

// =========================================================================
// 2. CÁLCULO DE PÁGINAS TOTALES
// =========================================================================
$countQuery = "SELECT COUNT(v.id_venta) as total_rows 
               FROM ventas v 
               LEFT JOIN clientes c ON c.id_cliente = v.id_cliente 
               WHERE $where";
$totalRows = one($countQuery, $params)['total_rows'];
$totalPages = ceil($totalRows / $limit);

// =========================================================================
// 3. OBTENER FACTURAS DE LA PÁGINA ACTUAL
// =========================================================================
$query = "SELECT v.*, c.nombre cliente, m.codigo moneda 
          FROM ventas v 
          LEFT JOIN clientes c ON c.id_cliente=v.id_cliente 
          JOIN monedas m ON m.id_moneda=v.id_moneda 
          WHERE $where 
          ORDER BY v.id_venta DESC 
          LIMIT $limit OFFSET $offset";
$rows = allrows($query, $params);

// =========================================================================
// 3.1 CLIENTES (para el selector del modal de edición)
// =========================================================================
$clientsList = allrows("
    SELECT id_cliente, nombre
    FROM clientes
    WHERE activo=1
    ORDER BY nombre
");

// =========================================================================
// 3.2 PRODUCTOS ACTIVOS (para editar las líneas de una factura)
// =========================================================================
$productsList = allrows("
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

// =========================================================================
// 4. GENERADOR DE HTML PARA LOS CONTROLES DE NAVEGACIÓN
// =========================================================================
$paginationHtml = '';
if ($totalPages > 1) {
    $paginationHtml .= '<div style="display: flex; gap: 5px; margin: 15px 0; align-items: center; justify-content: flex-end; flex-wrap: wrap;">';
    
    // Botón "Anterior"
    if ($page_actual > 1) {
        $prev = $page_actual - 1;
        $paginationHtml .= '<a class="btn sm" href="?page=invoices&p='.$prev.'&search='.urlencode($search).'">&laquo; Anterior</a>';
    }
    
    // Números de paginación
    for ($i = 1; $i <= $totalPages; $i++) {
        // Mostrar solo páginas cercanas, primera o última para no deformar el diseño
        if ($i == 1 || $i == $totalPages || ($i >= $page_actual - 2 && $i <= $page_actual + 2)) {
            $activeStyle = ($i === $page_actual) ? 'style="background: #333; color: #fff; border-color: #333;"' : '';
            $paginationHtml .= '<a class="btn sm" href="?page=invoices&p='.$i.'&search='.urlencode($search).'" '.$activeStyle.'>'.$i.'</a>';
        } elseif ($i == $page_actual - 3 || $i == $page_actual + 3) {
            $paginationHtml .= '<span>...</span>';
        }
    }
    
    // Botón "Siguiente"
    if ($page_actual < $totalPages) {
        $next = $page_actual + 1;
        $paginationHtml .= '<a class="btn sm" href="?page=invoices&p='.$next.'&search='.urlencode($search).'">Siguiente &raquo;</a>';
    }
    
    $paginationHtml .= '</div>';
}
?>

<script>
window.products = <?=json_encode(
    $productsList,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
)?>;
</script>

<section class="panel">
    <!-- Encabezado con buscador -->
    <div class="panel-head" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 15px; margin-bottom: 10px;">
        <div>
            <h2 style="margin: 0;">Facturas</h2>
            <p class="muted" style="margin: 4px 0 0;">Haz clic en una factura para editar cliente, número, fecha u observaciones.</p>
        </div>
        
        <form method="get" action="index.php" style="display: flex; gap: 8px;">
            <input type="hidden" name="page" value="invoices">
            <input type="text" name="search" value="<?=e($search)?>" placeholder="Buscar por cliente, n°, fecha, producto, total..." style="padding: 6px 12px; border: 1px solid #ccc; border-radius: 4px; width: 280px; max-width: 100%;">
            <button type="submit" class="btn">Buscar</button>
            <?php if($search): ?>
                <a href="?page=invoices" class="btn danger" style="padding: 6px 12px; text-decoration: none;">Limpiar</a>
            <?php endif; ?>
        </form>
    </div>

    <!-- Paginación Superior -->
    <?=$paginationHtml?>

    <div style="overflow-x: auto;">
        <table style="width: 100%; border-collapse: collapse;">
            <tr>
                <th style="text-align: left;">Número</th>
                <th style="text-align: left;">Fecha</th>
                <th style="text-align: left;">Cliente</th>
                <th style="text-align: left;">Total</th>
                <th style="text-align: left;">Estado</th>
                <th></th>
            </tr>
            
            <?php if(empty($rows)): ?>
            <tr>
                <td colspan="6" style="text-align: center; padding: 30px;">No se encontraron facturas que coincidan con tu búsqueda.</td>
            </tr>
            <?php else: ?>
                <?php foreach($rows as $r):?>
                <tr
                    class="<?=($r['estado']!=='ANULADA' ? 'clickable-row' : '')?>"
                    <?php if($r['estado']!=='ANULADA'): ?>
                    data-id="<?=e($r['id_venta'])?>"
                    data-numero="<?=e($r['numero_factura'])?>"
                    data-cliente="<?=e($r['id_cliente'])?>"
                    data-fecha="<?=e(substr($r['fecha'],0,10))?>"
                    data-observaciones="<?=e($r['observaciones'])?>"
                    title="Clic para editar"
                    <?php endif; ?>
                >
                    <td><?=e($r['numero_factura'])?></td>
                    <td><?=e($r['fecha'])?></td>
                    <td><?=e($r['cliente']??'Consumidor final')?></td>
                    <td><?=money($r['total'],$r['moneda']==='USD'?'$':$r['moneda'].' ')?></td>
                    <td><span class="badge"><?=e($r['estado'])?></span></td>
                    <td style="text-align: right;"><a class="btn sm" href="?page=invoices&view=<?=$r['id_venta']?>" onclick="event.stopPropagation()">Ver</a></td>
                </tr>
                <?php endforeach;?>
            <?php endif; ?>
        </table>
    </div>

    <!-- Paginación Inferior -->
    <?=$paginationHtml?>
</section>

<!-- =========================================================
     MODAL PARA VER FACTURA
     ========================================================= -->
<?php
if(isset($_GET['view'])){
    $id=(int)$_GET['view'];
    $v=one("SELECT v.*,c.nombre cliente,c.documento,m.codigo moneda,m.simbolo FROM ventas v LEFT JOIN clientes c ON c.id_cliente=v.id_cliente JOIN monedas m ON m.id_moneda=v.id_moneda WHERE v.id_venta=?",[$id]);
    $items=allrows("SELECT d.*,p.nombre FROM detalle_ventas d JOIN productos p ON p.id_producto=d.id_producto WHERE d.id_venta=?",[$id]);

    if($v):
?>

<div
    id="invoiceViewModal"
    class="edit-modal show"
    aria-hidden="false"
>

    <div
        class="edit-modal-box invoice-view-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="invoiceViewTitle"
    >

        <button
            type="button"
            class="edit-modal-close no-print"
            onclick="location.href='?page=invoices'"
            aria-label="Cerrar"
        >
            &times;
        </button>


        <div class="edit-modal-body" id="invoicePrintArea">

            <h2 id="invoiceViewTitle">
                Factura <?=e($v['numero_factura'])?>
            </h2>

            <p class="invoice-meta">
                <b>Cliente:</b> <?=e($v['cliente']??'Consumidor final')?> &middot; <b>Fecha:</b> <?=e($v['fecha'])?>
            </p>

            <table style="width: 100%;">
                <tr>
                    <th style="text-align: left;">Producto</th>
                    <th style="text-align: left;">Cantidad</th>
                    <th style="text-align: left;">Precio</th>
                    <th style="text-align: left;">Total</th>
                </tr>
                <?php foreach($items as $i):?>
                <tr>
                    <td><?=e($i['nombre'])?></td>
                    <td><?=$i['cantidad']?></td>
                    <td><?=money($i['precio_unitario'],$v['simbolo'])?></td>
                    <td><?=money($i['subtotal'],$v['simbolo'])?></td>
                </tr>
                <?php endforeach;?>
            </table>

            <h2 class="right" style="text-align: right; margin-top: 15px;">Total: <?=money($v['total'],$v['simbolo'])?></h2>
            <?php

            /*
             * Conversión a otras monedas, usando la tasa
             * congelada en el momento de la venta.
             * Si la factura es anterior a esta función
             * (tasas_cambio vacío), usamos la tasa actual
             * como respaldo.
             */

            $tasasVenta=[];

            if(!empty($v['tasas_cambio'])) {
                $decoded=json_decode($v['tasas_cambio'],true);
                if(is_array($decoded)) {
                    $tasasVenta=$decoded;
                }
            }

            if(empty($tasasVenta)) {
                $fallback=allrows("SELECT codigo,tasa_referencia FROM monedas WHERE activo=1");
                foreach($fallback as $fc) {
                    $tasasVenta[$fc['codigo']]=(float)$fc['tasa_referencia'];
                }
            }

            $baseCur=base_currency();

            ?>

            <?php if(!empty($tasasVenta)): ?>

                <div style="text-align:right;margin-top:4px;">

                    <?php foreach($tasasVenta as $codigo=>$tasa): ?>

                        <?php

                        if($codigo===$baseCur['codigo'] || $tasa<=0) {
                            continue;
                        }

                        $monedaInfo=one("SELECT simbolo FROM monedas WHERE codigo=?",[$codigo]);
                        $simboloConv=$monedaInfo['simbolo']??($codigo.' ');
                        $convertido=$v['total']/$tasa;

                        ?>

                        <p class="muted" style="margin:2px 0;">
                            ≈ <?=money($convertido,$simboloConv)?> <?=e($codigo)?>
                        </p>

                    <?php endforeach; ?>

                </div>

            <?php endif; ?>

            <?php if($v['estado']==='COMPLETADA'):?>

            <div class="invoice-actions no-print">

                <button
                    type="button"
                    class="btn"
                    onclick="window.print()"
                >
                    🖶 Imprimir
                </button>

                <div style="display:flex;gap:10px;flex-wrap:wrap;">

                    <button
                        type="button"
                        class="btn"
                        id="toggleEditItemsBtn"
                    >
                        ✎ Editar productos
                    </button>

                    <form method="post" action="actions.php" onsubmit="return confirm('¿Anular venta y devolver stock?')">
                        <input type="hidden" name="csrf" value="<?=e(csrf())?>">
                        <input type="hidden" name="action" value="cancel_sale">
                        <input type="hidden" name="return_page" value="invoices">
                        <input type="hidden" name="id" value="<?=$id?>">
                        <button class="btn danger">Anular factura</button>
                    </form>

                </div>

            </div>


            <div id="editItemsPanel" class="no-print" style="display:none;margin-top:18px;padding-top:18px;border-top:1px solid #e8edf3;">

                <h3>Editar productos de la factura</h3>

                <p class="muted">
                    Cambia productos, cantidades o precios. El stock se
                    recalcula automáticamente al guardar (se revierte lo
                    anterior y se descuenta lo nuevo). Esto no modifica
                    los pagos ya registrados: si el total cambia, revisa
                    que sigan cuadrando.
                </p>

                <form
                    id="saleForm"
                    method="post"
                    action="actions.php"
                >

                    <input type="hidden" name="csrf" value="<?=e(csrf())?>">
                    <input type="hidden" name="action" value="invoice_items_save">
                    <input type="hidden" name="return_page" value="invoices">
                    <input type="hidden" name="id" value="<?=$id?>">


                    <div class="form-grid">

                        <label>
                            Descuento

                            <input
                                id="saleDiscount"
                                name="descuento"
                                type="number"
                                step="0.01"
                                min="0"
                                value="<?=e($v['descuento'])?>"
                                onchange="calcSale()"
                                oninput="calcSale()"
                            >

                        </label>


                        <label>
                            Impuesto

                            <input
                                id="saleTax"
                                name="impuesto"
                                type="number"
                                step="0.01"
                                min="0"
                                value="<?=e($v['impuesto'])?>"
                                onchange="calcSale()"
                                oninput="calcSale()"
                            >

                        </label>

                    </div>


                    <table id="saleTable">

                        <thead>

                            <tr>
                                <th>Producto</th>
                                <th>Stock</th>
                                <th>Precio</th>
                                <th>Cantidad</th>
                                <th>Total</th>
                                <th></th>
                            </tr>

                        </thead>


                        <tbody>

                            <?php foreach($items as $i): ?>

                                <?php
                                    $currentStock = one(
                                        "SELECT stock_actual FROM productos WHERE id_producto=?",
                                        [$i['id_producto']]
                                    );
                                    $stockVal = $currentStock ? (float)$currentStock['stock_actual'] : 0;
                                ?>

                                <tr>

                                    <td class="product-cell">

                                        <input
                                            type="hidden"
                                            name="product_id[]"
                                            class="product-id"
                                            value="<?=e($i['id_producto'])?>"
                                        >

                                        <button
                                            type="button"
                                            class="select-product-btn has-product"
                                        >

                                            <span class="selected-product">

                                                <strong>
                                                    <?=e($i['nombre'])?>
                                                </strong>

                                            </span>

                                            <span class="selected-product-arrow">
                                                ›
                                            </span>

                                        </button>

                                    </td>


                                    <td class="stock">
                                        <?=e($stockVal)?>
                                    </td>


                                    <td>

                                        <input
                                            name="price[]"
                                            class="price"
                                            type="number"
                                            step="0.01"
                                            min="0"
                                            value="<?=e($i['precio_unitario'])?>"
                                            onchange="calcSale()"
                                            oninput="calcSale()"
                                        >

                                    </td>


                                    <td>

                                        <input
                                            name="quantity[]"
                                            class="qty"
                                            type="number"
                                            min="0.001"
                                            step="0.001"
                                            value="<?=e($i['cantidad'])?>"
                                            onchange="calcSale()"
                                            oninput="calcSale()"
                                        >

                                    </td>


                                    <td class="line">
                                        <?=money($i['subtotal'],$v['simbolo'])?>
                                    </td>


                                    <td>

                                        <button
                                            type="button"
                                            class="btn sm danger remove-sale"
                                            title="Eliminar producto"
                                        >
                                            ×
                                        </button>

                                    </td>

                                </tr>

                            <?php endforeach; ?>

                        </tbody>

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
                            <b id="saleSubtotal"><?=money($v['subtotal'],$v['simbolo'])?></b>
                        </span>

                        <span>
                            Total
                            <b id="saleTotal"><?=money($v['total'],$v['simbolo'])?></b>
                        </span>

                    </div>


                    <button
                        type="submit"
                        class="btn primary"
                    >
                        Guardar productos de la factura
                    </button>

                </form>

            </div>

            <?php endif;?>

        </div>

    </div>

</div>

<script>
document.addEventListener('DOMContentLoaded', function(){

    const toggleBtn = document.getElementById('toggleEditItemsBtn');
    const panel = document.getElementById('editItemsPanel');

    if(toggleBtn && panel){

        toggleBtn.addEventListener('click', function(){

            const isHidden = panel.style.display === 'none';

            panel.style.display = isHidden ? 'block' : 'none';

            toggleBtn.textContent = isHidden
                ? '✕ Cerrar edición de productos'
                : '✎ Editar productos';

            if(isHidden && typeof calcSale === 'function'){
                calcSale();
            }

        });

    }

    document.body.style.overflow = 'hidden';

});
</script>

<?php
    endif;
}
?>
<!-- =========================================================
     MODAL DE EDICIÓN DE FACTURA (encabezado)
     ========================================================= -->

<div
    id="invoiceEditModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="invoiceEditTitle"
    >

        <div class="edit-modal-header">

            <h2 id="invoiceEditTitle">
                Editar factura
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeInvoiceEditModal"
                aria-label="Cerrar"
            >
                &times;
            </button>

        </div>


        <form
            class="form-grid edit-modal-body"
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
                value="invoice_save"
            >

            <input
                type="hidden"
                name="return_page"
                value="invoices"
            >

            <input
                type="hidden"
                name="id"
                id="editInvoiceId"
            >


            <label>
                Número de factura

                <input
                    name="numero_factura"
                    id="editInvoiceNumero"
                    required
                >

            </label>


            <label>
                Cliente

                <select
                    name="cliente"
                    id="editInvoiceCliente"
                >

                    <option value="0">
                        Consumidor final
                    </option>

                    <?php foreach($clientsList as $c): ?>

                        <option value="<?=$c['id_cliente']?>">
                            <?=e($c['nombre'])?>
                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Fecha

                <input
                    type="date"
                    name="fecha"
                    id="editInvoiceFecha"
                    required
                >

            </label>


            <label style="grid-column: 1 / -1;">
                Observaciones

                <input
                    name="observaciones"
                    id="editInvoiceObservaciones"
                >

            </label>


            <p class="muted" style="grid-column: 1 / -1; margin: 0;">
                Los productos, cantidades, montos y pagos de la
                factura no se pueden editar aquí para no descuadrar
                el inventario. Si necesitas corregir eso, anula la
                factura y registra la venta de nuevo.
            </p>


            <div class="edit-modal-footer">

                <button
                    type="button"
                    class="btn"
                    id="cancelInvoiceEdit"
                >
                    Cancelar
                </button>

                <button
                    class="btn primary"
                    type="submit"
                >
                    Guardar cambios
                </button>

            </div>

        </form>

    </div>

</div>



<!-- =========================================================
     JAVASCRIPT DEL MODAL DE EDICIÓN
     ========================================================= -->

<script>

document.addEventListener(
    'DOMContentLoaded',
    function(){

        const modal =
            document.getElementById('invoiceEditModal');

        const closeButton =
            document.getElementById('closeInvoiceEditModal');

        const cancelButton =
            document.getElementById('cancelInvoiceEdit');


        function openModal(row){

            document.getElementById('editInvoiceId').value =
                row.dataset.id;

            document.getElementById('editInvoiceNumero').value =
                row.dataset.numero;

            document.getElementById('editInvoiceCliente').value =
                row.dataset.cliente || '0';

            document.getElementById('editInvoiceFecha').value =
                row.dataset.fecha;

            document.getElementById('editInvoiceObservaciones').value =
                row.dataset.observaciones;

            modal.classList.add('show');
            modal.setAttribute('aria-hidden','false');
            document.body.style.overflow='hidden';

        }


        function closeModal(){

            modal.classList.remove('show');
            modal.setAttribute('aria-hidden','true');
            document.body.style.overflow='';

        }


        document.querySelectorAll('tr.clickable-row').forEach(
            function(row){

                row.addEventListener('click', function(e){

                    if(e.target.closest('button, a, form, input, select')){
                        return;
                    }

                    openModal(row);

                });

            }
        );


        closeButton.addEventListener('click', closeModal);
        cancelButton.addEventListener('click', closeModal);


        modal.addEventListener('click', function(e){

            if(e.target === modal){
                closeModal();
            }

        });


        document.addEventListener('keydown', function(e){

            if(e.key === 'Escape' && modal.classList.contains('show')){
                closeModal();
            }

        });

    }
);

</script>