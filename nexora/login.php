<?php
require_once __DIR__.'/functions.php';
if(user()) redirect('index.php');
$error='';
if($_SERVER['REQUEST_METHOD']==='POST'){
    check_csrf();
    $u=trim(post('usuario','')); $p=(string)post('password','');
 $r=one("SELECT u.id_usuario,u.nombre,u.usuario,u.password,r.nombre rol
            FROM usuarios u JOIN roles r ON r.id_rol=u.id_rol
            WHERE u.usuario=? AND u.activo=1",[$u]);
    if($r && password_verify($p,$r['password'])) { login_user($r); redirect('index.php'); }
    $error='Usuario o contraseña incorrectos.';
}
?>
<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mi Tienda - Acceso</title><link rel="stylesheet" href="assets/style.css"></head>
<body class="login"><form class="login-card" method="post">
<div class="brand"><div class="logo">▣</div><div><b>Mi Tienda</b><small>Sistema de Facturación</small></div></div>
<h2>Iniciar sesión</h2>
<?php if($error):?><div class="alert danger"><?=e($error)?></div><?php endif;?>
<input type="hidden" name="csrf" value="<?=e(csrf())?>">
<label>Usuario<input name="usuario" required autofocus></label>
<label>Contraseña<input type="password" name="password" required></label>
<button class="btn primary full">Ingresar</button>
<p class="muted">Usuario inicial: admin / admin123</p>
</form></body></html>
