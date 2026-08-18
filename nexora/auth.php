<?php
require_once __DIR__.'/db.php';
if (session_status() !== PHP_SESSION_ACTIVE) session_start();
function csrf(): string {
    if (empty($_SESSION['csrf'])) $_SESSION['csrf']=bin2hex(random_bytes(32));
    return $_SESSION['csrf'];
}
function check_csrf(): void {
    if ($_SERVER['REQUEST_METHOD']==='POST' && !hash_equals($_SESSION['csrf']??'', $_POST['csrf']??'')) {
        http_response_code(419); exit('Token CSRF inválido.');
    }
}
function user(): ?array { return $_SESSION['user'] ?? null; }
function login_user(array $u): void { $_SESSION['user']=$u; }
function logout_user(): void { $_SESSION=[]; session_destroy(); }
function require_login(): void { if (!user()) { header('Location: login.php'); exit; } }
function admin_only(): void { if ((user()['rol']??'')!=='Administrador') { http_response_code(403); exit('Acceso no autorizado.'); } }
