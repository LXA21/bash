<?php

$cats=allrows("
    SELECT *
    FROM categorias
    WHERE activo=1
    ORDER BY nombre
");


$products=allrows("
    SELECT
        p.*,
        c.nombre AS categoria
    FROM productos p
    LEFT JOIN categorias c
        ON c.id_categoria=p.id_categoria
    WHERE p.activo=1
    ORDER BY p.id_producto DESC
");

?>

<section class="panel">

    <p class="panel-description">
        Catálogo, precios y existencias.
    </p>


    <form
        class="form-grid"
        method="post"
        action="actions.php"
        enctype="multipart/form-data"
    >

        <input
            type="hidden"
            name="csrf"
            value="<?=e(csrf())?>"
        >

        <input
            type="hidden"
            name="action"
            value="product_save"
        >

        <input
            type="hidden"
            name="return_page"
            value="products"
        >


        <label>
            Código

            <input
                name="codigo"
                required
            >

        </label>


        <label>
            Nombre

            <input
                name="nombre"
                required
            >

        </label>


        <label>
            Categoría

            <select
                name="categoria"
                required
            >

                <?php foreach($cats as $c): ?>

                    <option
                        value="<?=$c['id_categoria']?>"
                    >

                        <?=e($c['nombre'])?>

                    </option>

                <?php endforeach; ?>

            </select>

        </label>


        <label>
            Precio de venta

            <input
                type="number"
                step="0.01"
                min="0"
                name="precio_venta"
                required
            >

        </label>


        <label>
            Precio de compra

            <input
                type="number"
                step="0.01"
                min="0"
                name="precio_compra"
                required
            >

        </label>


        <label>
            Stock inicial

            <input
                type="number"
                step="1"
                min="0"
                name="stock"
                value="0"
            >

        </label>


        <label>
            Stock mínimo

            <input
                type="number"
                step="1"
                min="0"
                name="stock_minimo"
                value="1"
            >

        </label>


        <label>
            Imagen del producto

            <input
                type="file"
                name="imagen"
                accept="image/jpeg,image/png,image/webp,image/gif"
            >

            <small>
                JPG, PNG, WEBP o GIF. Máximo 5 MB.
            </small>

        </label>


        <div>

            <button
                class="btn primary"
                type="submit"
            >

                Guardar producto

            </button>

        </div>

    </form>

</section>



<section class="panel">

    <div class="panel-head">

        <div>

            <h2>
                Productos
            </h2>

            <p class="muted">
                Haz clic en un producto para editarlo.
            </p>

        </div>

    </div>


    <table>

        <thead>

            <tr>

                <th>
                    Imagen
                </th>

                <th>
                    Código
                </th>

                <th>
                    Producto
                </th>

                <th>
                    Categoría
                </th>

                <th>
                    Compra
                </th>

                <th>
                    Venta
                </th>

                <th>
                    Stock
                </th>

                <th>
                    Acción
                </th>

            </tr>

        </thead>


        <tbody>

        <?php foreach($products as $p): ?>

            <tr
                class="clickable-row"
                data-id="<?=e($p['id_producto'])?>"
                data-codigo="<?=e($p['codigo'])?>"
                data-nombre="<?=e($p['nombre'])?>"
                data-categoria="<?=e($p['id_categoria'])?>"
                data-precio-venta="<?=e($p['precio_venta'])?>"
                data-precio-compra="<?=e($p['precio_compra'])?>"
                data-stock="<?=e($p['stock_actual'])?>"
                data-stock-minimo="<?=e($p['stock_minimo'])?>"
                data-imagen="<?=e($p['imagen'])?>"
                title="Clic para editar"
            >


                <!-- IMAGEN DEL PRODUCTO -->

                <td>

                    <?php if(!empty($p['imagen'])): ?>

                        <img
                            src="<?=e($p['imagen'])?>"
                            alt="<?=e($p['nombre'])?>"
                            class="product-image-table"
                        >

                    <?php else: ?>

                        <div class="product-image-placeholder">
                            Sin imagen
                        </div>

                    <?php endif; ?>

                </td>


                <td>

                    <?=e($p['codigo'])?>

                </td>


                <td>

                    <?=e($p['nombre'])?>

                </td>


                <td>

                    <?=e($p['categoria'])?>

                </td>


                <td>

                    <?=money($p['costo_promedio'])?>

                </td>


                <td>

                    <?=money($p['precio_venta'])?>

                    <?php

                    $conversiones=allrows("
                        SELECT codigo, simbolo, tasa_referencia
                        FROM monedas
                        WHERE activo=1
                          AND es_moneda_base=0
                    ");

                    foreach($conversiones as $mc):

                        if($mc['tasa_referencia']<=0) {
                            continue;
                        }

                        $convertido=$p['precio_venta']/$mc['tasa_referencia'];

                    ?>

                        <br>

                        <small class="muted">
                            ≈ <?=money($convertido,$mc['simbolo'])?> <?=e($mc['codigo'])?>
                        </small>

                    <?php endforeach; ?>

                </td>


                <td
                    class="<?=(
                        $p['stock_actual'] <= $p['stock_minimo']
                        ? 'red'
                        : ''
                    )?>"
                >

                    <?=rtrim(
                        rtrim(
                            number_format(
                                (float)$p['stock_actual'],
                                3,
                                '.',
                                ''
                            ),
                            '0'
                        ),
                        '.'
                    )?>

                </td>


                <td>

                    <button
                        type="button"
                        class="btn sm edit-row-btn"
                    >
                        ✎ Editar
                    </button>

                    <form
                        method="post"
                        action="actions.php"
                        onsubmit="return confirm('¿Desactivar producto?')"
                        style="display:inline"
                    >

                        <input
                            type="hidden"
                            name="csrf"
                            value="<?=e(csrf())?>"
                        >

                        <input
                            type="hidden"
                            name="action"
                            value="product_delete"
                        >

                        <input
                            type="hidden"
                            name="return_page"
                            value="products"
                        >

                        <input
                            type="hidden"
                            name="id"
                            value="<?=$p['id_producto']?>"
                        >

                        <button
                            class="btn sm danger"
                            type="submit"
                        >

                            Desactivar

                        </button>

                    </form>

                </td>

            </tr>

        <?php endforeach; ?>

        </tbody>

    </table>

</section>



<!-- =========================================================
     MODAL DE EDICIÓN DE PRODUCTO
     ========================================================= -->

<div
    id="productEditModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="productEditTitle"
    >

        <div class="edit-modal-header">

            <h2 id="productEditTitle">
                Editar producto
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeProductEditModal"
                aria-label="Cerrar"
            >
                &times;
            </button>

        </div>


        <form
            class="form-grid edit-modal-body"
            method="post"
            action="actions.php"
            enctype="multipart/form-data"
        >

            <input
                type="hidden"
                name="csrf"
                value="<?=e(csrf())?>"
            >

            <input
                type="hidden"
                name="action"
                value="product_save"
            >

            <input
                type="hidden"
                name="return_page"
                value="products"
            >

            <input
                type="hidden"
                name="id"
                id="editProductId"
            >


            <label>
                Código

                <input
                    name="codigo"
                    id="editProductCodigo"
                    required
                >

            </label>


            <label>
                Nombre

                <input
                    name="nombre"
                    id="editProductNombre"
                    required
                >

            </label>


            <label>
                Categoría

                <select
                    name="categoria"
                    id="editProductCategoria"
                    required
                >

                    <?php foreach($cats as $c): ?>

                        <option
                            value="<?=$c['id_categoria']?>"
                        >

                            <?=e($c['nombre'])?>

                        </option>

                    <?php endforeach; ?>

                </select>

            </label>


            <label>
                Precio de venta

                <input
                    type="number"
                    step="0.01"
                    min="0"
                    name="precio_venta"
                    id="editProductPrecioVenta"
                    required
                >

            </label>


            <label>
                Precio de compra

                <input
                    type="number"
                    step="0.01"
                    min="0"
                    name="precio_compra"
                    id="editProductPrecioCompra"
                    required
                >

            </label>


            <label>
                Stock actual

                <input
                    type="number"
                    step="0.001"
                    min="0"
                    name="stock"
                    id="editProductStock"
                >

            </label>


            <label>
                Stock mínimo

                <input
                    type="number"
                    step="0.001"
                    min="0"
                    name="stock_minimo"
                    id="editProductStockMinimo"
                >

            </label>


            <label>
                Imagen del producto

                <input
                    type="file"
                    name="imagen"
                    accept="image/jpeg,image/png,image/webp,image/gif"
                >

                <small id="editProductImagenActual">
                    Deja este campo vacío para conservar la imagen actual.
                </small>

            </label>


            <div class="edit-modal-footer">

                <button
                    type="button"
                    class="btn"
                    id="cancelProductEdit"
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
            document.getElementById('productEditModal');

        const closeButton =
            document.getElementById('closeProductEditModal');

        const cancelButton =
            document.getElementById('cancelProductEdit');


        function openModal(row){

            document.getElementById('editProductId').value =
                row.dataset.id;

            document.getElementById('editProductCodigo').value =
                row.dataset.codigo;

            document.getElementById('editProductNombre').value =
                row.dataset.nombre;

            document.getElementById('editProductCategoria').value =
                row.dataset.categoria;

            document.getElementById('editProductPrecioVenta').value =
                row.dataset.precioVenta;

            document.getElementById('editProductPrecioCompra').value =
                row.dataset.precioCompra;

            document.getElementById('editProductStock').value =
    parseFloat(row.dataset.stock || 0);

document.getElementById('editProductStockMinimo').value =
    parseFloat(row.dataset.stockMinimo || 0);

            document.getElementById('editProductImagenActual').textContent =
                row.dataset.imagen
                    ? 'Imagen actual: '+row.dataset.imagen.split('/').pop()+'. Deja vacío para conservarla.'
                    : 'Este producto no tiene imagen. Puedes agregar una.';

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


                const editBtn =
                    row.querySelector('.edit-row-btn');

                if(editBtn){

                    editBtn.addEventListener('click', function(e){

                        e.stopPropagation();
                        openModal(row);

                    });

                }

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