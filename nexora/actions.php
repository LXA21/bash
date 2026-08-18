<?php

require_once __DIR__.'/functions.php';

require_login();
check_csrf();

$action=post('action','');

try {

    $pdo=db();

    switch($action) {


               /*
        |--------------------------------------------------------------------------
        | GUARDAR PRODUCTO
        |--------------------------------------------------------------------------
        */

        case 'product_save':

            $id=(int)post('id',0);

            $codigo=trim(post('codigo',''));
            $nombre=trim(post('nombre',''));
            $categoria=(int)post('categoria',0);
            $precioVenta=(float)post('precio_venta',0);
            $precioCompra=(float)post('precio_compra',0);


            /*
             * STOCK INICIAL
             */

            $stockActual=(float)post('stock',0);

            $stockMinimo=(float)post('stock_minimo',0);

            $activo=(int)post('activo',1);


            /*
             * VALIDACIONES
             */

            if($codigo==='' || $nombre==='') {

                throw new Exception(
                    'Código y nombre son obligatorios.'
                );

            }


            if($precioVenta<0 || $precioCompra<0) {

                throw new Exception(
                    'Los precios no pueden ser negativos.'
                );

            }


            if($stockActual<0 || $stockMinimo<0) {

                throw new Exception(
                    'El stock no puede ser negativo.'
                );

            }



            /*
             |--------------------------------------------------------------------------
             | PROCESAR IMAGEN
             |--------------------------------------------------------------------------
             */

            $imagenRuta=null;


            if(
                isset($_FILES['imagen']) &&
                $_FILES['imagen']['error'] !== UPLOAD_ERR_NO_FILE
            ) {


                /*
                 * Comprobar errores de subida
                 */

                if(
                    $_FILES['imagen']['error'] !==
                    UPLOAD_ERR_OK
                ) {

                    throw new Exception(
                        'No se pudo cargar la imagen.'
                    );

                }


                /*
                 * Máximo 5 MB
                 */

                if(
                    $_FILES['imagen']['size'] >
                    5 * 1024 * 1024
                ) {

                    throw new Exception(
                        'La imagen no puede superar los 5 MB.'
                    );

                }


                /*
                 * Comprobar que realmente sea una imagen
                 */

                $tmp=
                    $_FILES['imagen']['tmp_name'];


                $imageInfo=
                    @getimagesize($tmp);


                if($imageInfo===false) {

                    throw new Exception(
                        'El archivo seleccionado no es una imagen válida.'
                    );

                }


                /*
                 * MIME permitido
                 */

                $allowedTypes=[
                    'image/jpeg'=>'jpg',
                    'image/png'=>'png',
                    'image/webp'=>'webp',
                    'image/gif'=>'gif'
                ];


                $mime=
                    $imageInfo['mime'] ?? '';


                if(
                    !isset(
                        $allowedTypes[$mime]
                    )
                ) {

                    throw new Exception(
                        'Formato de imagen no permitido. Usa JPG, PNG, WEBP o GIF.'
                    );

                }


                /*
                 * Crear carpeta
                 */

                $uploadDir=
                    __DIR__.'/uploads/products';


                if(!is_dir($uploadDir)) {

                    if(
                        !mkdir(
                            $uploadDir,
                            0775,
                            true
                        )
                    ) {

                        throw new Exception(
                            'No se pudo crear la carpeta de imágenes.'
                        );

                    }

                }


                /*
                 * Nombre único
                 */

                $extension=
                    $allowedTypes[$mime];


                $fileName=
                    'product_'.
                    bin2hex(
                        random_bytes(16)
                    ).
                    '.'.
                    $extension;


                $destination=
                    $uploadDir.'/'.$fileName;


                /*
                 * Mover imagen
                 */

                if(
                    !move_uploaded_file(
                        $tmp,
                        $destination
                    )
                ) {

                    throw new Exception(
                        'No se pudo guardar la imagen.'
                    );

                }


                /*
                 * Ruta que se guardará en MySQL
                 */

                $imagenRuta=
                    'uploads/products/'.$fileName;

            }



            /*
             |--------------------------------------------------------------------------
             | ACTUALIZAR PRODUCTO
             |--------------------------------------------------------------------------
             */

            if($id) {


                /*
                 * Si se subió una imagen nueva,
                 * también actualizamos imagen.
                 */

                if($imagenRuta!==null) {

                    /*
                     * Obtener imagen anterior
                     */

                    $old=one("
                        SELECT imagen
                        FROM productos
                        WHERE id_producto=?
                    ",[$id]);


                    $pdo->prepare("
                        UPDATE productos
                        SET
                            codigo=?,
                            nombre=?,
                            id_categoria=?,
                            precio_venta=?,
                            precio_compra=?,
                            costo_promedio=?,
                            stock_actual=?,
                            stock_minimo=?,
                            activo=?,
                            imagen=?
                        WHERE id_producto=?
                    ")->execute([
                        $codigo,
                        $nombre,
                        $categoria,
                        $precioVenta,
                        $precioCompra,
                        $precioCompra,
                        $stockActual,
                        $stockMinimo,
                        $activo,
                        $imagenRuta,
                        $id
                    ]);

                    /*
                     * Eliminar imagen anterior
                     * si existe.
                     */

                    if(
                        $old &&
                        !empty($old['imagen'])
                    ) {

                        $oldFile=
                            __DIR__.'/'.$old['imagen'];


                        if(
                            is_file($oldFile)
                        ) {

                            @unlink($oldFile);

                        }

                    }

                } else {


                    /*
                     * Actualizar sin cambiar
                     * la imagen existente.
                     */

                    $pdo->prepare("
                        UPDATE productos
                        SET
                            codigo=?,
                            nombre=?,
                            id_categoria=?,
                            precio_venta=?,
                            precio_compra=?,
                            stock_actual=?,
                            stock_minimo=?,
                            activo=?
                        WHERE id_producto=?
                    ")->execute([
                        $codigo,
                        $nombre,
                        $categoria,
                        $precioVenta,
                        $precioCompra,
                        $stockActual,
                        $stockMinimo,
                        $activo,
                        $id
                    ]);

                }

            } else {


                /*
                 |--------------------------------------------------------------------------
                 | CREAR NUEVO PRODUCTO
                 |--------------------------------------------------------------------------
                 */

                $pdo->prepare("
                    INSERT INTO productos
                    (
                        codigo,
                        nombre,
                        id_categoria,
                        precio_venta,
                        precio_compra,
                        costo_promedio,
                        stock_actual,
                        stock_minimo,
                        activo,
                        imagen
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $codigo,
                    $nombre,
                    $categoria,
                    $precioVenta,
                    $precioCompra,
                    $precioCompra,
                    $stockActual,
                    $stockMinimo,
                    1,
                    $imagenRuta
                ]);

            }


            flash(
                'success',
                'Producto guardado correctamente.'
            );


            break;

        /*
        |--------------------------------------------------------------------------
        | DESACTIVAR PRODUCTO
        |--------------------------------------------------------------------------
        */

        case 'product_delete':

            $pdo->prepare("
                UPDATE productos
                SET activo=0
                WHERE id_producto=?
            ")->execute([
                (int)post('id')
            ]);

            flash('success','Producto desactivado.');

            break;


        /*
        |--------------------------------------------------------------------------
        | GUARDAR CLIENTE
        |--------------------------------------------------------------------------
        */

        case 'client_save':

            $id=(int)post('id',0);

           $d=[
                trim(post('nombre','')),
                trim(post('documento','')),
                trim(post('telefono','')),
                trim(post('correo','')),
                trim(post('direccion',''))
            ];


            if($id) {

                $d[]=$id;

                $pdo->prepare("
                    UPDATE clientes
                    SET
                        nombre=?,
                        documento=?,
                        telefono=?,
                        correo=?,
                        direccion=?
                    WHERE id_cliente=?
                ")->execute($d);

            } else {

                $pdo->prepare("
                    INSERT INTO clientes
                    (
                        nombre,
                        documento,
                        telefono,
                        correo,
                        direccion
                    )
                    VALUES(?,?,?,?,?)
                ")->execute($d);

            }

            flash('success','Cliente guardado.');

            break;
                 /*
        |--------------------------------------------------------------------------
        | DESACTIVAR CLIENTES SELECCIONADOS
        |--------------------------------------------------------------------------
        */

        case 'client_delete_multiple':

            $ids = post('clientes', []);


            /*
             * Comprobar que existan clientes seleccionados
             */

            if(!is_array($ids) || empty($ids)) {

                throw new Exception(
                    'No seleccionaste ningún cliente.'
                );

            }


            /*
             * Convertir los IDs a números enteros
             */

            $ids = array_map(
                'intval',
                $ids
            );


            /*
             * Eliminar IDs inválidos
             */

            $ids = array_filter(
                $ids,
                function($id){

                    return $id > 0;

                }
            );


            /*
             * Eliminar IDs repetidos
             */

            $ids = array_values(
                array_unique($ids)
            );


            if(empty($ids)) {

                throw new Exception(
                    'No se encontraron clientes válidos.'
                );

            }


            /*
             * Crear los signos ?
             *
             * Ejemplo:
             *
             * 3 clientes:
             *
             * ?,?,?
             */

            $placeholders =
                implode(
                    ',',
                    array_fill(
                        0,
                        count($ids),
                        '?'
                    )
                );


            /*
             * DESACTIVAR CLIENTES
             *
             * No hacemos DELETE.
             *
             * Esto conserva las ventas históricas.
             */

            $stmt = $pdo->prepare("
                UPDATE clientes
                SET activo=0
                WHERE id_cliente IN ($placeholders)
            ");


            $stmt->execute(
                $ids
            );


            /*
             * Obtener cantidad de clientes afectados
             */

            $deleted =
                $stmt->rowCount();


            if($deleted === 0) {

                throw new Exception(
                    'No se pudo desactivar ningún cliente.'
                );

            }


            /*
             * Mensaje de éxito
             */

            flash(
                'success',
                $deleted === 1
                    ? 'Cliente eliminado correctamente.'
                    : $deleted.' clientes eliminados correctamente.'
            );


            break;
                 /*
        |--------------------------------------------------------------------------
        | DESACTIVAR PROVEEDORES SELECCIONADOS
        |--------------------------------------------------------------------------
        */

        case 'supplier_delete_multiple':

            $ids = post('proveedores', []);


            /*
             * Verificar que realmente recibimos
             * proveedores seleccionados.
             */

            if(!is_array($ids) || empty($ids)) {

                throw new Exception(
                    'No seleccionaste ningún proveedor.'
                );

            }


            /*
             * Convertir todos los IDs a enteros
             * y eliminar valores inválidos.
             */

            $ids = array_map(
                'intval',
                $ids
            );


            $ids = array_filter(
                $ids,
                function($id){

                    return $id > 0;

                }
            );


            /*
             * Eliminar IDs duplicados.
             */

            $ids = array_values(
                array_unique($ids)
            );


            if(empty($ids)) {

                throw new Exception(
                    'No se encontraron proveedores válidos.'
                );

            }


            /*
             * Preparar la consulta.
             *
             * NO hacemos DELETE físico.
             *
             * Cambiamos activo=0.
             *
             * Esto permite conservar las compras
             * históricas relacionadas con el proveedor.
             */

            $placeholders =
                implode(
                    ',',
                    array_fill(
                        0,
                        count($ids),
                        '?'
                    )
                );


            $stmt = $pdo->prepare("
                UPDATE proveedores
                SET activo=0
                WHERE id_proveedor IN ($placeholders)
            ");


            $stmt->execute(
                $ids
            );


            /*
             * Obtener cantidad realmente afectada.
             */

            $deleted =
                $stmt->rowCount();


            if($deleted === 0) {

                throw new Exception(
                    'No se pudo desactivar ningún proveedor.'
                );

            }


            flash(
                'success',
                $deleted === 1
                    ? 'Proveedor eliminado correctamente.'
                    : $deleted.' proveedores eliminados correctamente.'
            );


            break;
        /*
        |--------------------------------------------------------------------------
        | GUARDAR PROVEEDOR
        |--------------------------------------------------------------------------
        */

        case 'supplier_save':

            $id=(int)post('id',0);

            $d=[
                trim(post('nombre','')),
                trim(post('documento','')),
                trim(post('telefono','')),
                trim(post('correo','')),
                trim(post('direccion',''))
            ];


            if($id) {

                $d[]=$id;

                $pdo->prepare("
                    UPDATE proveedores
                    SET
                        nombre=?,
                        documento=?,
                        telefono=?,
                        correo=?,
                        direccion=?
                    WHERE id_proveedor=?
                ")->execute($d);

            } else {

                $pdo->prepare("
                    INSERT INTO proveedores
                    (
                        nombre,
                        documento,
                        telefono,
                        correo,
                        direccion
                    )
                    VALUES(?,?,?,?,?)
                ")->execute($d);

            }

            flash('success','Proveedor guardado.');

            break;


        /*
        |--------------------------------------------------------------------------
        | REGISTRAR COMPRA
        |--------------------------------------------------------------------------
        */

        case 'purchase_save':

            $supplier=(int)post('proveedor',0);
            $currency=(int)post('moneda',0);
            $invoice=trim(post('factura',''));

            $ids=post('product_id',[]);
            $qtys=post('quantity',[]);
            $costs=post('cost',[]);


            if(!$supplier || !$currency || !$invoice || !$ids) {
                throw new Exception(
                    'Proveedor, moneda, factura y productos son obligatorios.'
                );
            }


            $pdo->beginTransaction();

            $sub=0;
            $items=[];


            foreach($ids as $i=>$pid) {

                $q=(float)($qtys[$i]??0);
                $c=(float)($costs[$i]??0);

                if($q<=0) {
                    continue;
                }

                if($c<0) {
                    throw new Exception('El costo no puede ser negativo.');
                }

                $line=$q*$c;

                $sub+=$line;

                $items[]=[
                    (int)$pid,
                    $q,
                    $c,
                    $line
                ];
            }


            if(!$items) {
                throw new Exception('Agrega al menos un producto.');
            }


            $desc=(float)post('descuento',0);
            $tax=(float)post('impuesto',0);

            $total=max(
                0,
                $sub-$desc+$tax
            );


            /*
             * La tabla compras requiere id_usuario.
             */
            $pdo->prepare("
                INSERT INTO compras
                (
                    numero_factura,
                    id_proveedor,
                    id_usuario,
                    id_moneda,
                    subtotal,
                    descuento,
                    impuesto,
                    total
                )
                VALUES(?,?,?,?,?,?,?,?)
            ")->execute([
                $invoice,
                $supplier,
                user()['id_usuario'],
                $currency,
                $sub,
                $desc,
                $tax,
                $total
            ]);


            $cid=(int)$pdo->lastInsertId();


            foreach($items as [$pid,$q,$c,$line]) {

                /*
                 * Guardamos el detalle de la compra.
                 *
                 * La BD utiliza precio_unitario,
                 * no costo_unitario.
                 */
                $pdo->prepare("
                    INSERT INTO detalle_compras
                    (
                        id_compra,
                        id_producto,
                        cantidad,
                        precio_unitario,
                        subtotal
                    )
                    VALUES(?,?,?,?,?)
                ")->execute([
                    $cid,
                    $pid,
                    $q,
                    $c,
                    $line
                ]);


                /*
                 * Capturamos el id_detalle_compra
                 * INMEDIATAMENTE después de insertarlo,
                 * antes de que product_stock_in() u otra
                 * operación puedan sobrescribir
                 * lastInsertId().
                 */
                $detailId=(int)$pdo->lastInsertId();


                /*
                 * Stock antes de la entrada.
                 */
                $before=one("
                    SELECT stock_actual
                    FROM productos
                    WHERE id_producto=?
                    FOR UPDATE
                ",[$pid]);


                if(!$before) {
                    throw new Exception(
                        'Producto no encontrado.'
                    );
                }


                $stockAnterior=(float)$before['stock_actual'];


                /*
                 * Aumentar inventario.
                 */
                product_stock_in(
                    $pdo,
                    $pid,
                    $q,
                    $c
                );


                /*
                 * Stock después de la entrada.
                 */
                $after=one("
                    SELECT stock_actual
                    FROM productos
                    WHERE id_producto=?
                ",[$pid]);


                $stockNuevo=(float)$after['stock_actual'];


                /*
                 * Registrar movimiento.
                 *
                 * Se utilizan los nombres reales
                 * de movimientos_inventario.
                 */
                $pdo->prepare("
                    INSERT INTO movimientos_inventario
                    (
                        id_producto,
                        tipo_movimiento,
                        cantidad,
                        stock_anterior,
                        stock_nuevo,
                        costo_unitario,
                        id_compra,
                        id_detalle_compra,
                        id_usuario
                    )
                    VALUES(?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $pid,
                    'ENTRADA_COMPRA',
                    $q,
                    $stockAnterior,
                    $stockNuevo,
                    $c,
                    $cid,
                    $detailId,
                    user()['id_usuario']
                ]);

            }


            $pdo->commit();

            flash(
                'success',
                'Compra registrada y stock actualizado.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | REGISTRAR VENTA
        |--------------------------------------------------------------------------
        */

        case 'sale_save':

            $client=(int)post('cliente',0) ?: null;
            $currency=(int)post('moneda',0);

            $ids=post('product_id',[]);
            $qtys=post('quantity',[]);
            $prices=post('price',[]);


            if(!$currency || !$ids) {
                throw new Exception(
                    'Moneda y productos son obligatorios.'
                );
            }


            $pdo->beginTransaction();

            $sub=0;
            $items=[];


            foreach($ids as $i=>$pid) {

                $q=(float)($qtys[$i]??0);
                $p=(float)($prices[$i]??0);

                if($q<=0) {
                    continue;
                }

                if($p<0) {
                    throw new Exception(
                        'El precio no puede ser negativo.'
                    );
                }


                $prod=one("
                    SELECT costo_promedio
                    FROM productos
                    WHERE id_producto=?
                      AND activo=1
                ",[$pid]);


                if(!$prod) {
                    throw new Exception(
                        'Producto inválido.'
                    );
                }


                $line=$q*$p;

                $sub+=$line;

                $items[]=[
                    (int)$pid,
                    $q,
                    $p,
                    $line,
                    (float)$prod['costo_promedio']
                ];
            }


            if(!$items) {
                throw new Exception(
                    'Agrega al menos un producto.'
                );
            }


            $desc=(float)post('descuento',0);
            $tax=(float)post('impuesto',0);

            $total=max(
                0,
                $sub-$desc+$tax
            );


            $num='F-'.date('YmdHis').'-'.random_int(10,99);


            /*
             * Guardamos una "foto" de las tasas de todas
             * las monedas activas en el momento de la venta.
             * Así, si luego actualizas el valor del dólar,
             * esta factura siempre mostrará la conversión
             * con la tasa que estaba vigente ese día.
             */
            $tasasActivas=allrows("
                SELECT codigo, tasa_referencia
                FROM monedas
                WHERE activo=1
            ");

            $tasasSnapshot=[];

            foreach($tasasActivas as $tc) {
                $tasasSnapshot[$tc['codigo']]=(float)$tc['tasa_referencia'];
            }

            $tasasJson=json_encode($tasasSnapshot);


            $pdo->prepare("
                INSERT INTO ventas
                (
                    numero_factura,
                    id_cliente,
                    id_usuario,
                    id_moneda,
                    tasas_cambio,
                    subtotal,
                    descuento,
                    impuesto,
                    total,
                    estado
                )
                VALUES(?,?,?,?,?,?,?,?,?,?)
            ")->execute([
                $num,
                $client,
                user()['id_usuario'],
                $currency,
                $tasasJson,
                $sub,
                $desc,
                $tax,
                $total,
                'COMPLETADA'
            ]);

            $vid=(int)$pdo->lastInsertId();


            foreach($items as [$pid,$q,$p,$line,$cost]) {

                /*
                 * product_stock_out devuelve el stock anterior.
                 */
                $stockAnterior=product_stock_out(
                    $pdo,
                    $pid,
                    $q
                );


                $stockNuevo=$stockAnterior-$q;


                /*
                 * Registrar detalle de venta.
                 */
                $detail=$pdo->prepare("
                    INSERT INTO detalle_ventas
                    (
                        id_venta,
                        id_producto,
                        cantidad,
                        precio_unitario,
                        costo_unitario,
                        subtotal
                    )
                    VALUES(?,?,?,?,?,?)
                ");


                $detail->execute([
                    $vid,
                    $pid,
                    $q,
                    $p,
                    $cost,
                    $line
                ]);


                $detailId=(int)$pdo->lastInsertId();


                /*
                 * Registrar movimiento de salida.
                 */
                $pdo->prepare("
                    INSERT INTO movimientos_inventario
                    (
                        id_producto,
                        tipo_movimiento,
                        cantidad,
                        stock_anterior,
                        stock_nuevo,
                        costo_unitario,
                        id_venta,
                        id_detalle_venta,
                        id_usuario
                    )
                    VALUES(?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $pid,
                    'SALIDA_VENTA',
                    $q,
                    $stockAnterior,
                    $stockNuevo,
                    $cost,
                    $vid,
                    $detailId,
                    user()['id_usuario']
                ]);

            }


            /*
             * Registrar pagos.
             */
            $methods=post('payment_method',[]);
            $amounts=post('payment_amount',[]);
            $rates=post('payment_rate',[]);


            foreach($methods as $i=>$mid) {

                $a=(float)($amounts[$i]??0);
                $r=(float)($rates[$i]??1);

                if($a<=0) {
                    continue;
                }

                if($r<=0) {
                    $r=1;
                }


                /*
                 * Conversión a moneda base.
                 */
                $amountBase=$a*$r;


                $pdo->prepare("
                    INSERT INTO pagos_ventas
                    (
                        id_venta,
                        id_metodo_pago,
                        monto,
                        tipo_cambio,
                        monto_moneda_base,
                        referencia
                    )
                    VALUES(?,?,?,?,?,?)
                ")->execute([
                    $vid,
                    (int)$mid,
                    $a,
                    $r,
                    $amountBase,
                    trim(post('payment_ref_'.$i,''))
                ]);

            }


            $pdo->commit();


            flash(
                'success',
                'Venta registrada. Factura '.$num
            );


            redirect(
                'index.php?page=invoices&view='.$vid
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | GUARDAR MONEDA
        |--------------------------------------------------------------------------
        |
        | El usuario ingresa "cuántas unidades de esta moneda
        | equivalen a 1 dólar hoy" (ej: 4000 para COP), porque
        | es lo que se ve y se entiende a diario.
        |
        | Internamente guardamos tasa_referencia como el valor
        | en dólares de 1 unidad de esa moneda (1 / valor
        | ingresado), que es lo que usa el resto del sistema
        | para calcular montos en la moneda base.
        */

        case 'currency_save':

            $codigo=strtoupper(
                trim(post('codigo',''))
            );

            $nombre=trim(
                post('nombre','')
            );

            $simbolo=trim(
                post('simbolo','')
            );

            $valorDolar=max(
                0.000001,
                (float)post('tasa',1)
            );

            $tasa=1/$valorDolar;


            $pdo->prepare("
                INSERT INTO monedas
                (
                    codigo,
                    nombre,
                    simbolo,
                    tasa_referencia,
                    es_moneda_base,
                    activo
                )
                VALUES(?,?,?,?,0,1)
            ")->execute([
                $codigo,
                $nombre,
                $simbolo,
                $tasa
            ]);


            flash(
                'success',
                'Moneda agregada.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | ACTUALIZAR TASA DE UNA MONEDA
        |--------------------------------------------------------------------------
        |
        | Igual que arriba: recibe "cuántas unidades de esta
        | moneda equivalen a 1 dólar hoy" y lo convierte antes
        | de guardar.
        */

        case 'currency_update_rate':

            $id=(int)post('id',0);

            $valorDolar=max(
                0.000001,
                (float)post('tasa',1)
            );

            $tasa=1/$valorDolar;


            if(!$id) {
                throw new Exception(
                    'Moneda no válida.'
                );
            }


            $pdo->prepare("
                UPDATE monedas
                SET tasa_referencia=?
                WHERE id_moneda=?
                  AND es_moneda_base=0
            ")->execute([
                $tasa,
                $id
            ]);


            flash(
                'success',
                'Tasa actualizada correctamente.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | GUARDAR MÉTODO DE PAGO
        |--------------------------------------------------------------------------
        */

        case 'payment_save':

            $pdo->prepare("
                INSERT INTO metodos_pago
                (
                    nombre,
                    tipo_pago,
                    id_moneda,
                    activo
                )
                VALUES(?,?,?,1)
            ")->execute([
                trim(post('nombre','')),
                strtoupper(
                    trim(
                        post('tipo_pago','EFECTIVO')
                    )
                ),
                (int)post('moneda')
            ]);


            flash(
                'success',
                'Método de pago agregado.'
            );

            break;
/*
        |--------------------------------------------------------------------------
        | ELIMINAR MÉTODO DE PAGO
        |--------------------------------------------------------------------------
        */

        case 'payment_delete':

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception(
                    'Método de pago no válido.'
                );
            }


            $pdo->prepare("
                UPDATE metodos_pago
                SET activo=0
                WHERE id_metodo_pago=?
            ")->execute([
                $id
            ]);


            flash(
                'success',
                'Método de pago eliminado.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | ELIMINAR MONEDA
        |--------------------------------------------------------------------------
        |
        | Se desactiva (no se borra físicamente), para no romper
        | ventas/facturas históricas que ya guardaron su tasa.
        | Al quedar activo=0, deja de aparecer automáticamente
        | en las conversiones de Productos, Inventario, Ventas
        | y Facturas nuevas, porque todas esas consultas filtran
        | por monedas activas.
        */

        case 'currency_delete':

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception(
                    'Moneda no válida.'
                );
            }


            $cur=one("
                SELECT es_moneda_base
                FROM monedas
                WHERE id_moneda=?
            ",[$id]);

            if(!$cur) {
                throw new Exception(
                    'Moneda no encontrada.'
                );
            }

            if($cur['es_moneda_base']) {
                throw new Exception(
                    'No puedes eliminar la moneda base.'
                );
            }


            $pdo->prepare("
                UPDATE monedas
                SET activo=0
                WHERE id_moneda=?
            ")->execute([
                $id
            ]);


            flash(
                'success',
                'Moneda eliminada. Ya no aparecerá en las conversiones.'
            );

            break;

        /*
        |--------------------------------------------------------------------------
        | CREAR USUARIO
        |--------------------------------------------------------------------------
        */

        case 'user_save':

            admin_only();

            $role=(int)post('rol');

            $hash=password_hash(
                post('password'),
                PASSWORD_DEFAULT
            );


            $pdo->prepare("
                INSERT INTO usuarios
                (
                    id_rol,
                    nombre,
                    usuario,
                    password,
                    activo
                )
                VALUES(?,?,?,?,1)
            ")->execute([
                $role,
                trim(post('nombre')),
                trim(post('usuario')),
                $hash
            ]);


            flash(
                'success',
                'Usuario creado.'
            );

            break;

        /*
        |--------------------------------------------------------------------------
        | ACTUALIZAR USUARIO
        |--------------------------------------------------------------------------
        |
        | La contraseña es opcional: si el campo llega vacío,
        | se conserva la contraseña actual sin cambios.
        */

        case 'user_update':

            admin_only();

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception(
                    'Usuario no válido.'
                );
            }


            $nombre=trim(post('nombre',''));
            $usuario=trim(post('usuario',''));
            $rol=(int)post('rol',0);
            $password=post('password','');


            if($nombre==='' || $usuario==='') {
                throw new Exception(
                    'Nombre y usuario son obligatorios.'
                );
            }


            /*
             * Evitar usuario duplicado en otro registro.
             */

            $dup=one("
                SELECT id_usuario
                FROM usuarios
                WHERE usuario=?
                  AND id_usuario<>?
            ",[$usuario,$id]);

            if($dup) {
                throw new Exception(
                    'Ya existe otro usuario con ese nombre de usuario.'
                );
            }


            if(trim($password)!=='') {

                $hash=password_hash(
                    $password,
                    PASSWORD_DEFAULT
                );

                $pdo->prepare("
                    UPDATE usuarios
                    SET
                        nombre=?,
                        usuario=?,
                        id_rol=?,
                        password=?
                    WHERE id_usuario=?
                ")->execute([
                    $nombre,
                    $usuario,
                    $rol,
                    $hash,
                    $id
                ]);

            } else {

                $pdo->prepare("
                    UPDATE usuarios
                    SET
                        nombre=?,
                        usuario=?,
                        id_rol=?
                    WHERE id_usuario=?
                ")->execute([
                    $nombre,
                    $usuario,
                    $rol,
                    $id
                ]);

            }


            flash(
                'success',
                'Usuario actualizado correctamente.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | ELIMINAR USUARIO
        |--------------------------------------------------------------------------
        |
        | Se desactiva (no se borra físicamente), para conservar
        | el historial de ventas/compras que registró. No se
        | permite desactivar el usuario con el que se tiene la
        | sesión abierta actualmente, para no perder acceso.
        */

        case 'user_delete':

            admin_only();

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception(
                    'Usuario no válido.'
                );
            }


            if($id === (int)user()['id_usuario']) {
                throw new Exception(
                    'No puedes eliminar tu propio usuario mientras tienes la sesión abierta.'
                );
            }


            $pdo->prepare("
                UPDATE usuarios
                SET activo=0
                WHERE id_usuario=?
            ")->execute([
                $id
            ]);


            flash(
                'success',
                'Usuario eliminado.'
            );

            break;
        /*
        |--------------------------------------------------------------------------
        | RESPALDO
        |--------------------------------------------------------------------------
        */

        case 'backup':

            admin_only();

            $dir=__DIR__.'/storage/backups';

            if(!is_dir($dir)) {
                mkdir($dir,0775,true);
            }


            $file=$dir.'/backup_'.date(
                'Y-m-d_H-i-s'
            ).'.sql';


            $tables=allrows(
                "SHOW TABLES"
            );


            $out="-- Mi Tienda backup\n";
            $out.="SET FOREIGN_KEY_CHECKS=0;\n";


            foreach($tables as $t) {

                $name=array_values($t)[0];

                $out.=
                    "DROP TABLE IF EXISTS `$name`;\n";


                $create=one(
                    "SHOW CREATE TABLE `$name`"
                );


                $out.=
                    $create['Create Table'].
                    ";\n";


                $rows=allrows(
                    "SELECT * FROM `$name`"
                );


                foreach($rows as $row) {

                    $cols=array_map(
                        fn($x)=>"`$x`",
                        array_keys($row)
                    );


                    $vals=array_map(
                        fn($x)=>
                            $x===null
                                ? 'NULL'
                                : $pdo->quote($x),
                        array_values($row)
                    );


                    $out.=
                        "INSERT INTO `$name` (".
                        implode(',',$cols).
                        ") VALUES (".
                        implode(',',$vals).
                        ");\n";
                }
            }


            $out.=
                "SET FOREIGN_KEY_CHECKS=1;\n";


            file_put_contents(
                $file,
                $out
            );


            flash(
                'success',
                'Respaldo creado: '.
                basename($file)
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | ACTUALIZAR DATOS DE FACTURA (encabezado)
        |--------------------------------------------------------------------------
        |
        | Solo se editan datos de encabezado: cliente, número de
        | factura, fecha y observaciones. NO se tocan items, montos,
        | pagos ni stock, porque esos ya están ligados al historial
        | de inventario y a los pagos registrados. Para corregir
        | cantidades o productos hay que anular la venta y crear
        | una nueva (acción "cancel_sale" ya existente).
        */

        case 'invoice_save':

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception('Factura no válida.');
            }


            $v=one("
                SELECT id_venta,estado
                FROM ventas
                WHERE id_venta=?
            ",[$id]);

            if(!$v) {
                throw new Exception('Factura no encontrada.');
            }

            if($v['estado']==='ANULADA') {
                throw new Exception(
                    'No se puede editar una factura anulada.'
                );
            }


            $numeroFactura=trim(post('numero_factura',''));
            $cliente=(int)post('cliente',0);
            $fecha=trim(post('fecha',''));
            $observaciones=trim(post('observaciones',''));


            if($numeroFactura==='') {
                throw new Exception(
                    'El número de factura es obligatorio.'
                );
            }

            if($fecha==='') {
                throw new Exception(
                    'La fecha es obligatoria.'
                );
            }


            /*
             * Evitar número de factura duplicado
             * en otra venta distinta a esta.
             */

            $dup=one("
                SELECT id_venta
                FROM ventas
                WHERE numero_factura=?
                  AND id_venta<>?
            ",[$numeroFactura,$id]);

            if($dup) {
                throw new Exception(
                    'Ya existe otra factura con ese número.'
                );
            }


            $pdo->prepare("
                UPDATE ventas
                SET
                    numero_factura=?,
                    id_cliente=?,
                    fecha=?,
                    observaciones=?
                WHERE id_venta=?
            ")->execute([
                $numeroFactura,
                $cliente ?: null,
                $fecha,
                $observaciones,
                $id
            ]);


            flash(
                'success',
                'Factura actualizada correctamente.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | EDITAR PRODUCTOS DE UNA FACTURA (líneas, cantidades, precios)
        |--------------------------------------------------------------------------
        |
        | Reemplaza por completo el detalle de la venta:
        |
        |  1. Revierte el stock de las líneas actuales, como si
        |     la venta no se hubiera hecho.
        |  2. Borra esas líneas.
        |  3. Valida y aplica la nueva lista de productos,
        |     descontando el stock de nuevo (con la misma
        |     validación de "stock insuficiente" que usa una
        |     venta normal).
        |  4. Recalcula subtotal/descuento/impuesto/total.
        |
        | Todo dentro de una sola transacción: si algo falla
        | (ej. stock insuficiente), no se aplica ningún cambio.
        |
        | NOTA: esto NO modifica los pagos ya registrados
        | (pagos_ventas). Si el nuevo total cambia, revisa que
        | los pagos sigan cuadrando.
        */

        case 'invoice_items_save':

            $id=(int)post('id',0);

            if(!$id) {
                throw new Exception('Factura no válida.');
            }


            $pdo->beginTransaction();


            $v=one("
                SELECT *
                FROM ventas
                WHERE id_venta=?
                FOR UPDATE
            ",[$id]);

            if(!$v) {
                throw new Exception('Factura no encontrada.');
            }

            if($v['estado']!=='COMPLETADA') {
                throw new Exception(
                    'Solo se pueden editar los productos de una factura completada.'
                );
            }


            /*
             * -----------------------------------------------
             * 1. REVERTIR STOCK DE LAS LÍNEAS ACTUALES
             * -----------------------------------------------
             */

            $oldItems=allrows("
                SELECT *
                FROM detalle_ventas
                WHERE id_venta=?
            ",[$id]);


            foreach($oldItems as $old) {

                $prod=one("
                    SELECT stock_actual
                    FROM productos
                    WHERE id_producto=?
                    FOR UPDATE
                ",[$old['id_producto']]);

                if(!$prod) {
                    throw new Exception(
                        'Producto no encontrado.'
                    );
                }

                $stockAnterior=(float)$prod['stock_actual'];
                $stockNuevo=$stockAnterior+(float)$old['cantidad'];

                $pdo->prepare("
                    UPDATE productos
                    SET stock_actual=?
                    WHERE id_producto=?
                ")->execute([
                    $stockNuevo,
                    $old['id_producto']
                ]);

                $pdo->prepare("
                    INSERT INTO movimientos_inventario
                    (
                        id_producto,
                        tipo_movimiento,
                        cantidad,
                        stock_anterior,
                        stock_nuevo,
                        costo_unitario,
                        id_venta,
                        id_detalle_venta,
                        id_usuario,
                        observaciones
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $old['id_producto'],
                    'AJUSTE_ENTRADA',
                    (float)$old['cantidad'],
                    $stockAnterior,
                    $stockNuevo,
                    (float)$old['costo_unitario'],
                    $id,
                    $old['id_detalle_venta'],
                    user()['id_usuario'],
                    'Edición de factura #'.$id.' (reverso de línea anterior)'
                ]);

            }


            /*
             * -----------------------------------------------
             * 2. BORRAR LAS LÍNEAS ANTERIORES
             * -----------------------------------------------
             */

            $pdo->prepare("
                DELETE FROM detalle_ventas
                WHERE id_venta=?
            ")->execute([$id]);


            /*
             * -----------------------------------------------
             * 3. VALIDAR Y APLICAR LOS NUEVOS PRODUCTOS
             * -----------------------------------------------
             */

            $ids=post('product_id',[]);
            $qtys=post('quantity',[]);
            $prices=post('price',[]);

            $sub=0;
            $items=[];


            foreach($ids as $i=>$pid) {

                $q=(float)($qtys[$i]??0);
                $p=(float)($prices[$i]??0);

                if($q<=0) {
                    continue;
                }

                if($p<0) {
                    throw new Exception(
                        'El precio no puede ser negativo.'
                    );
                }


                $prod=one("
                    SELECT costo_promedio
                    FROM productos
                    WHERE id_producto=?
                      AND activo=1
                ",[$pid]);

                if(!$prod) {
                    throw new Exception(
                        'Producto inválido.'
                    );
                }


                $line=$q*$p;
                $sub+=$line;

                $items[]=[
                    (int)$pid,
                    $q,
                    $p,
                    $line,
                    (float)$prod['costo_promedio']
                ];

            }


            if(!$items) {
                throw new Exception(
                    'La factura debe tener al menos un producto.'
                );
            }


            foreach($items as [$pid,$q,$p,$line,$cost]) {

                /*
                 * product_stock_out valida que haya stock
                 * suficiente y lo descuenta. Si no alcanza,
                 * lanza excepción y se revierte todo.
                 */
                $stockAnterior=product_stock_out(
                    $pdo,
                    $pid,
                    $q
                );

                $stockNuevo=$stockAnterior-$q;


                $detail=$pdo->prepare("
                    INSERT INTO detalle_ventas
                    (
                        id_venta,
                        id_producto,
                        cantidad,
                        precio_unitario,
                        costo_unitario,
                        subtotal
                    )
                    VALUES(?,?,?,?,?,?)
                ");

                $detail->execute([
                    $id,
                    $pid,
                    $q,
                    $p,
                    $cost,
                    $line
                ]);

                $detailId=(int)$pdo->lastInsertId();


                $pdo->prepare("
                    INSERT INTO movimientos_inventario
                    (
                        id_producto,
                        tipo_movimiento,
                        cantidad,
                        stock_anterior,
                        stock_nuevo,
                        costo_unitario,
                        id_venta,
                        id_detalle_venta,
                        id_usuario,
                        observaciones
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $pid,
                    'AJUSTE_SALIDA',
                    $q,
                    $stockAnterior,
                    $stockNuevo,
                    $cost,
                    $id,
                    $detailId,
                    user()['id_usuario'],
                    'Edición de factura #'.$id.' (nueva línea)'
                ]);

            }


            /*
             * -----------------------------------------------
             * 4. RECALCULAR TOTALES DE LA FACTURA
             * -----------------------------------------------
             */

            $desc=(float)post('descuento',0);
            $tax=(float)post('impuesto',0);

            $total=max(0,$sub-$desc+$tax);

            $pdo->prepare("
                UPDATE ventas
                SET
                    subtotal=?,
                    descuento=?,
                    impuesto=?,
                    total=?
                WHERE id_venta=?
            ")->execute([
                $sub,
                $desc,
                $tax,
                $total,
                $id
            ]);


            $pdo->commit();


            flash(
                'success',
                'Factura actualizada y stock recalculado correctamente.'
            );


            redirect(
                'index.php?page=invoices&view='.$id
            );

            break;


        case 'cancel_sale':

            $id=(int)post('id');

            $pdo->beginTransaction();


            $v=one("
                SELECT *
                FROM ventas
                WHERE id_venta=?
                FOR UPDATE
            ",[$id]);


            if(!$v || $v['estado']!=='COMPLETADA') {
                throw new Exception(
                    'Venta no disponible para anular.'
                );
            }


            $items=allrows("
                SELECT *
                FROM detalle_ventas
                WHERE id_venta=?
            ",[$id]);


            foreach($items as $it) {

                /*
                 * Obtener stock actual antes
                 * de restaurar la mercancía.
                 */
                $before=one("
                    SELECT stock_actual
                    FROM productos
                    WHERE id_producto=?
                    FOR UPDATE
                ",[$it['id_producto']]);


                if(!$before) {
                    throw new Exception(
                        'Producto no encontrado.'
                    );
                }


                $stockAnterior=(float)$before['stock_actual'];

                $cantidad=(float)$it['cantidad'];

                $stockNuevo=$stockAnterior+$cantidad;


                /*
                 * Restaurar stock_actual.
                 */
                $pdo->prepare("
                    UPDATE productos
                    SET stock_actual=?
                    WHERE id_producto=?
                ")->execute([
                    $stockNuevo,
                    $it['id_producto']
                ]);


                /*
                 * Registrar movimiento.
                 */
                $pdo->prepare("
                    INSERT INTO movimientos_inventario
                    (
                        id_producto,
                        tipo_movimiento,
                        cantidad,
                        stock_anterior,
                        stock_nuevo,
                        costo_unitario,
                        id_venta,
                        id_detalle_venta,
                        id_usuario,
                        observaciones
                    )
                    VALUES(?,?,?,?,?,?,?,?,?,?)
                ")->execute([
                    $it['id_producto'],
                    'ENTRADA_DEVOLUCION',
                    $cantidad,
                    $stockAnterior,
                    $stockNuevo,
                    (float)$it['costo_unitario'],
                    $id,
                    $it['id_detalle_venta'],
                    user()['id_usuario'],
                    'Anulación de venta #'.$id
                ]);

            }


            $pdo->prepare("
                UPDATE ventas
                SET estado='ANULADA'
                WHERE id_venta=?
            ")->execute([$id]);


            $pdo->commit();


            flash(
                'success',
                'Venta anulada y stock restaurado.'
            );

            break;


        /*
        |--------------------------------------------------------------------------
        | ACCIÓN DESCONOCIDA
        |--------------------------------------------------------------------------
        */

        default:

            throw new Exception(
                'Acción no válida.'
            );
    }


} catch(Throwable $e) {

    if(isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    flash(
        'danger',
        $e->getMessage()
    );
}


redirect(
    'index.php?page='.
    ($_POST['return_page']??'dashboard')
);