<?php

$rows = allrows("
    SELECT *
    FROM proveedores
    WHERE activo = 1
    ORDER BY id_proveedor DESC
");

?>

<!-- =========================================================
     NUEVO PROVEEDOR
     ========================================================= -->

<section class="panel">

    <div class="panel-head">

        <h2>Nuevo proveedor</h2>

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
            value="supplier_save"
        >

        <input
            type="hidden"
            name="return_page"
            value="suppliers"
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
            Email

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
                type="submit"
                class="btn primary"
            >
                Guardar proveedor
            </button>

        </div>

    </form>

</section>


<!-- =========================================================
     LISTADO DE PROVEEDORES
     ========================================================= -->

<section class="panel">

    <div
        class="supplier-list-head"
    >

        <div>

            <h2>
                Proveedores
            </h2>

            <p class="muted">
                Haz clic en un proveedor para editarlo, o selecciona
                varios para eliminarlos.
            </p>

        </div>


        <!-- BOTÓN ELIMINAR -->

        <button
            type="button"
            class="btn danger supplier-delete-button"
            id="openSupplierDeleteModal"
            disabled
        >
            🗑️ Eliminar seleccionados
        </button>

    </div>


    <!-- =====================================================
         FORMULARIO DE SELECCIÓN
         ===================================================== -->

    <form
        method="post"
        action="actions.php"
        id="supplierDeleteForm"
    >

        <input
            type="hidden"
            name="csrf"
            value="<?=e(csrf())?>"
        >

        <input
            type="hidden"
            name="action"
            value="supplier_delete_multiple"
        >

        <input
            type="hidden"
            name="return_page"
            value="suppliers"
        >


        <div
            class="supplier-table-wrapper"
        >

            <table>

                <thead>

                    <tr>

                        <!-- SELECCIONAR TODOS -->

                        <th
                            class="supplier-check-column"
                        >

                            <input
                                type="checkbox"
                                id="selectAllSuppliers"
                                title="Seleccionar todos"
                            >

                        </th>


                        <th>
                            Proveedor
                        </th>


                        <th>
                            Documento
                        </th>


                        <th>
                            Teléfono
                        </th>


                        <th>
                            Email
                        </th>

                    </tr>

                </thead>


                <tbody>

                    <?php if(empty($rows)): ?>

                        <tr>

                            <td
                                colspan="5"
                                class="supplier-empty"
                            >

                                No hay proveedores registrados.

                            </td>

                        </tr>

                    <?php else: ?>


                        <?php foreach($rows as $r): ?>

                            <tr
                                class="clickable-row"
                                data-id="<?=e($r['id_proveedor'])?>"
                                data-nombre="<?=e($r['nombre'])?>"
                                data-documento="<?=e($r['documento'])?>"
                                data-telefono="<?=e($r['telefono'])?>"
                                data-correo="<?=e($r['correo'])?>"
                                data-direccion="<?=e($r['direccion'])?>"
                                title="Clic para editar"
                            >

                                <!-- CHECKBOX DEL PROVEEDOR -->

                                <td
                                    class="supplier-check-column"
                                >

                                    <input
                                        type="checkbox"
                                        class="supplier-checkbox"
                                        name="proveedores[]"
                                        value="<?=e($r['id_proveedor'])?>"
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


                                <!-- EMAIL -->

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
     MODAL DE EDICIÓN DE PROVEEDOR
     ========================================================= -->

<div
    id="supplierEditModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="supplierEditTitle"
    >

        <div class="edit-modal-header">

            <h2 id="supplierEditTitle">
                Editar proveedor
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeSupplierEditModal"
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
                value="supplier_save"
            >

            <input
                type="hidden"
                name="return_page"
                value="suppliers"
            >

            <input
                type="hidden"
                name="id"
                id="editSupplierId"
            >


            <label>
                Nombre

                <input
                    name="nombre"
                    id="editSupplierNombre"
                    required
                >

            </label>


            <label>
                Documento

                <input
                    name="documento"
                    id="editSupplierDocumento"
                >

            </label>


            <label>
                Teléfono

                <input
                    name="telefono"
                    id="editSupplierTelefono"
                >

            </label>


            <label>
                Email

                <input
                    type="email"
                    name="correo"
                    id="editSupplierCorreo"
                >

            </label>


            <label>
                Dirección

                <input
                    name="direccion"
                    id="editSupplierDireccion"
                >

            </label>


            <div class="edit-modal-footer">

                <button
                    type="button"
                    class="btn"
                    id="cancelSupplierEdit"
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
     MODAL PARA CONFIRMAR ELIMINACIÓN
     ========================================================= -->

<div
    id="supplierDeleteModal"
    class="supplier-modal"
    aria-hidden="true"
>

    <div
        class="supplier-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="supplierDeleteTitle"
    >

        <div class="supplier-modal-header">

            <h2 id="supplierDeleteTitle">
                Confirmar eliminación
            </h2>


            <button
                type="button"
                class="supplier-modal-close"
                id="closeSupplierDeleteModal"
                aria-label="Cerrar"
            >
                &times;
            </button>

        </div>


        <div class="supplier-modal-body">

            <div class="supplier-delete-icon">
                🗑️
            </div>


            <h3>
                ¿Deseas eliminar los proveedores seleccionados?
            </h3>


            <p>

                Has seleccionado

                <strong
                    id="selectedSupplierCount"
                >
                    0
                </strong>

                proveedor(es).

            </p>


            <p class="muted">

                Los proveedores serán desactivados y dejarán de
                aparecer en el listado. Las compras existentes
                conservarán sus datos.

            </p>

        </div>


        <div class="supplier-modal-footer">

            <button
                type="button"
                class="btn"
                id="cancelSupplierDelete"
            >
                Cancelar
            </button>


            <button
                type="button"
                class="btn danger supplier-confirm-delete"
                id="confirmSupplierDelete"
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
         * EDICIÓN DE PROVEEDOR (clic en la fila)
         * =====================================================
         */

        const editModal =
            document.getElementById('supplierEditModal');

        const closeEditButton =
            document.getElementById('closeSupplierEditModal');

        const cancelEditButton =
            document.getElementById('cancelSupplierEdit');


        function openEditModal(row){

            document.getElementById('editSupplierId').value =
                row.dataset.id;

            document.getElementById('editSupplierNombre').value =
                row.dataset.nombre;

            document.getElementById('editSupplierDocumento').value =
                row.dataset.documento;

            document.getElementById('editSupplierTelefono').value =
                row.dataset.telefono;

            document.getElementById('editSupplierCorreo').value =
                row.dataset.correo;

            document.getElementById('editSupplierDireccion').value =
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
                'selectAllSuppliers'
            );


        const checkboxes =
            document.querySelectorAll(
                '.supplier-checkbox'
            );


        const deleteButton =
            document.getElementById(
                'openSupplierDeleteModal'
            );


        const modal =
            document.getElementById(
                'supplierDeleteModal'
            );


        const closeButton =
            document.getElementById(
                'closeSupplierDeleteModal'
            );


        const cancelButton =
            document.getElementById(
                'cancelSupplierDelete'
            );


        const confirmButton =
            document.getElementById(
                'confirmSupplierDelete'
            );


        const deleteForm =
            document.getElementById(
                'supplierDeleteForm'
            );


        const selectedCount =
            document.getElementById(
                'selectedSupplierCount'
            );


        checkboxes.forEach(function(checkbox){

            checkbox.addEventListener('click', function(e){
                e.stopPropagation();
            });

        });


        function updateSupplierSelection(){

            const selected =
                document.querySelectorAll(
                    '.supplier-checkbox:checked'
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


                    updateSupplierSelection();

                }
            );

        }


        checkboxes.forEach(
            function(checkbox){

                checkbox.addEventListener(
                    'change',
                    updateSupplierSelection
                );

            }
        );


        function openModal(){

            const selected =
                document.querySelectorAll(
                    '.supplier-checkbox:checked'
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

                if(event.key === 'Escape'){

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
                        '.supplier-checkbox:checked'
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


        updateSupplierSelection();

    }
);

</script>