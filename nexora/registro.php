<?php
require_once __DIR__.'/functions.php';

if(user()) redirect('index.php');

$error = '';
$exito = '';

// SOLUCIÓN 1: Usar 'allrows' en lugar de 'all'
$lista_roles = allrows("SELECT id_rol, nombre FROM roles ORDER BY nombre ASC");

if($_SERVER['REQUEST_METHOD'] === 'POST'){
    check_csrf(); 
    
    $nombre = trim(post('nombre', ''));
    $u = trim(post('usuario', '')); 
    $p = (string)post('password', '');
    $id_rol = (int)post('id_rol', 0);
    
    if (empty($nombre) || empty($u) || empty($p) || empty($id_rol)) {
        $error = 'Todos los campos son obligatorios, incluyendo el rol.';
    } else {
        // Verificamos si el usuario ya existe
        $existe = one("SELECT id_usuario FROM usuarios WHERE usuario = ?", [$u]);
        
        if($existe) {
            $error = 'El nombre de usuario ya se encuentra registrado.';
        } else {
            // Generamos el hash de la contraseña
            $password_hash = password_hash($p, PASSWORD_DEFAULT);
            
            // SOLUCIÓN 2: Usar db()->prepare()->execute() para el INSERT
            $sql = "INSERT INTO usuarios (id_rol, nombre, usuario, password, activo) VALUES (?, ?, ?, ?, 1)";
            db()->prepare($sql)->execute([$id_rol, $nombre, $u, $password_hash]);
            
            $exito = 'Usuario registrado exitosamente. Ya puedes iniciar sesión.';
        }
    }
}
?>
<!doctype html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Mi Tienda - Registro</title>
    <link rel="stylesheet" href="assets/style.css">
</head>
<body class="login">
    <form class="login-card" method="post">
        <div class="brand">
            <div class="logo">▣</div>
            <div><b>Mi Tienda</b><small>Sistema de Facturación</small></div>
        </div>
        
        <h2>Registrar Usuario</h2>
        
        <?php if($error): ?>
            <div class="alert danger"><?=e($error)?></div>
        <?php endif; ?>
        
        <?php if($exito): ?>
            <div class="alert success"><?=e($exito)?></div>
        <?php endif; ?>
        
        <input type="hidden" name="csrf" value="<?=e(csrf())?>">
        
        <label>Nombre Completo
            <input name="nombre" required autofocus>
        </label>
        
        <label>Usuario
            <input name="usuario" required>
        </label>

        <!-- Menú desplegable para seleccionar el rol -->
        <label>Rol en el Sistema
            <select name="id_rol" required style="width: 100%; padding: 8px; margin-top: 5px; margin-bottom: 15px;">
                <option value="">Seleccione un rol...</option>
                <?php foreach($lista_roles as $rol): ?>
                    <option value="<?=e($rol['id_rol'])?>"><?=e($rol['nombre'])?></option>
                <?php endforeach; ?>
            </select>
        </label>
        
        <label>Contraseña
            <input type="password" name="password" required>
        </label>
        
        <button class="btn primary full">Registrarse</button>
        <p class="muted" style="text-align: center; margin-top: 15px;">
            <a href="login.php" style="color: inherit;">¿Ya tienes cuenta? Inicia sesión aquí</a>
        </p>
    </form>
</body>
</html>