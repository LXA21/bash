DROP DATABASE IF EXISTS sistema_facturacion;
CREATE DATABASE sistema_facturacion
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE sistema_facturacion;

-- ============================================================
-- CREACIÓN DE USUARIO MYSQL Y PERMISOS (Para phpMyAdmin y PHP)
-- ============================================================
CREATE USER IF NOT EXISTS 'comanda'@'%' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO 'comanda'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- ============================================================
-- 1. ROLES
-- ============================================================
CREATE TABLE roles (
    id_rol INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(255),
    activo BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

-- ============================================================
-- 2. USUARIOS
-- NOTA: password debe almacenarse como HASH desde el backend.
-- ============================================================
CREATE TABLE usuarios (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    id_rol INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    usuario VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_usuario_rol
        FOREIGN KEY (id_rol) REFERENCES roles(id_rol)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ============================================================
-- 3. CATEGORIAS
-- ============================================================
CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion VARCHAR(255),
    activo BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

-- ============================================================
-- 4. PRODUCTOS
-- ============================================================
CREATE TABLE productos (
    id_producto INT AUTO_INCREMENT PRIMARY KEY,
    id_categoria INT NULL,
    codigo VARCHAR(50) NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    descripcion TEXT,
    precio_compra DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    precio_venta DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    costo_promedio DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    stock_actual DECIMAL(12,3) NOT NULL DEFAULT 0.000,
    stock_minimo DECIMAL(12,3) NOT NULL DEFAULT 0.000,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_producto_precios
        CHECK (precio_compra >= 0 AND precio_venta >= 0
               AND costo_promedio >= 0),

    CONSTRAINT chk_producto_stock
        CHECK (stock_actual >= 0 AND stock_minimo >= 0),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
        ON UPDATE CASCADE
        ON DELETE SET NULL
) ENGINE=InnoDB;

-- ============================================================
-- 5. CLIENTES
-- ============================================================
CREATE TABLE clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    documento VARCHAR(50),
    telefono VARCHAR(30),
    correo VARCHAR(100),
    direccion VARCHAR(255),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE INDEX idx_clientes_nombre ON clientes(nombre);
CREATE INDEX idx_clientes_documento ON clientes(documento);

-- ============================================================
-- 6. PROVEEDORES
-- ============================================================
CREATE TABLE proveedores (
    id_proveedor INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    documento VARCHAR(50),
    telefono VARCHAR(30),
    correo VARCHAR(100),
    direccion VARCHAR(255),
    contacto VARCHAR(100),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE INDEX idx_proveedores_nombre ON proveedores(nombre);
CREATE INDEX idx_proveedores_documento ON proveedores(documento);

-- ============================================================
-- 7. MONEDAS
-- Permite agregar monedas nuevas desde el sistema.
-- Ejemplos: USD, EUR, VES, COP, CAD, etc.
-- ============================================================
CREATE TABLE monedas (
    id_moneda INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(10) NOT NULL UNIQUE,
    nombre VARCHAR(50) NOT NULL,
    simbolo VARCHAR(10) NOT NULL,
    tasa_referencia DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
    es_moneda_base BOOLEAN NOT NULL DEFAULT FALSE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_moneda_tasa
        CHECK (tasa_referencia > 0)
) ENGINE=InnoDB;

-- ============================================================
-- 8. METODOS DE PAGO
-- Cada método puede estar asociado a una moneda.
-- Así puedes tener, por ejemplo:
-- Efectivo USD
-- Efectivo VES
-- Transferencia USD
-- Transferencia VES
-- Tarjeta
-- Otra moneda
--
-- tipo_pago: EFECTIVO, TRANSFERENCIA, TARJETA, OTRO
-- ============================================================
CREATE TABLE metodos_pago (
    id_metodo_pago INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    tipo_pago ENUM(
        'EFECTIVO',
        'TRANSFERENCIA',
        'TARJETA',
        'OTRO'
    ) NOT NULL DEFAULT 'EFECTIVO',
    id_moneda INT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_metodo_moneda
        UNIQUE (nombre, id_moneda),

    CONSTRAINT fk_metodo_moneda
        FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ============================================================
-- 9. VENTAS / FACTURAS
-- ============================================================
CREATE TABLE ventas (
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    numero_factura VARCHAR(50) NOT NULL UNIQUE,
    id_cliente INT NULL,
    id_usuario INT NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    subtotal DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    descuento DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    impuesto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total DECIMAL(12,2) NOT NULL DEFAULT 0.00,

    id_moneda INT NOT NULL,
    tipo_cambio DECIMAL(18,6) NOT NULL DEFAULT 1.000000,

    estado ENUM(
        'PENDIENTE',
        'COMPLETADA',
        'ANULADA'
    ) NOT NULL DEFAULT 'COMPLETADA',

    observaciones VARCHAR(255),

    CONSTRAINT chk_venta_montos
        CHECK (subtotal >= 0 AND descuento >= 0
               AND impuesto >= 0 AND total >= 0),

    CONSTRAINT chk_venta_tipo_cambio
        CHECK (tipo_cambio > 0),

    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_venta_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_venta_moneda
        FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_ventas_fecha ON ventas(fecha);
CREATE INDEX idx_ventas_cliente ON ventas(id_cliente);
CREATE INDEX idx_ventas_estado ON ventas(estado);

-- ============================================================
-- 10. DETALLE DE VENTAS
-- Guarda el costo histórico del producto para calcular
-- correctamente la ganancia de cada venta.
-- ============================================================
CREATE TABLE detalle_ventas (
    id_detalle_venta INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad DECIMAL(12,3) NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,
    costo_unitario DECIMAL(12,2) NOT NULL,
    descuento DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    subtotal DECIMAL(12,2) NOT NULL,

    CONSTRAINT chk_detalle_venta_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT chk_detalle_venta_precios
        CHECK (precio_unitario >= 0 AND costo_unitario >= 0
               AND descuento >= 0 AND subtotal >= 0),

    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_detalle_venta_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_detalle_ventas_venta ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_ventas_producto ON detalle_ventas(id_producto);

-- ============================================================
-- 11. PAGOS DE VENTAS
-- Permite que una venta pueda pagarse con uno o varios
-- métodos/monedas.
-- Ejemplo:
-- Total $100
-- $60 efectivo USD
-- $40 transferencia USD
--
-- También permite:
-- $50 USD + equivalente en otra moneda.
-- ============================================================
CREATE TABLE pagos_ventas (
    id_pago_venta INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    id_metodo_pago INT NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    tipo_cambio DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
    monto_moneda_base DECIMAL(12,2) NOT NULL,
    referencia VARCHAR(100),
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_pago_venta_monto
        CHECK (monto > 0 AND tipo_cambio > 0
               AND monto_moneda_base > 0),

    CONSTRAINT fk_pago_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_pago_venta_metodo
        FOREIGN KEY (id_metodo_pago) REFERENCES metodos_pago(id_metodo_pago)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_pagos_ventas_venta ON pagos_ventas(id_venta);

-- ============================================================
-- 12. COMPRAS
-- Registra la factura del proveedor.
-- ============================================================
CREATE TABLE compras (
    id_compra INT AUTO_INCREMENT PRIMARY KEY,
    numero_factura VARCHAR(50) NOT NULL UNIQUE,
    id_proveedor INT NOT NULL,
    id_usuario INT NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    subtotal DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    descuento DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    impuesto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total DECIMAL(12,2) NOT NULL DEFAULT 0.00,

    id_moneda INT NOT NULL,
    tipo_cambio DECIMAL(18,6) NOT NULL DEFAULT 1.000000,

    estado ENUM(
        'PENDIENTE',
        'COMPLETADA',
        'ANULADA'
    ) NOT NULL DEFAULT 'COMPLETADA',

    observaciones VARCHAR(255),

    CONSTRAINT chk_compra_montos
        CHECK (subtotal >= 0 AND descuento >= 0
               AND impuesto >= 0 AND total >= 0),

    CONSTRAINT chk_compra_tipo_cambio
        CHECK (tipo_cambio > 0),

    CONSTRAINT fk_compra_proveedor
        FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_compra_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_compra_moneda
        FOREIGN KEY (id_moneda) REFERENCES monedas(id_moneda)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_compras_fecha ON compras(fecha);
CREATE INDEX idx_compras_proveedor ON compras(id_proveedor);
CREATE INDEX idx_compras_estado ON compras(estado);

-- ============================================================
-- 13. DETALLE DE COMPRAS
-- Aquí queda guardado el precio real pagado al proveedor.
-- ============================================================
CREATE TABLE detalle_compras (
    id_detalle_compra INT AUTO_INCREMENT PRIMARY KEY,
    id_compra INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad DECIMAL(12,3) NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,
    descuento DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    subtotal DECIMAL(12,2) NOT NULL,

    CONSTRAINT chk_detalle_compra_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT chk_detalle_compra_precios
        CHECK (precio_unitario >= 0 AND descuento >= 0
               AND subtotal >= 0),

    CONSTRAINT fk_detalle_compra
        FOREIGN KEY (id_compra) REFERENCES compras(id_compra)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_detalle_compra_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_detalle_compras_compra ON detalle_compras(id_compra);
CREATE INDEX idx_detalle_compras_producto ON detalle_compras(id_producto);

-- ============================================================
-- 14. MOVIMIENTOS DE INVENTARIO
-- Toda entrada/salida debe quedar registrada aquí.
-- ============================================================
CREATE TABLE movimientos_inventario (
    id_movimiento INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,

    tipo_movimiento ENUM(
        'ENTRADA_COMPRA',
        'SALIDA_VENTA',
        'ENTRADA_DEVOLUCION',
        'SALIDA_DEVOLUCION',
        'AJUSTE_ENTRADA',
        'AJUSTE_SALIDA'
    ) NOT NULL,

    cantidad DECIMAL(12,3) NOT NULL,
    stock_anterior DECIMAL(12,3) NOT NULL,
    stock_nuevo DECIMAL(12,3) NOT NULL,
    costo_unitario DECIMAL(12,2) NOT NULL DEFAULT 0.00,

    id_compra INT NULL,
    id_detalle_compra INT NULL,
    id_venta INT NULL,
    id_detalle_venta INT NULL,
    id_usuario INT NOT NULL,

    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observaciones VARCHAR(255),

    CONSTRAINT chk_movimiento_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT chk_movimiento_stock
        CHECK (stock_anterior >= 0 AND stock_nuevo >= 0),

    CONSTRAINT chk_movimiento_costo
        CHECK (costo_unitario >= 0),

    CONSTRAINT fk_mov_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    CONSTRAINT fk_mov_compra
        FOREIGN KEY (id_compra) REFERENCES compras(id_compra)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_mov_detalle_compra
        FOREIGN KEY (id_detalle_compra) REFERENCES detalle_compras(id_detalle_compra)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_mov_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_mov_detalle_venta
        FOREIGN KEY (id_detalle_venta) REFERENCES detalle_ventas(id_detalle_venta)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT fk_mov_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_mov_producto_fecha
    ON movimientos_inventario(id_producto, fecha);

CREATE INDEX idx_mov_tipo
    ON movimientos_inventario(tipo_movimiento);

-- ============================================================
-- 15. RESPALDOS
-- Guarda información del respaldo; el archivo real .sql
-- debe almacenarse fuera de MySQL.
-- ============================================================
CREATE TABLE respaldos (
    id_respaldo INT AUTO_INCREMENT PRIMARY KEY,
    nombre_archivo VARCHAR(255) NOT NULL,
    ruta_archivo VARCHAR(500),
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo ENUM('MANUAL','AUTOMATICO') NOT NULL,
    tamano BIGINT,
    estado ENUM('EXITOSO','FALLIDO') NOT NULL,
    id_usuario INT NULL,

    CONSTRAINT fk_respaldo_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
        ON UPDATE CASCADE
        ON DELETE SET NULL
) ENGINE=InnoDB;

-- ============================================================
-- DATOS INICIALES
-- ============================================================

-- Roles
INSERT INTO roles (nombre, descripcion) VALUES
('Administrador', 'Acceso completo al sistema'),
('Vendedor', 'Registro y consulta de ventas'),
('Inventario', 'Gestión de productos e inventario');

-- Moneda base y monedas iniciales
INSERT INTO monedas
(codigo, nombre, simbolo, tasa_referencia, es_moneda_base)
VALUES
('USD', 'Dólar estadounidense', '$', 1.000000, TRUE),
('EUR', 'Euro', '€', 1.000000, FALSE),
('VES', 'Bolívar venezolano', 'Bs.', 1.000000, FALSE),
('COP', 'Peso colombiano', '$', 1.000000, FALSE),
('CAD', 'Dólar canadiense', 'C$', 1.000000, FALSE);

-- Métodos de pago iniciales
INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Efectivo USD', 'EFECTIVO', id_moneda
FROM monedas WHERE codigo = 'USD';

INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Transferencia USD', 'TRANSFERENCIA', id_moneda
FROM monedas WHERE codigo = 'USD';

INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Tarjeta USD', 'TARJETA', id_moneda
FROM monedas WHERE codigo = 'USD';

INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Efectivo EUR', 'EFECTIVO', id_moneda
FROM monedas WHERE codigo = 'EUR';

INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Efectivo VES', 'EFECTIVO', id_moneda
FROM monedas WHERE codigo = 'VES';

INSERT INTO metodos_pago (nombre, tipo_pago, id_moneda)
SELECT 'Transferencia VES', 'TRANSFERENCIA', id_moneda
FROM monedas WHERE codigo = 'VES';

-- Categorías de ejemplo
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Productos electrónicos'),
('Accesorios', 'Accesorios para dispositivos'),
('Hogar', 'Productos para el hogar'),
('Otros', 'Productos generales');

-- Cliente general
INSERT INTO clientes (nombre, documento)
VALUES ('Consumidor Final', '99999999');

-- ============================================================
-- VISTAS ÚTILES
-- ============================================================

-- Vista de productos con categoría y estado de stock
CREATE VIEW vista_inventario AS
SELECT
    p.id_producto,
    p.codigo,
    p.nombre,
    c.nombre AS categoria,
    p.precio_compra,
    p.precio_venta,
    p.costo_promedio,
    p.stock_actual,
    p.stock_minimo,
    CASE
        WHEN p.stock_actual = 0 THEN 'AGOTADO'
        WHEN p.stock_actual <= p.stock_minimo THEN 'STOCK BAJO'
        ELSE 'DISPONIBLE'
    END AS estado_stock
FROM productos p
LEFT JOIN categorias c
    ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE;

-- Vista de ganancias por producto vendido
CREATE VIEW vista_ganancias_ventas AS
SELECT
    v.id_venta,
    v.numero_factura,
    v.fecha,
    p.id_producto,
    p.codigo,
    p.nombre AS producto,
    dv.cantidad,
    dv.precio_unitario,
    dv.costo_unitario,
    (dv.precio_unitario - dv.costo_unitario) * dv.cantidad
        AS ganancia_bruta,
    dv.subtotal
FROM ventas v
INNER JOIN detalle_ventas dv
    ON v.id_venta = dv.id_venta
INNER JOIN productos p
    ON dv.id_producto = p.id_producto
WHERE v.estado = 'COMPLETADA';

-- Vista de compras con proveedor
CREATE VIEW vista_compras AS
SELECT
    c.id_compra,
    c.numero_factura,
    c.fecha,
    pr.nombre AS proveedor,
    m.codigo AS moneda,
    c.subtotal,
    c.descuento,
    c.impuesto,
    c.total,
    c.estado
FROM compras c
INNER JOIN proveedores pr
    ON c.id_proveedor = pr.id_proveedor
INNER JOIN monedas m
    ON c.id_moneda = m.id_moneda;

-- ============================================================
-- CONSULTAS DE COMPROBACIÓN
-- ============================================================

-- Ver tablas creadas:
SHOW TABLES;

-- Ver monedas:
SELECT * FROM monedas;

-- Ver métodos de pago:
SELECT
    mp.id_metodo_pago,
    mp.nombre AS metodo_pago,
    mp.tipo_pago,
    m.codigo AS moneda,
    m.simbolo
FROM metodos_pago mp
INNER JOIN monedas m
    ON mp.id_moneda = m.id_moneda;

-- Ver productos e inventario:
SELECT * FROM vista_inventario;

-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================