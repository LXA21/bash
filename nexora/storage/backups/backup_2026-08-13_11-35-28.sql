-- Mi Tienda backup
SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS `categorias`;
CREATE TABLE `categorias` (
  `id_categoria` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id_categoria`),
  UNIQUE KEY `nombre` (`nombre`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `categorias` (`id_categoria`,`nombre`,`descripcion`,`activo`) VALUES ('1','Electrónica','Productos electrónicos','1');
INSERT INTO `categorias` (`id_categoria`,`nombre`,`descripcion`,`activo`) VALUES ('2','Accesorios','Accesorios para dispositivos','1');
INSERT INTO `categorias` (`id_categoria`,`nombre`,`descripcion`,`activo`) VALUES ('3','Hogar','Productos para el hogar','1');
INSERT INTO `categorias` (`id_categoria`,`nombre`,`descripcion`,`activo`) VALUES ('4','Otros','Productos generales','1');
DROP TABLE IF EXISTS `clientes`;
CREATE TABLE `clientes` (
  `id_cliente` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `documento` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `telefono` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `correo` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `direccion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_cliente`),
  KEY `idx_clientes_nombre` (`nombre`),
  KEY `idx_clientes_documento` (`documento`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `clientes` (`id_cliente`,`nombre`,`documento`,`telefono`,`correo`,`direccion`,`activo`,`fecha_creacion`) VALUES ('1','Consumidor Final','99999999',NULL,NULL,NULL,'1','2026-08-12 14:37:35');
INSERT INTO `clientes` (`id_cliente`,`nombre`,`documento`,`telefono`,`correo`,`direccion`,`activo`,`fecha_creacion`) VALUES ('2','arianna','31727273','041677777','','','1','2026-08-13 11:17:04');
DROP TABLE IF EXISTS `compras`;
CREATE TABLE `compras` (
  `id_compra` int NOT NULL AUTO_INCREMENT,
  `numero_factura` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `id_proveedor` int NOT NULL,
  `id_usuario` int NOT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `subtotal` decimal(12,2) NOT NULL DEFAULT '0.00',
  `descuento` decimal(12,2) NOT NULL DEFAULT '0.00',
  `impuesto` decimal(12,2) NOT NULL DEFAULT '0.00',
  `total` decimal(12,2) NOT NULL DEFAULT '0.00',
  `id_moneda` int NOT NULL,
  `tipo_cambio` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `estado` enum('PENDIENTE','COMPLETADA','ANULADA') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'COMPLETADA',
  `observaciones` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id_compra`),
  UNIQUE KEY `numero_factura` (`numero_factura`),
  KEY `fk_compra_usuario` (`id_usuario`),
  KEY `fk_compra_moneda` (`id_moneda`),
  KEY `idx_compras_fecha` (`fecha`),
  KEY `idx_compras_proveedor` (`id_proveedor`),
  KEY `idx_compras_estado` (`estado`),
  CONSTRAINT `fk_compra_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_compra_proveedor` FOREIGN KEY (`id_proveedor`) REFERENCES `proveedores` (`id_proveedor`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_compra_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `chk_compra_montos` CHECK (((`subtotal` >= 0) and (`descuento` >= 0) and (`impuesto` >= 0) and (`total` >= 0))),
  CONSTRAINT `chk_compra_tipo_cambio` CHECK ((`tipo_cambio` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `detalle_compras`;
CREATE TABLE `detalle_compras` (
  `id_detalle_compra` int NOT NULL AUTO_INCREMENT,
  `id_compra` int NOT NULL,
  `id_producto` int NOT NULL,
  `cantidad` decimal(12,3) NOT NULL,
  `precio_unitario` decimal(12,2) NOT NULL,
  `descuento` decimal(12,2) NOT NULL DEFAULT '0.00',
  `subtotal` decimal(12,2) NOT NULL,
  PRIMARY KEY (`id_detalle_compra`),
  KEY `idx_detalle_compras_compra` (`id_compra`),
  KEY `idx_detalle_compras_producto` (`id_producto`),
  CONSTRAINT `fk_detalle_compra` FOREIGN KEY (`id_compra`) REFERENCES `compras` (`id_compra`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_detalle_compra_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `chk_detalle_compra_cantidad` CHECK ((`cantidad` > 0)),
  CONSTRAINT `chk_detalle_compra_precios` CHECK (((`precio_unitario` >= 0) and (`descuento` >= 0) and (`subtotal` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `detalle_ventas`;
CREATE TABLE `detalle_ventas` (
  `id_detalle_venta` int NOT NULL AUTO_INCREMENT,
  `id_venta` int NOT NULL,
  `id_producto` int NOT NULL,
  `cantidad` decimal(12,3) NOT NULL,
  `precio_unitario` decimal(12,2) NOT NULL,
  `costo_unitario` decimal(12,2) NOT NULL,
  `descuento` decimal(12,2) NOT NULL DEFAULT '0.00',
  `subtotal` decimal(12,2) NOT NULL,
  PRIMARY KEY (`id_detalle_venta`),
  KEY `idx_detalle_ventas_venta` (`id_venta`),
  KEY `idx_detalle_ventas_producto` (`id_producto`),
  CONSTRAINT `fk_detalle_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_detalle_venta_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `chk_detalle_venta_cantidad` CHECK ((`cantidad` > 0)),
  CONSTRAINT `chk_detalle_venta_precios` CHECK (((`precio_unitario` >= 0) and (`costo_unitario` >= 0) and (`descuento` >= 0) and (`subtotal` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `metodos_pago`;
CREATE TABLE `metodos_pago` (
  `id_metodo_pago` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `tipo_pago` enum('EFECTIVO','TRANSFERENCIA','TARJETA','OTRO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'EFECTIVO',
  `id_moneda` int NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_metodo_pago`),
  UNIQUE KEY `uq_metodo_moneda` (`nombre`,`id_moneda`),
  KEY `fk_metodo_moneda` (`id_moneda`),
  CONSTRAINT `fk_metodo_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('1','Efectivo USD','EFECTIVO','1','1','2026-08-12 14:37:35');
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('2','Transferencia USD','TRANSFERENCIA','1','1','2026-08-12 14:37:35');
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('3','Tarjeta USD','TARJETA','1','1','2026-08-12 14:37:35');
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('4','Efectivo EUR','EFECTIVO','2','1','2026-08-12 14:37:35');
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('5','Efectivo VES','EFECTIVO','3','1','2026-08-12 14:37:35');
INSERT INTO `metodos_pago` (`id_metodo_pago`,`nombre`,`tipo_pago`,`id_moneda`,`activo`,`fecha_creacion`) VALUES ('6','Transferencia VES','TRANSFERENCIA','3','1','2026-08-12 14:37:35');
DROP TABLE IF EXISTS `monedas`;
CREATE TABLE `monedas` (
  `id_moneda` int NOT NULL AUTO_INCREMENT,
  `codigo` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `simbolo` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `tasa_referencia` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `es_moneda_base` tinyint(1) NOT NULL DEFAULT '0',
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_moneda`),
  UNIQUE KEY `codigo` (`codigo`),
  CONSTRAINT `chk_moneda_tasa` CHECK ((`tasa_referencia` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `monedas` (`id_moneda`,`codigo`,`nombre`,`simbolo`,`tasa_referencia`,`es_moneda_base`,`activo`,`fecha_creacion`) VALUES ('1','USD','Dólar estadounidense','$','1.000000','1','1','2026-08-12 14:37:35');
INSERT INTO `monedas` (`id_moneda`,`codigo`,`nombre`,`simbolo`,`tasa_referencia`,`es_moneda_base`,`activo`,`fecha_creacion`) VALUES ('2','EUR','Euro','€','1.000000','0','1','2026-08-12 14:37:35');
INSERT INTO `monedas` (`id_moneda`,`codigo`,`nombre`,`simbolo`,`tasa_referencia`,`es_moneda_base`,`activo`,`fecha_creacion`) VALUES ('3','VES','Bolívar venezolano','Bs.','1.000000','0','1','2026-08-12 14:37:35');
INSERT INTO `monedas` (`id_moneda`,`codigo`,`nombre`,`simbolo`,`tasa_referencia`,`es_moneda_base`,`activo`,`fecha_creacion`) VALUES ('4','COP','Peso colombiano','$','1.000000','0','1','2026-08-12 14:37:35');
INSERT INTO `monedas` (`id_moneda`,`codigo`,`nombre`,`simbolo`,`tasa_referencia`,`es_moneda_base`,`activo`,`fecha_creacion`) VALUES ('5','CAD','Dólar canadiense','C$','1.000000','0','1','2026-08-12 14:37:35');
DROP TABLE IF EXISTS `movimientos_inventario`;
CREATE TABLE `movimientos_inventario` (
  `id_movimiento` int NOT NULL AUTO_INCREMENT,
  `id_producto` int NOT NULL,
  `tipo_movimiento` enum('ENTRADA_COMPRA','SALIDA_VENTA','ENTRADA_DEVOLUCION','SALIDA_DEVOLUCION','AJUSTE_ENTRADA','AJUSTE_SALIDA') COLLATE utf8mb4_unicode_ci NOT NULL,
  `cantidad` decimal(12,3) NOT NULL,
  `stock_anterior` decimal(12,3) NOT NULL,
  `stock_nuevo` decimal(12,3) NOT NULL,
  `costo_unitario` decimal(12,2) NOT NULL DEFAULT '0.00',
  `id_compra` int DEFAULT NULL,
  `id_detalle_compra` int DEFAULT NULL,
  `id_venta` int DEFAULT NULL,
  `id_detalle_venta` int DEFAULT NULL,
  `id_usuario` int NOT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `observaciones` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id_movimiento`),
  KEY `fk_mov_compra` (`id_compra`),
  KEY `fk_mov_detalle_compra` (`id_detalle_compra`),
  KEY `fk_mov_venta` (`id_venta`),
  KEY `fk_mov_detalle_venta` (`id_detalle_venta`),
  KEY `fk_mov_usuario` (`id_usuario`),
  KEY `idx_mov_producto_fecha` (`id_producto`,`fecha`),
  KEY `idx_mov_tipo` (`tipo_movimiento`),
  CONSTRAINT `fk_mov_compra` FOREIGN KEY (`id_compra`) REFERENCES `compras` (`id_compra`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_mov_detalle_compra` FOREIGN KEY (`id_detalle_compra`) REFERENCES `detalle_compras` (`id_detalle_compra`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_mov_detalle_venta` FOREIGN KEY (`id_detalle_venta`) REFERENCES `detalle_ventas` (`id_detalle_venta`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_mov_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_mov_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_mov_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `chk_movimiento_cantidad` CHECK ((`cantidad` > 0)),
  CONSTRAINT `chk_movimiento_costo` CHECK ((`costo_unitario` >= 0)),
  CONSTRAINT `chk_movimiento_stock` CHECK (((`stock_anterior` >= 0) and (`stock_nuevo` >= 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `pagos_ventas`;
CREATE TABLE `pagos_ventas` (
  `id_pago_venta` int NOT NULL AUTO_INCREMENT,
  `id_venta` int NOT NULL,
  `id_metodo_pago` int NOT NULL,
  `monto` decimal(12,2) NOT NULL,
  `tipo_cambio` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `monto_moneda_base` decimal(12,2) NOT NULL,
  `referencia` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_pago_venta`),
  KEY `fk_pago_venta_metodo` (`id_metodo_pago`),
  KEY `idx_pagos_ventas_venta` (`id_venta`),
  CONSTRAINT `fk_pago_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_pago_venta_metodo` FOREIGN KEY (`id_metodo_pago`) REFERENCES `metodos_pago` (`id_metodo_pago`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `chk_pago_venta_monto` CHECK (((`monto` > 0) and (`tipo_cambio` > 0) and (`monto_moneda_base` > 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `productos`;
CREATE TABLE `productos` (
  `id_producto` int NOT NULL AUTO_INCREMENT,
  `id_categoria` int DEFAULT NULL,
  `codigo` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nombre` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` text COLLATE utf8mb4_unicode_ci,
  `precio_compra` decimal(12,2) NOT NULL DEFAULT '0.00',
  `precio_venta` decimal(12,2) NOT NULL DEFAULT '0.00',
  `costo_promedio` decimal(12,2) NOT NULL DEFAULT '0.00',
  `stock_actual` decimal(12,3) NOT NULL DEFAULT '0.000',
  `stock_minimo` decimal(12,3) NOT NULL DEFAULT '0.000',
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_producto`),
  UNIQUE KEY `codigo` (`codigo`),
  KEY `fk_producto_categoria` (`id_categoria`),
  CONSTRAINT `fk_producto_categoria` FOREIGN KEY (`id_categoria`) REFERENCES `categorias` (`id_categoria`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `chk_producto_precios` CHECK (((`precio_compra` >= 0) and (`precio_venta` >= 0) and (`costo_promedio` >= 0))),
  CONSTRAINT `chk_producto_stock` CHECK (((`stock_actual` >= 0) and (`stock_minimo` >= 0)))
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `productos` (`id_producto`,`id_categoria`,`codigo`,`nombre`,`descripcion`,`precio_compra`,`precio_venta`,`costo_promedio`,`stock_actual`,`stock_minimo`,`activo`,`fecha_creacion`) VALUES ('1','1','MP003','arroz marquez',NULL,'15.00','20.00','15.00','15.000','4.000','1','2026-08-13 10:56:34');
DROP TABLE IF EXISTS `proveedores`;
CREATE TABLE `proveedores` (
  `id_proveedor` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `documento` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `telefono` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `correo` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `direccion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `contacto` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_proveedor`),
  KEY `idx_proveedores_nombre` (`nombre`),
  KEY `idx_proveedores_documento` (`documento`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `respaldos`;
CREATE TABLE `respaldos` (
  `id_respaldo` int NOT NULL AUTO_INCREMENT,
  `nombre_archivo` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ruta_archivo` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `tipo` enum('MANUAL','AUTOMATICO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `tamano` bigint DEFAULT NULL,
  `estado` enum('EXITOSO','FALLIDO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `id_usuario` int DEFAULT NULL,
  PRIMARY KEY (`id_respaldo`),
  KEY `fk_respaldo_usuario` (`id_usuario`),
  CONSTRAINT `fk_respaldo_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `roles`;
CREATE TABLE `roles` (
  `id_rol` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id_rol`),
  UNIQUE KEY `nombre` (`nombre`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `roles` (`id_rol`,`nombre`,`descripcion`,`activo`) VALUES ('1','Administrador','Acceso completo al sistema','1');
INSERT INTO `roles` (`id_rol`,`nombre`,`descripcion`,`activo`) VALUES ('2','Vendedor','Registro y consulta de ventas','1');
INSERT INTO `roles` (`id_rol`,`nombre`,`descripcion`,`activo`) VALUES ('3','Inventario','Gestión de productos e inventario','1');
DROP TABLE IF EXISTS `usuarios`;
CREATE TABLE `usuarios` (
  `id_usuario` int NOT NULL AUTO_INCREMENT,
  `id_rol` int NOT NULL,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `usuario` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_usuario`),
  UNIQUE KEY `usuario` (`usuario`),
  KEY `fk_usuario_rol` (`id_rol`),
  CONSTRAINT `fk_usuario_rol` FOREIGN KEY (`id_rol`) REFERENCES `roles` (`id_rol`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `usuarios` (`id_usuario`,`id_rol`,`nombre`,`usuario`,`password`,`activo`,`fecha_creacion`) VALUES ('1','1','arianna','ari','$2y$10$7WSe8i60YujLEX2i3DLPc.sWkgLPqXCsdzaMLPpFBZTjBO7ZLP9UW','1','2026-08-12 16:55:25');
DROP TABLE IF EXISTS `ventas`;
CREATE TABLE `ventas` (
  `id_venta` int NOT NULL AUTO_INCREMENT,
  `numero_factura` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `id_cliente` int DEFAULT NULL,
  `id_usuario` int NOT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `subtotal` decimal(12,2) NOT NULL DEFAULT '0.00',
  `descuento` decimal(12,2) NOT NULL DEFAULT '0.00',
  `impuesto` decimal(12,2) NOT NULL DEFAULT '0.00',
  `total` decimal(12,2) NOT NULL DEFAULT '0.00',
  `id_moneda` int NOT NULL,
  `tipo_cambio` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `estado` enum('PENDIENTE','COMPLETADA','ANULADA') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'COMPLETADA',
  `observaciones` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id_venta`),
  UNIQUE KEY `numero_factura` (`numero_factura`),
  KEY `fk_venta_usuario` (`id_usuario`),
  KEY `fk_venta_moneda` (`id_moneda`),
  KEY `idx_ventas_fecha` (`fecha`),
  KEY `idx_ventas_cliente` (`id_cliente`),
  KEY `idx_ventas_estado` (`estado`),
  CONSTRAINT `fk_venta_cliente` FOREIGN KEY (`id_cliente`) REFERENCES `clientes` (`id_cliente`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_venta_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `fk_venta_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT `chk_venta_montos` CHECK (((`subtotal` >= 0) and (`descuento` >= 0) and (`impuesto` >= 0) and (`total` >= 0))),
  CONSTRAINT `chk_venta_tipo_cambio` CHECK ((`tipo_cambio` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `vista_compras`;
;
DROP TABLE IF EXISTS `vista_ganancias_ventas`;
;
DROP TABLE IF EXISTS `vista_inventario`;
;
INSERT INTO `vista_inventario` (`id_producto`,`codigo`,`nombre`,`categoria`,`precio_compra`,`precio_venta`,`costo_promedio`,`stock_actual`,`stock_minimo`,`estado_stock`) VALUES ('1','MP003','arroz marquez','Electrónica','15.00','20.00','15.00','15.000','4.000','DISPONIBLE');
SET FOREIGN_KEY_CHECKS=1;
