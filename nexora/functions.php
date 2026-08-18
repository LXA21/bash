<?php
require_once __DIR__.'/auth.php';

function e($v): string {
    return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

function money($v,$s='$'): string {
    return $s.number_format((float)$v,2,'.',',');
}

function flash($type=null,$msg=null) {
    if ($msg!==null) {
        $_SESSION['flash']=[$type,$msg];
        return;
    }

    $f=$_SESSION['flash']??null;
    unset($_SESSION['flash']);

    return $f;
}

function one($sql,$p=[]): ?array {
    $s=db()->prepare($sql);
    $s->execute($p);
    $r=$s->fetch();

    return $r?:null;
}

function allrows($sql,$p=[]): array {
    $s=db()->prepare($sql);
    $s->execute($p);

    return $s->fetchAll();
}

function post($k,$d=null) {
    return $_POST[$k]??$d;
}

function redirect($u) {
    header('Location: '.$u);
    exit;
}

function base_currency(): array {
    return one("
        SELECT *
        FROM monedas
        WHERE es_moneda_base=1
          AND activo=1
        LIMIT 1
    ") ?: [
        'codigo'=>'USD',
        'simbolo'=>'$',
        'tasa_referencia'=>1,
        'id_moneda'=>1
    ];
}


/*
|--------------------------------------------------------------------------
| ENTRADA DE INVENTARIO
|--------------------------------------------------------------------------
| Aumenta stock_actual cuando entra mercancía.
*/
function product_stock_in(PDO $pdo,int $id,float $qty,float $cost): void {

    $p=one("
        SELECT stock_actual,costo_promedio
        FROM productos
        WHERE id_producto=?
        FOR UPDATE
    ",[$id]);

    if(!$p) {
        throw new Exception('Producto no encontrado.');
    }

    $old=(float)$p['stock_actual'];
    $oldc=(float)$p['costo_promedio'];

    $new=$old+$qty;

    $avg=$new>0
        ? (($old*$oldc)+($qty*$cost))/$new
        : $cost;

    $pdo->prepare("
        UPDATE productos
        SET
            stock_actual=?,
            precio_compra=?,
            costo_promedio=?
        WHERE id_producto=?
    ")->execute([
        $new,
        $cost,
        $avg,
        $id
    ]);
}


/*
|--------------------------------------------------------------------------
| SALIDA DE INVENTARIO
|--------------------------------------------------------------------------
| Disminuye stock_actual cuando se vende mercancía.
*/
function product_stock_out(PDO $pdo,int $id,float $qty): float {

    $p=one("
        SELECT stock_actual
        FROM productos
        WHERE id_producto=?
        FOR UPDATE
    ",[$id]);

    if(!$p) {
        throw new Exception('Producto no encontrado.');
    }

    $old=(float)$p['stock_actual'];

    if($old+0.00001<$qty) {
        throw new Exception(
            "Stock insuficiente. Disponible: ".$old
        );
    }

    $pdo->prepare("
        UPDATE productos
        SET stock_actual=?
        WHERE id_producto=?
    ")->execute([
        $old-$qty,
        $id
    ]);

    return $old;
}