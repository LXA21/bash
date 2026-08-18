<?php

$cur = allrows("
    SELECT *
    FROM monedas
    WHERE activo=1
    ORDER BY codigo
");

$methods = allrows("
    SELECT
        mp.*,
        m.codigo moneda
    FROM metodos_pago mp
    JOIN monedas m
        ON m.id_moneda=mp.id_moneda
    WHERE mp.activo=1
    ORDER BY mp.id_metodo_pago DESC
");

?>

<div class="grid2">

    <section class="panel">

        <h2>Agregar moneda</h2>

        <form method="post" action="actions.php">
            <input type="hidden" name="csrf" value="<?=e(csrf())?>">
            <input type="hidden" name="action" value="currency_save">
            <input type="hidden" name="return_page" value="payments">

            <label>
                Código
                <input name="codigo" maxlength="3" placeholder="COP" required>
            </label>

            <label>
                Nombre
                <input name="nombre" required>
            </label>

            <label>
                Símbolo
                <input name="simbolo" value="$" required>
            </label>

            <label>
                ¿Cuánto vale 1 dólar hoy en esta moneda?
                <input type="number" name="tasa" step="0.000001" placeholder="4000" required>
            </label>

            <button class="btn primary">Agregar moneda</button>
        </form>

    </section>


    <section class="panel">

        <h2>Agregar método de pago</h2>

        <form method="post" action="actions.php">
            <input type="hidden" name="csrf" value="<?=e(csrf())?>">
            <input type="hidden" name="action" value="payment_save">
            <input type="hidden" name="return_page" value="payments">

            <label>
                Nombre
                <input name="nombre" placeholder="Transferencia" required>
            </label>

            <label>
                Moneda
                <select name="moneda">
                    <?php foreach($cur as $c): ?>
                        <option value="<?=$c['id_moneda']?>">
                            <?=e($c['codigo'].' - '.$c['nombre'])?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </label>

            <button class="btn primary">Agregar método</button>
        </form>

    </section>

</div>


<!-- =========================================================
     TASA DE CAMBIO DEL DÍA
     ========================================================= -->

<section class="panel">

    <div class="panel-head">

        <div>

            <h2>Monedas y tasa de cambio del día</h2>

            <p class="panel-description">
                Escribe cuántas unidades de cada moneda equivalen a
                1 dólar hoy. Ejemplo: si el dólar está en 4,000 pesos,
                escribe <b>4000</b>. Se aplica automáticamente en
                Ventas, Compras y Facturas.
            </p>

        </div>

    </div>


    <div class="currency-grid">

        <?php foreach($cur as $c): ?>

            <div class="currency-card <?=($c['es_moneda_base'] ? 'is-base' : '')?>">

                <div class="currency-card-head">

                    <div class="currency-badge">
                        <?=e($c['codigo'])?>
                    </div>

                    <div class="currency-name">
                        <b><?=e($c['nombre'])?></b>
                        <span><?=e($c['simbolo'])?> · símbolo</span>
                    </div>

                </div>


                <?php if($c['es_moneda_base']): ?>

                    <span class="currency-base-tag">
                        ★ Moneda base — 1 USD = 1 USD
                    </span>

                <?php else: ?>

                    <?php

                    $valorActual=$c['tasa_referencia']>0
                        ? rtrim(rtrim(number_format(1/$c['tasa_referencia'],6,'.',''),'0'),'.')
                        : 0;

                    ?>

                    <form
                        class="currency-card-form"
                        method="post"
                        action="actions.php"
                    >

                        <input type="hidden" name="csrf" value="<?=e(csrf())?>">
                        <input type="hidden" name="action" value="currency_update_rate">
                        <input type="hidden" name="return_page" value="payments">
                        <input type="hidden" name="id" value="<?=$c['id_moneda']?>">

                        <label>
                            1 USD equivale a
                        </label>

                        <div class="currency-input-row">

                            <input
                                type="number"
                                name="tasa"
                                step="0.000001"
                                min="0.000001"
                                value="<?=e($valorActual)?>"
                                required
                            >

                            <button class="btn sm primary" type="submit">
                                Guardar
                            </button>

                        </div>

                    </form>


                    <button
                        type="button"
                        class="btn sm danger js-delete-trigger"
                        style="margin-top:10px;width:100%;"
                        data-action="currency_delete"
                        data-id="<?=$c['id_moneda']?>"
                        data-label="<?=e($c['codigo'].' - '.$c['nombre'])?>"
                    >
                        Eliminar moneda
                    </button>

                <?php endif; ?>

            </div>

        <?php endforeach; ?>

    </div>

</section>


<section class="panel">

    <h2>Métodos de pago</h2>

    <table>
        <tr>
            <th>Método</th>
            <th>Moneda</th>
            <th></th>
        </tr>

        <?php if(empty($methods)): ?>
            <tr>
                <td colspan="3" style="text-align:center;padding:20px;">
                    No tienes métodos de pago registrados.
                </td>
            </tr>
        <?php endif; ?>

        <?php foreach($methods as $m): ?>
            <tr>
                <td><?=e($m['nombre'])?></td>
                <td><?=e($m['moneda'])?></td>
                <td>

                    <button
                        type="button"
                        class="btn sm danger js-delete-trigger"
                        data-action="payment_delete"
                        data-id="<?=$m['id_metodo_pago']?>"
                        data-label="<?=e($m['nombre'])?>"
                    >
                        Eliminar
                    </button>

                </td>
            </tr>
        <?php endforeach; ?>
    </table>

</section>


<!-- =========================================================
     MODAL DE CONFIRMACIÓN DE ELIMINACIÓN
     ========================================================= -->

<div
    id="deleteConfirmModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        style="max-width:420px;"
        role="dialog"
        aria-modal="true"
        aria-labelledby="deleteConfirmTitle"
    >

        <div class="edit-modal-header">

            <h2 id="deleteConfirmTitle">
                Eliminar
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeDeleteModal"
                aria-label="Cerrar"
            >
                &times;
            </button>

        </div>


        <div class="edit-modal-body">

            <p id="deleteConfirmText">
                ¿Seguro que deseas eliminar este elemento?
            </p>

            <form
                method="post"
                action="actions.php"
                id="deleteConfirmForm"
            >

                <input type="hidden" name="csrf" value="<?=e(csrf())?>">
                <input type="hidden" name="action" id="deleteConfirmAction" value="">
                <input type="hidden" name="return_page" value="payments">
                <input type="hidden" name="id" id="deleteConfirmId" value="">

                <div class="edit-modal-footer">

                    <button
                        type="button"
                        class="btn"
                        id="cancelDeleteModal"
                    >
                        Cancelar
                    </button>

                    <button
                        class="btn danger"
                        type="submit"
                    >
                        Sí, eliminar
                    </button>

                </div>

            </form>

        </div>

    </div>

</div>


<script>

document.addEventListener('DOMContentLoaded', function(){

    const modal = document.getElementById('deleteConfirmModal');
    const closeBtn = document.getElementById('closeDeleteModal');
    const cancelBtn = document.getElementById('cancelDeleteModal');
    const titleEl = document.getElementById('deleteConfirmTitle');
    const textEl = document.getElementById('deleteConfirmText');
    const actionInput = document.getElementById('deleteConfirmAction');
    const idInput = document.getElementById('deleteConfirmId');


    function openDeleteModal(action, id, label){

        actionInput.value = action;
        idInput.value = id;

        titleEl.textContent = 'Eliminar "' + label + '"';

        textEl.textContent =
            '¿Seguro que deseas eliminar "' + label + '"? ' +
            'Esta acción no se puede deshacer y dejará de ' +
            'aparecer en el sistema, incluyendo las conversiones ' +
            'de moneda mostradas en productos.';

        modal.classList.add('show');
        modal.setAttribute('aria-hidden', 'false');

    }


    function closeDeleteModal(){

        modal.classList.remove('show');
        modal.setAttribute('aria-hidden', 'true');

    }


    document.querySelectorAll('.js-delete-trigger').forEach(function(btn){

        btn.addEventListener('click', function(){

            openDeleteModal(
                btn.dataset.action,
                btn.dataset.id,
                btn.dataset.label
            );

        });

    });


    closeBtn.addEventListener('click', closeDeleteModal);
    cancelBtn.addEventListener('click', closeDeleteModal);


    modal.addEventListener('click', function(e){

        if(e.target === modal){
            closeDeleteModal();
        }

    });


    document.addEventListener('keydown', function(e){

        if(e.key === 'Escape' && modal.classList.contains('show')){
            closeDeleteModal();
        }

    });

});

</script>