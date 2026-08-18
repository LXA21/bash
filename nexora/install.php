<?php
require_once __DIR__.'/db.php';
$msg=''; $err='';
try {
    $r=one("SELECT id_usuario FROM usuarios WHERE usuario='admin' LIMIT 1");
    if(!$r){
        $role=one("SELECT id_rol FROM roles WHERE nombre='Administrador'");
        if(!$role) throw new Exception('Importa primero database.sql.');
        $h=password_hash('admin123',PASSWORD_DEFAULT);
        db()->prepare("INSERT INTO usuarios(id_rol,nombre,usuario,password) VALUES(?,?,?,?)")
           ->execute([$role['id_rol'],'Administrador','admin',$h]);
        $msg='Administrador creado: admin / admin123';
    } else $msg='El usuario admin ya existe.';
} catch(Throwable $e){$err=$e->getMessage();}
?><!doctype html><html lang="es"><head><meta charset="utf-8"><link rel="stylesheet" href="assets/style.css"><title>Instalación</title></head>
<body class="login"><div class="login-card"><h2>Instalación</h2>
<?php if($msg):?><div class="alert success"><?=e($msg)?></div><a class="btn primary full" href="login.php">Entrar</a><?php endif;?>
<?php if($err):?><div class="alert danger"><?=e($err)?></div><?php endif;?>
<p class="muted">Elimina install.php después de usarlo.</p></div></body></html>
