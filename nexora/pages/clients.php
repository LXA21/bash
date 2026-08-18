<?php

$rows = allrows("
    SELECT
        id_cliente,
        nombre,
        documento,
        telefono,
        correo,
        direccion
    FROM clientes
    WHERE activo = 1
    ORDER BY id_cliente DESC
");

?>


<!-- =========================================================
     NUEVO CLIENTE
     ========================================================= -->

<section class="panel">

    <div class="panel-head">

        <h2>Nuevo cliente</h2>

    </div>


    <form
        class="form-grid"
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
            value="client_save"
        >


        <input
            type="hidden"
            name="return_page"
            value="clients"
        >


        <label>

            Nombre

            <input
                name="nombre"
                required
            >

        </label>


        <label>

            Documento

            <input
                name="documento"
            >

        </label>


        <label>

            Teléfono

            <input
                name="telefono"
            >

        </label>


        <label>

            Correo

            <input
                type="email"
                name="correo"
            >

        </label>


        <label>

            Dirección

            <input
                name="direccion"
            >

        </label>


        <div>

            <button
                class="btn primary"
                type="submit"
            >
                Guardar
            </button>

        </div>

    </form>

</section>



<!-- =========================================================
     LISTADO DE CLIENTES
     ========================================================= -->

<section class="panel">

    <div class="client-list-head">

        <div>

            <h2>
                Clientes
            </h2>

            <p class="muted">
                Haz clic en un cliente para editarlo, o selecciona
                varios para eliminarlos.
            </p>

        </div>


        <!-- BOTÓN ELIMINAR -->

        <button
            type="button"
            class="btn danger client-delete-button"
            id="openClientDeleteModal"
            disabled
        >
            🗑️ Eliminar seleccionados
        </button>

    </div>



    <!-- =====================================================
         FORMULARIO PARA SELECCIONAR CLIENTES
         ===================================================== -->

    <form
        method="post"
        action="actions.php"
        id="clientDeleteForm"
    >

        <input
            type="hidden"
            name="csrf"
            value="<?=e(csrf())?>"
        >


        <input
            type="hidden"
            name="action"
            value="client_delete_multiple"
        >


        <input
            type="hidden"
            name="return_page"
            value="clients"
        >


        <div class="client-table-wrapper">

            <table>

                <thead>

                    <tr>

                        <!-- SELECCIONAR TODOS -->

                        <th
                            class="client-check-column"
                        >

                            <input
                                type="checkbox"
                                id="selectAllClients"
                                title="Seleccionar todos"
                            >

                        </th>


                        <th>
                            Nombre
                        </th>


                        <th>
                            Documento
                        </th>


                        <th>
                            Teléfono
                        </th>


                        <th>
                            Correo
                        </th>

                    </tr>

                </thead>


                <tbody>


                    <?php if(empty($rows)): ?>

                        <tr>

                            <td
                                colspan="5"
                                class="client-empty"
                            >

                                No hay clientes registrados.

                            </td>

                        </tr>


                    <?php else: ?>


                        <?php foreach($rows as $r): ?>

                            <tr
                                class="clickable-row"
                                data-id="<?=e($r['id_cliente'])?>"
                                data-nombre="<?=e($r['nombre'])?>"
                                data-documento="<?=e($r['documento'])?>"
                                data-telefono="<?=e($r['telefono'])?>"
                                data-correo="<?=e($r['correo'])?>"
                                data-direccion="<?=e($r['direccion'])?>"
                                title="Clic para editar"
                            >


                                <!-- CHECKBOX -->

                                <td
                                    class="client-check-column"
                                >

                                    <input
                                        type="checkbox"
                                        class="client-checkbox"
                                        name="clientes[]"
                                        value="<?=e($r['id_cliente'])?>"
                                    >

                                </td>


                                <!-- NOMBRE -->

                                <td>

                                    <strong>
                                        <?=e($r['nombre'])?>
                                    </strong>

                                </td>


                                <!-- DOCUMENTO -->

                                <td>
                                    <?=e($r['documento'])?>
                                </td>


                                <!-- TELÉFONO -->

                                <td>
                                    <?=e($r['telefono'])?>
                                </td>


                                <!-- CORREO -->

                                <td>
                                    <?=e($r['correo'])?>
                                </td>


                            </tr>

                        <?php endforeach; ?>


                    <?php endif; ?>


                </tbody>

            </table>

        </div>

    </form>

</section>



<!-- =========================================================
     MODAL DE EDICIÓN DE CLIENTE
     ========================================================= -->

<div
    id="clientEditModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="clientEditTitle"
    >

        <div class="edit-modal-header">

            <h2 id="clientEditTitle">
                Editar cliente
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeClientEditModal"
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
                value="client_save"
            >

            <input
                type="hidden"
                name="return_page"
                value="clients"
            >

            <input
                type="hidden"
                name="id"
                id="editClientId"
            >


            <label>
                Nombre

                <input
                    name="nombre"
                    id="editClientNombre"
                    required
                >

            </label>


            <label>
                Documento

                <input
                    name="documento"
                    id="editClientDocumento"
                >

            </label>


            <label>
                Teléfono

                <input
                    name="telefono"
                    id="editClientTelefono"
                >

            </label>


            <label>
                Correo

                <input
                    type="email"
                    name="correo"
                    id="editClientCorreo"
                >

            </label>


            <label>
                Dirección

                <input
                    name="direccion"
                    id="editClientDireccion"
                >

            </label>


            <div class="edit-modal-footer">

                <button
                    type="button"
                    class="btn"
                    id="cancelClientEdit"
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
     MODAL DE CONFIRMACIÓN DE ELIMINACIÓN
     ========================================================= -->

<div
    id="clientDeleteModal"
    class="client-modal"
    aria-hidden="true"
>

    <div
        class="client-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="clientDeleteTitle"
    >


        <!-- CABECERA -->

        <div class="client-modal-header">

            <h2 id="clientDeleteTitle">
                Confirmar eliminación
            </h2>


            <button
                type="button"
                class="client-modal-close"
                id="closeClientDeleteModal"
                aria-label="Cerrar"
            >
                &times;
            </button>

        </div>



        <!-- CONTENIDO -->

        <div class="client-modal-body">


            <div class="client-delete-icon">
                🗑️
            </div>


            <h3>
                ¿Deseas eliminar los clientes seleccionados?
            </h3>


            <p>

                Has seleccionado

                <strong
                    id="selectedClientCount"
                >
                    0
                </strong>

                cliente(s).

            </p>


            <p class="muted">

                Los clientes serán desactivados y dejarán
                de aparecer en el listado. Las ventas
                históricas conservarán sus datos.

            </p>

        </div>



        <!-- BOTONES -->

        <div class="client-modal-footer">


            <button
                type="button"
                class="btn"
                id="cancelClientDelete"
            >
                Cancelar
            </button>


            <button
                type="button"
                class="btn client-confirm-delete"
                id="confirmClientDelete"
            >
                🗑️ Sí, eliminar
            </button>


        </div>

    </div>

</div>



<!-- =========================================================
     JAVASCRIPT
     ========================================================= -->

<script>

document.addEventListener(
    'DOMContentLoaded',
    function(){

        /*
         * =====================================================
         * EDICIÓN DE CLIENTE (clic en la fila)
         * =====================================================
         */

        const editModal =
            document.getElementById('clientEditModal');

        const closeEditButton =
            document.getElementById('closeClientEditModal');

        const cancelEditButton =
            document.getElementById('cancelClientEdit');


        function openEditModal(row){

            document.getElementById('editClientId').value =
                row.dataset.id;

            document.getElementById('editClientNombre').value =
                row.dataset.nombre;

            document.getElementById('editClientDocumento').value =
                row.dataset.documento;

            document.getElementById('editClientTelefono').value =
                row.dataset.telefono;

            document.getElementById('editClientCorreo').value =
                row.dataset.correo;

            document.getElementById('editClientDireccion').value =
                row.dataset.direccion;

            editModal.classList.add('show');
            editModal.setAttribute('aria-hidden','false');
            document.body.style.overflow='hidden';

        }


        function closeEditModal(){

            editModal.classList.remove('show');
            editModal.setAttribute('aria-hidden','true');
            document.body.style.overflow='';

        }


        document.querySelectorAll('tr.clickable-row').forEach(
            function(row){

                row.addEventListener('click', function(e){

                    if(e.target.closest('button, a, form, input, select')){
                        return;
                    }

                    openEditModal(row);

                });

            }
        );


        closeEditButton.addEventListener('click', closeEditModal);
        cancelEditButton.addEventListener('click', closeEditModal);


        editModal.addEventListener('click', function(e){

            if(e.target === editModal){
                closeEditModal();
            }

        });


        /*
         * =====================================================
         * ELIMINACIÓN MÚLTIPLE (checkboxes)
         * =====================================================
         */

        const selectAll =
            document.getElementById(
                'selectAllClients'
            );


        const checkboxes =
            document.querySelectorAll(
                '.client-checkbox'
            );


        const deleteButton =
            document.getElementById(
                'openClientDeleteModal'
            );


        const modal =
            document.getElementById(
                'clientDeleteModal'
            );


        const closeButton =
            document.getElementById(
                'closeClientDeleteModal'
            );


        const cancelButton =
            document.getElementById(
                'cancelClientDelete'
            );


        const confirmButton =
            document.getElementById(
                'confirmClientDelete'
            );


        const deleteForm =
            document.getElementById(
                'clientDeleteForm'
            );


        const selectedCount =
            document.getElementById(
                'selectedClientCount'
            );


        /*
         * Evitar que el clic en el checkbox
         * también dispare la apertura del modal
         * de edición (ya se filtra arriba, pero
         * detenemos la propagación por seguridad).
         */

        checkboxes.forEach(function(checkbox){

            checkbox.addEventListener('click', function(e){
                e.stopPropagation();
            });

        });


        function updateClientSelection(){

            const selected =
                document.querySelectorAll(
                    '.client-checkbox:checked'
                );


            const total =
                checkboxes.length;


            const count =
                selected.length;


            selectedCount.textContent =
                count;


            deleteButton.disabled =
                count === 0;


            if(total === 0){

                selectAll.checked = false;
                selectAll.indeterminate = false;

            }

            else if(count === total){

                selectAll.checked = true;
                selectAll.indeterminate = false;

            }

            else if(count > 0){

                selectAll.checked = false;
                selectAll.indeterminate = true;

            }

            else{

                selectAll.checked = false;
                selectAll.indeterminate = false;

            }

        }


        if(selectAll){

            selectAll.addEventListener(
                'change',
                function(){

                    checkboxes.forEach(
                        function(checkbox){

                            checkbox.checked =
                                selectAll.checked;

                        }
                    );


                    updateClientSelection();

                }
            );

        }


        checkboxes.forEach(
            function(checkbox){

                checkbox.addEventListener(
                    'change',
                    updateClientSelection
                );

            }
        );


        function openModal(){

            const selected =
                document.querySelectorAll(
                    '.client-checkbox:checked'
                );


            if(selected.length === 0){
                return;
            }


            selectedCount.textContent =
                selected.length;


            modal.classList.add('show');

            modal.setAttribute(
                'aria-hidden',
                'false'
            );


            document.body.style.overflow =
                'hidden';

        }


        function closeModal(){

            modal.classList.remove('show');

            modal.setAttribute(
                'aria-hidden',
                'true'
            );


            document.body.style.overflow =
                '';

        }


        deleteButton.addEventListener(
            'click',
            openModal
        );


        closeButton.addEventListener(
            'click',
            closeModal
        );


        cancelButton.addEventListener(
            'click',
            closeModal
        );


        modal.addEventListener(
            'click',
            function(event){

                if(event.target === modal){
                    closeModal();
                }

            }
        );


        document.addEventListener(
            'keydown',
            function(event){

                if(
                    event.key === 'Escape'
                ){

                    if(modal.classList.contains('show')){
                        closeModal();
                    }

                    if(editModal.classList.contains('show')){
                        closeEditModal();
                    }

                }

            }
        );


        confirmButton.addEventListener(
            'click',
            function(){

                const selected =
                    document.querySelectorAll(
                        '.client-checkbox:checked'
                    );


                if(selected.length === 0){

                    closeModal();
                    return;

                }


                confirmButton.disabled =
                    true;


                confirmButton.textContent =
                    'Eliminando...';


                deleteForm.submit();

            }
        );


        updateClientSelection();

    }
);

</script>