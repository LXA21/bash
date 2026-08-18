# Mi Tienda - Sistema de Facturación PHP/MySQL

## Instalación en WAMP
1. Copia la carpeta a `C:\wamp64\www\mi_tienda`.
2. Abre WAMP y espera el icono verde.
3. Entra a `http://localhost/phpmyadmin`.
4. Importa `database.sql`.
5. Revisa `config.php` si tu usuario root tiene contraseña.
6. Abre `http://localhost/mi_tienda/install.php`.
7. Entra con `admin / admin123`.
8. Elimina `install.php` después de crear el administrador.

## Módulos
Dashboard, Productos, Inventario, Ventas, Facturación, Clientes, Compras, Proveedores, Métodos de pago/Monedas, Reportes, Respaldos, Usuarios y Configuración.

## Flujo
Compra -> aumenta stock y recalcula costo promedio.
Venta -> valida stock, guarda costo histórico, descuenta stock, registra movimiento y factura.
Anulación -> restaura el stock.
