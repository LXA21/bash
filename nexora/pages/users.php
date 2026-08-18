<?php

admin_only();

$roles=allrows("
    SELECT *
    FROM roles
    ORDER BY nombre
");

$users=allrows("
    SELECT
        u.*,
        r.nombre rol
    FROM usuarios u
    JOIN roles r
        ON r.id_rol=u.id_rol
    WHERE u.activo=1
    ORDER BY u.id_usuario DESC
");

?>


<section class="panel">

    <h2>Nuevo usuario</h2>

    <form
        class="form-grid"
        method="post"
        action="actions.php"
    >

        <input type="hidden" name="csrf" value="<?=e(csrf())?>">
        <input type="hidden" name="action" value="user_save">
        <input type="hidden" name="return_page" value="users">

        <label>
            Nombre
            <input name="nombre" required>
        </label>

        <label>
            Usuario
            <input name="usuario" required>
        </label>

        <label>
            Contraseña
            <input type="password" name="password" required>
        </label>

        <label>
            Rol
            <select name="rol">
                <?php foreach($roles as $r): ?>
                    <option value="<?=$r['id_rol']?>">
                        <?=e($r['nombre'])?>
                    </option>
                <?php endforeach; ?>
            </select>
        </label>

        <div>
            <button class="btn primary">Crear usuario</button>
        </div>

    </form>

</section>


<section class="panel">

    <h2>Usuarios</h2>

    <p class="panel-description">
        Haz clic en un usuario para editarlo, o usa el botón
        rojo para eliminarlo.
    </p>

    <table>

        <tr>
            <th>Nombre</th>
            <th>Usuario</th>
            <th>Rol</th>
            <th>Estado</th>
            <th></th>
        </tr>

        <?php if(empty($users)): ?>
            <tr>
                <td colspan="5" style="text-align:center;padding:20px;">
                    No hay usuarios registrados.
                </td>
            </tr>
        <?php endif; ?>

        <?php foreach($users as $u): ?>

            <tr
                class="clickable-row"
                data-id="<?=e($u['id_usuario'])?>"
                data-nombre="<?=e($u['nombre'])?>"
                data-usuario="<?=e($u['usuario'])?>"
                data-rol="<?=e($u['id_rol'])?>"
                title="Clic para editar"
            >

                <td><?=e($u['nombre'])?></td>
                <td><?=e($u['usuario'])?></td>
                <td><?=e($u['rol'])?></td>
                <td><?=($u['activo']?'Activo':'Inactivo')?></td>

                <td>

                    <button
                        type="button"
                        class="btn sm danger js-delete-trigger"
                        data-action="user_delete"
                        data-id="<?=$u['id_usuario']?>"
                        data-label="<?=e($u['usuario'])?>"
                    >
                        Eliminar
                    </button>

                </td>

            </tr>

        <?php endforeach; ?>

    </table>

</section>


<!-- =========================================================
     MODAL DE EDICIÓN DE USUARIO
     ========================================================= -->

<div
    id="userEditModal"
    class="edit-modal"
    aria-hidden="true"
>

    <div
        class="edit-modal-box"
        role="dialog"
        aria-modal="true"
        aria-labelledby="userEditTitle"
    >

        <div class="edit-modal-header">

            <h2 id="userEditTitle">
                Editar usuario
            </h2>

            <button
                type="button"
                class="edit-modal-close"
                id="closeUserEditModal"
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

            <input type="hidden" name="csrf" value="<?=e(csrf())?>">
            <input type="hidden" name="action" value="user_update">
            <input type="hidden" name="return_page" value="users">
            <input type="hidden" name="id" id="editUserId">

            <label>
                Nombre
                <input name="nombre" id="editUserNombre" required>
            </label>

            <label>
                Usuario
                <input name="usuario" id="editUserUsuario" required>
            </label>

            <label>
                Rol
                <select name="rol" id="editUserRol">
                    <?php foreach($roles as $r): ?>
                        <option value="<?=$r['id_rol']?>">
                            <?=e($r['nombre'])?>
                        </option>
                    <?php endforeach; ?>
                </select>
            </label>

            <label>
                Nueva contraseña

                <input
                    type="password"
                    name="password"
                    placeholder="Dejar vacío para no cambiarla"
                >

                <small class="muted">
                    Deja este campo vacío si no quieres cambiar la contraseña actual.
                </small>

            </label>

            <div class="edit-modal-footer">

                <button
                    type="button"
                    class="btn"
                    id="cancelUserEdit"
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
                <input type="hidden" name="return_page" value="users">
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


<!-- =========================================================
     JAVASCRIPT
     ========================================================= -->

<script>

document.addEventListener('DOMContentLoaded', function(){

    /* =====================================================
       EDITAR USUARIO
       ===================================================== */

    const editModal = document.getElementById('userEditModal');
    const closeEditBtn = document.getElementById('closeUserEditModal');
    const cancelEditBtn = document.getElementById('cancelUserEdit');


    function openEditModal(row){

        document.getElementById('editUserId').value = row.dataset.id;
        document.getElementById('editUserNombre').value = row.dataset.nombre;
        document.getElementById('editUserUsuario').value = row.dataset.usuario;
        document.getElementById('editUserRol').value = row.dataset.rol;

        editModal.classList.add('show');
        editModal.setAttribute('aria-hidden','false');

    }


    function closeEditModal(){

        editModal.classList.remove('show');
        editModal.setAttribute('aria-hidden','true');

    }


    document.querySelectorAll('tr.clickable-row').forEach(function(row){

        row.addEventListener('click', function(e){

            if(e.target.closest('button, a, form, input, select')){
                return;
            }

            openEditModal(row);

        });

    });


    closeEditBtn.addEventListener('click', closeEditModal);
    cancelEditBtn.addEventListener('click', closeEditModal);

    editModal.addEventListener('click', function(e){
        if(e.target === editModal){
            closeEditModal();
        }
    });


    /* =====================================================
       ELIMINAR USUARIO
       ===================================================== */

    const deleteModal = document.getElementById('deleteConfirmModal');
    const closeDeleteBtn = document.getElementById('closeDeleteModal');
    const cancelDeleteBtn = document.getElementById('cancelDeleteModal');
    const deleteTitle = document.getElementById('deleteConfirmTitle');
    const deleteText = document.getElementById('deleteConfirmText');
    const deleteAction = document.getElementById('deleteConfirmAction');
    const deleteId = document.getElementById('deleteConfirmId');


    function openDeleteModal(action, id, label){

        deleteAction.value = action;
        deleteId.value = id;

        deleteTitle.textContent = 'Eliminar "' + label + '"';

        deleteText.textContent =
            '¿Seguro que deseas eliminar el usuario "' + label + '"? ' +
            'Ya no podrá iniciar sesión en el sistema.';

        deleteModal.classList.add('show');
        deleteModal.setAttribute('aria-hidden','false');

    }


    function closeDeleteModal(){

        deleteModal.classList.remove('show');
        deleteModal.setAttribute('aria-hidden','true');

    }


    document.querySelectorAll('.js-delete-trigger').forEach(function(btn){

        btn.addEventListener('click', function(e){

            e.stopPropagation();

            openDeleteModal(
                btn.dataset.action,
                btn.dataset.id,
                btn.dataset.label
            );

        });

    });


    closeDeleteBtn.addEventListener('click', closeDeleteModal);
    cancelDeleteBtn.addEventListener('click', closeDeleteModal);

    deleteModal.addEventListener('click', function(e){
        if(e.target === deleteModal){
            closeDeleteModal();
        }
    });


    /* =====================================================
       ESC PARA CERRAR CUALQUIER MODAL ABIERTO
       ===================================================== */

    document.addEventListener('keydown', function(e){

        if(e.key !== 'Escape'){
            return;
        }

        if(editModal.classList.contains('show')){
            closeEditModal();
        }

        if(deleteModal.classList.contains('show')){
            closeDeleteModal();
        }

    });

});

</script>