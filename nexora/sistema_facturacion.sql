-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1:3306
-- Tiempo de generación: 18-08-2026 a las 15:04:01
-- Versión del servidor: 8.4.7
-- Versión de PHP: 8.3.28

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `sistema_facturacion`
--

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `categorias`
--

DROP TABLE IF EXISTS `categorias`;
CREATE TABLE IF NOT EXISTS `categorias` (
  `id_categoria` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id_categoria`),
  UNIQUE KEY `nombre` (`nombre`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `categorias`
--

INSERT INTO `categorias` (`id_categoria`, `nombre`, `descripcion`, `activo`) VALUES
(1, 'Electrónica', 'Productos electrónicos', 1),
(2, 'Accesorios', 'Accesorios para dispositivos', 1),
(3, 'Hogar', 'Productos para el hogar', 1),
(4, 'Otros', 'Productos generales', 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `clientes`
--

DROP TABLE IF EXISTS `clientes`;
CREATE TABLE IF NOT EXISTS `clientes` (
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
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `clientes`
--

INSERT INTO `clientes` (`id_cliente`, `nombre`, `documento`, `telefono`, `correo`, `direccion`, `activo`, `fecha_creacion`) VALUES
(1, 'Consumidor Final', '99999999', NULL, NULL, NULL, 0, '2026-08-12 14:37:35'),
(2, 'arianna', '31727273', '041677777', '', '', 0, '2026-08-13 11:17:04'),
(3, 'kelvin', '31727273', '2838374', 'kelvin@gmail.com', 'La San Juana', 1, '2026-08-15 18:14:08');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `compras`
--

DROP TABLE IF EXISTS `compras`;
CREATE TABLE IF NOT EXISTS `compras` (
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
  KEY `idx_compras_estado` (`estado`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_compras`
--

DROP TABLE IF EXISTS `detalle_compras`;
CREATE TABLE IF NOT EXISTS `detalle_compras` (
  `id_detalle_compra` int NOT NULL AUTO_INCREMENT,
  `id_compra` int NOT NULL,
  `id_producto` int NOT NULL,
  `cantidad` decimal(12,3) NOT NULL,
  `precio_unitario` decimal(12,2) NOT NULL,
  `descuento` decimal(12,2) NOT NULL DEFAULT '0.00',
  `subtotal` decimal(12,2) NOT NULL,
  PRIMARY KEY (`id_detalle_compra`),
  KEY `idx_detalle_compras_compra` (`id_compra`),
  KEY `idx_detalle_compras_producto` (`id_producto`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_ventas`
--

DROP TABLE IF EXISTS `detalle_ventas`;
CREATE TABLE IF NOT EXISTS `detalle_ventas` (
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
  KEY `idx_detalle_ventas_producto` (`id_producto`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `detalle_ventas`
--

INSERT INTO `detalle_ventas` (`id_detalle_venta`, `id_venta`, `id_producto`, `cantidad`, `precio_unitario`, `costo_unitario`, `descuento`, `subtotal`) VALUES
(1, 1, 1, 1.000, 20.00, 15.00, 0.00, 20.00),
(2, 2, 2, 1.000, 15.00, 10.00, 0.00, 15.00),
(3, 3, 3, 1.000, 8.00, 4.00, 0.00, 8.00),
(4, 4, 4, 1.000, 17.00, 12.00, 0.00, 17.00),
(5, 5, 4, 2.000, 17.00, 12.00, 0.00, 34.00),
(6, 6, 3, 1.000, 8.00, 4.00, 0.00, 8.00),
(7, 7, 2, 5.000, 15.00, 10.00, 0.00, 75.00),
(8, 8, 4, 5.000, 17.00, 12.00, 0.00, 85.00),
(9, 9, 3, 5.000, 8.00, 4.00, 0.00, 40.00),
(10, 10, 4, 3.000, 17.00, 12.00, 0.00, 51.00),
(11, 11, 2, 1.000, 15.00, 10.00, 0.00, 15.00),
(12, 11, 3, 3.000, 8.00, 4.00, 0.00, 24.00),
(13, 11, 4, 3.000, 17.00, 12.00, 0.00, 51.00),
(14, 12, 2, 5.000, 15.00, 10.00, 0.00, 75.00),
(16, 14, 2, 2.000, 15.00, 10.00, 0.00, 30.00),
(18, 15, 2, 2.000, 15.00, 10.00, 0.00, 30.00),
(19, 15, 11, 3.000, 5.00, 4.00, 0.00, 15.00),
(20, 15, 10, 15.000, 5.00, 3.00, 0.00, 75.00),
(21, 15, 4, 5.000, 17.00, 12.00, 0.00, 85.00),
(22, 15, 7, 19.000, 5000.00, 2300.00, 0.00, 95000.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `metodos_pago`
--

DROP TABLE IF EXISTS `metodos_pago`;
CREATE TABLE IF NOT EXISTS `metodos_pago` (
  `id_metodo_pago` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `tipo_pago` enum('EFECTIVO','TRANSFERENCIA','TARJETA','OTRO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'EFECTIVO',
  `id_moneda` int NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_metodo_pago`),
  UNIQUE KEY `uq_metodo_moneda` (`nombre`,`id_moneda`),
  KEY `fk_metodo_moneda` (`id_moneda`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `metodos_pago`
--

INSERT INTO `metodos_pago` (`id_metodo_pago`, `nombre`, `tipo_pago`, `id_moneda`, `activo`, `fecha_creacion`) VALUES
(1, 'Efectivo USD', 'EFECTIVO', 1, 1, '2026-08-12 14:37:35'),
(2, 'Transferencia USD', 'TRANSFERENCIA', 1, 1, '2026-08-12 14:37:35'),
(3, 'Tarjeta USD', 'TARJETA', 1, 1, '2026-08-12 14:37:35'),
(4, 'Efectivo EUR', 'EFECTIVO', 2, 0, '2026-08-12 14:37:35'),
(5, 'Efectivo VES', 'EFECTIVO', 3, 1, '2026-08-12 14:37:35'),
(6, 'Transferencia VES', 'TRANSFERENCIA', 3, 1, '2026-08-12 14:37:35'),
(7, 'Efectivo', 'EFECTIVO', 4, 0, '2026-08-17 22:29:15'),
(8, 'Pesos en Efectivo', 'EFECTIVO', 4, 1, '2026-08-17 22:29:31');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `monedas`
--

DROP TABLE IF EXISTS `monedas`;
CREATE TABLE IF NOT EXISTS `monedas` (
  `id_moneda` int NOT NULL AUTO_INCREMENT,
  `codigo` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `simbolo` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `tasa_referencia` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `es_moneda_base` tinyint(1) NOT NULL DEFAULT '0',
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_moneda`),
  UNIQUE KEY `codigo` (`codigo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `monedas`
--

INSERT INTO `monedas` (`id_moneda`, `codigo`, `nombre`, `simbolo`, `tasa_referencia`, `es_moneda_base`, `activo`, `fecha_creacion`) VALUES
(1, 'USD', 'Dólar estadounidense', '$', 1.000000, 1, 1, '2026-08-12 14:37:35'),
(2, 'EUR', 'Euro', '€', 1.000000, 0, 0, '2026-08-12 14:37:35'),
(3, 'VES', 'Bolívar venezolano', 'Bs.', 0.002000, 0, 1, '2026-08-12 14:37:35'),
(4, 'COP', 'Peso colombiano', '$', 0.000286, 0, 1, '2026-08-12 14:37:35'),
(5, 'CAD', 'Dólar canadiense', 'C$', 1.000000, 0, 0, '2026-08-12 14:37:35'),
(6, 'COD', 'pesos colombianos', '$', 0.000286, 0, 0, '2026-08-17 22:28:49');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `movimientos_inventario`
--

DROP TABLE IF EXISTS `movimientos_inventario`;
CREATE TABLE IF NOT EXISTS `movimientos_inventario` (
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
  KEY `idx_mov_tipo` (`tipo_movimiento`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `movimientos_inventario`
--

INSERT INTO `movimientos_inventario` (`id_movimiento`, `id_producto`, `tipo_movimiento`, `cantidad`, `stock_anterior`, `stock_nuevo`, `costo_unitario`, `id_compra`, `id_detalle_compra`, `id_venta`, `id_detalle_venta`, `id_usuario`, `fecha`, `observaciones`) VALUES
(1, 1, 'SALIDA_VENTA', 1.000, 15.000, 14.000, 15.00, NULL, NULL, 1, 1, 1, '2026-08-13 13:43:50', NULL),
(2, 2, 'SALIDA_VENTA', 1.000, 12.000, 11.000, 10.00, NULL, NULL, 2, 2, 1, '2026-08-13 15:13:10', NULL),
(5, 3, 'SALIDA_VENTA', 1.000, 12.000, 11.000, 4.00, NULL, NULL, 3, 3, 1, '2026-08-13 16:07:26', NULL),
(6, 4, 'SALIDA_VENTA', 1.000, 19.000, 18.000, 12.00, NULL, NULL, 4, 4, 1, '2026-08-13 16:08:02', NULL),
(7, 4, 'SALIDA_VENTA', 2.000, 18.000, 16.000, 12.00, NULL, NULL, 5, 5, 1, '2026-08-13 16:13:37', NULL),
(8, 3, 'SALIDA_VENTA', 1.000, 11.000, 10.000, 4.00, NULL, NULL, 6, 6, 1, '2026-08-13 16:14:11', NULL),
(9, 2, 'SALIDA_VENTA', 5.000, 11.000, 6.000, 10.00, NULL, NULL, 7, 7, 1, '2026-08-13 16:14:37', NULL),
(10, 4, 'SALIDA_VENTA', 5.000, 16.000, 11.000, 12.00, NULL, NULL, 8, 8, 1, '2026-08-13 16:15:04', NULL),
(11, 3, 'SALIDA_VENTA', 5.000, 10.000, 5.000, 4.00, NULL, NULL, 9, 9, 1, '2026-08-13 16:15:38', NULL),
(12, 4, 'SALIDA_VENTA', 3.000, 11.000, 8.000, 12.00, NULL, NULL, 10, 10, 1, '2026-08-13 16:16:02', NULL),
(13, 2, 'SALIDA_VENTA', 1.000, 6.000, 5.000, 10.00, NULL, NULL, 11, 11, 1, '2026-08-13 16:16:52', NULL),
(14, 3, 'SALIDA_VENTA', 3.000, 5.000, 2.000, 4.00, NULL, NULL, 11, 12, 1, '2026-08-13 16:16:52', NULL),
(15, 4, 'SALIDA_VENTA', 3.000, 8.000, 5.000, 12.00, NULL, NULL, 11, 13, 1, '2026-08-13 16:16:52', NULL),
(16, 2, 'SALIDA_VENTA', 5.000, 5.000, 0.000, 10.00, NULL, NULL, 12, 14, 1, '2026-08-13 17:10:41', NULL),
(17, 2, 'ENTRADA_DEVOLUCION', 5.000, 0.000, 5.000, 10.00, NULL, NULL, 12, 14, 1, '2026-08-13 17:14:20', 'Anulación de venta #12'),
(18, 8, 'SALIDA_VENTA', 3.000, 13.000, 10.000, 12000.00, NULL, NULL, 14, NULL, 1, '2026-08-15 18:13:26', NULL),
(19, 8, 'AJUSTE_ENTRADA', 3.000, 10.000, 13.000, 12000.00, NULL, NULL, 14, NULL, 1, '2026-08-15 23:35:55', 'Edición de factura #14 (reverso de línea anterior)'),
(20, 2, 'AJUSTE_SALIDA', 2.000, 5.000, 3.000, 10.00, NULL, NULL, 14, 16, 1, '2026-08-15 23:35:55', 'Edición de factura #14 (nueva línea)'),
(21, 2, 'SALIDA_VENTA', 1.000, 3.000, 2.000, 10.00, NULL, NULL, 15, NULL, 1, '2026-08-18 10:37:14', NULL),
(22, 2, 'AJUSTE_ENTRADA', 1.000, 2.000, 3.000, 10.00, NULL, NULL, 15, NULL, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (reverso de línea anterior)'),
(23, 2, 'AJUSTE_SALIDA', 2.000, 3.000, 1.000, 10.00, NULL, NULL, 15, 18, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (nueva línea)'),
(24, 11, 'AJUSTE_SALIDA', 3.000, 3.000, 0.000, 4.00, NULL, NULL, 15, 19, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (nueva línea)'),
(25, 10, 'AJUSTE_SALIDA', 15.000, 15.000, 0.000, 3.00, NULL, NULL, 15, 20, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (nueva línea)'),
(26, 4, 'AJUSTE_SALIDA', 5.000, 5.000, 0.000, 12.00, NULL, NULL, 15, 21, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (nueva línea)'),
(27, 7, 'AJUSTE_SALIDA', 19.000, 19.000, 0.000, 2300.00, NULL, NULL, 15, 22, 1, '2026-08-18 10:38:29', 'Edición de factura #15 (nueva línea)');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `pagos_ventas`
--

DROP TABLE IF EXISTS `pagos_ventas`;
CREATE TABLE IF NOT EXISTS `pagos_ventas` (
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
  KEY `idx_pagos_ventas_venta` (`id_venta`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `pagos_ventas`
--

INSERT INTO `pagos_ventas` (`id_pago_venta`, `id_venta`, `id_metodo_pago`, `monto`, `tipo_cambio`, `monto_moneda_base`, `referencia`, `fecha`) VALUES
(1, 1, 4, 1.00, 5.000000, 5.00, '', '2026-08-13 13:43:50'),
(2, 2, 5, 15.00, 1.000000, 15.00, '', '2026-08-13 15:13:10'),
(3, 3, 1, 7.79, 1.000000, 7.79, '', '2026-08-13 16:07:26'),
(4, 4, 1, 17.00, 1.000000, 17.00, '', '2026-08-13 16:08:02'),
(5, 5, 4, 17.00, 1.000000, 17.00, '', '2026-08-13 16:13:37'),
(6, 6, 5, 8.00, 1.000000, 8.00, '', '2026-08-13 16:14:11'),
(7, 7, 3, 75.00, 1.000000, 75.00, '', '2026-08-13 16:14:37'),
(8, 8, 5, 85.00, 1.000000, 85.00, '', '2026-08-13 16:15:04'),
(9, 9, 1, 40.00, 1.000000, 40.00, '', '2026-08-13 16:15:38'),
(10, 10, 1, 51.00, 1.000000, 51.00, '', '2026-08-13 16:16:02'),
(11, 11, 3, 90.00, 1.000000, 90.00, '', '2026-08-13 16:16:52'),
(12, 12, 1, 75.00, 1.000000, 75.00, '', '2026-08-13 17:10:41'),
(13, 14, 1, 45000.00, 1.000000, 45000.00, '', '2026-08-15 18:13:26'),
(14, 15, 3, 15.00, 1.000000, 15.00, '', '2026-08-18 10:37:14');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `productos`
--

DROP TABLE IF EXISTS `productos`;
CREATE TABLE IF NOT EXISTS `productos` (
  `id_producto` int NOT NULL AUTO_INCREMENT,
  `id_categoria` int DEFAULT NULL,
  `codigo` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `nombre` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `imagen` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
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
  KEY `fk_producto_categoria` (`id_categoria`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `productos`
--

INSERT INTO `productos` (`id_producto`, `id_categoria`, `codigo`, `nombre`, `imagen`, `descripcion`, `precio_compra`, `precio_venta`, `costo_promedio`, `stock_actual`, `stock_minimo`, `activo`, `fecha_creacion`) VALUES
(1, 1, 'MP003', 'arroz marquez', NULL, NULL, 15.00, 20.00, 15.00, 14.000, 4.000, 0, '2026-08-13 10:56:34'),
(2, 4, 'MP005', 'Harina Mary', NULL, NULL, 10.00, 15.00, 10.00, 1.000, 4.000, 1, '2026-08-13 14:46:16'),
(3, 4, 'MP007', 'Lentejas', NULL, NULL, 4.00, 8.00, 4.00, 2.000, 3.000, 1, '2026-08-13 14:47:08'),
(4, 4, 'MP009', 'Mantequilla Mavesa', NULL, NULL, 12.00, 17.00, 12.00, 0.000, 4.000, 1, '2026-08-13 14:47:44'),
(5, 3, 'MP010', 'Mayones Mavesa', NULL, NULL, 13.00, 18.00, 13.00, 15.000, 5.000, 1, '2026-08-13 14:48:24'),
(6, 2, 'MP002', 'Lentejas', NULL, NULL, 8.00, 13.00, 8.00, 15.000, 3.000, 0, '2026-08-13 14:51:52'),
(7, 1, 'MP011', 'LECHE V', 'uploads/products/product_72d724442fc3514c955fb438597c8d2f.jpg', NULL, 2300.00, 5000.00, 2300.00, 0.000, 5.000, 1, '2026-08-15 15:08:15'),
(8, 2, 'MP015', 'aceite', 'uploads/products/product_8a06c861ff291aca4710438a804ca5bc.jpg', NULL, 3.00, 5.00, 12000.00, 13.000, 3.000, 1, '2026-08-15 18:12:21'),
(10, 2, 'MP016', 'frijoles', NULL, NULL, 3.00, 5.00, 3.00, 0.000, 4.000, 1, '2026-08-16 22:37:12'),
(11, 2, 'MP018', 'Harina Pan', NULL, NULL, 4.00, 5.00, 4.00, 0.000, 3.000, 1, '2026-08-16 22:56:09');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `proveedores`
--

DROP TABLE IF EXISTS `proveedores`;
CREATE TABLE IF NOT EXISTS `proveedores` (
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
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `proveedores`
--

INSERT INTO `proveedores` (`id_proveedor`, `nombre`, `documento`, `telefono`, `correo`, `direccion`, `contacto`, `activo`, `fecha_creacion`) VALUES
(1, 'carlos', '2345324', '04163578467', '', 'La Esperanza', NULL, 0, '2026-08-13 15:17:09'),
(2, 'jose', '2345654', '0416754689', '', 'La San Juana', NULL, 0, '2026-08-13 16:34:10'),
(3, 'katherin', '3214563', '04243567821', 'arianna1704angarita@gmail.com', 'Los bloques', NULL, 1, '2026-08-13 16:36:47'),
(4, 'KATHERIN', '32132456', '03300555', 'arianna.angarita13@gmail.com', 'La San Juana', NULL, 1, '2026-08-15 17:59:09');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `respaldos`
--

DROP TABLE IF EXISTS `respaldos`;
CREATE TABLE IF NOT EXISTS `respaldos` (
  `id_respaldo` int NOT NULL AUTO_INCREMENT,
  `nombre_archivo` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ruta_archivo` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `fecha` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `tipo` enum('MANUAL','AUTOMATICO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `tamano` bigint DEFAULT NULL,
  `estado` enum('EXITOSO','FALLIDO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `id_usuario` int DEFAULT NULL,
  PRIMARY KEY (`id_respaldo`),
  KEY `fk_respaldo_usuario` (`id_usuario`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `roles`
--

DROP TABLE IF EXISTS `roles`;
CREATE TABLE IF NOT EXISTS `roles` (
  `id_rol` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id_rol`),
  UNIQUE KEY `nombre` (`nombre`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `roles`
--

INSERT INTO `roles` (`id_rol`, `nombre`, `descripcion`, `activo`) VALUES
(1, 'Administrador', 'Acceso completo al sistema', 1),
(2, 'Vendedor', 'Registro y consulta de ventas', 1),
(3, 'Inventario', 'Gestión de productos e inventario', 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usuarios`
--

DROP TABLE IF EXISTS `usuarios`;
CREATE TABLE IF NOT EXISTS `usuarios` (
  `id_usuario` int NOT NULL AUTO_INCREMENT,
  `id_rol` int NOT NULL,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `usuario` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT '1',
  `fecha_creacion` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_usuario`),
  UNIQUE KEY `usuario` (`usuario`),
  KEY `fk_usuario_rol` (`id_rol`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `usuarios`
--

INSERT INTO `usuarios` (`id_usuario`, `id_rol`, `nombre`, `usuario`, `password`, `activo`, `fecha_creacion`) VALUES
(1, 1, 'arianna', 'ari', '$2y$10$7WSe8i60YujLEX2i3DLPc.sWkgLPqXCsdzaMLPpFBZTjBO7ZLP9UW', 1, '2026-08-12 16:55:25'),
(2, 2, 'arianna', 'katherin', '$2y$10$izVt1EAonKjvFTPMDmByv.Ievq6AyvG0T17BKs3NOqbTrIZiXJGEO', 1, '2026-08-17 22:12:37');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ventas`
--

DROP TABLE IF EXISTS `ventas`;
CREATE TABLE IF NOT EXISTS `ventas` (
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
  `tasas_cambio` text COLLATE utf8mb4_unicode_ci,
  `tipo_cambio` decimal(18,6) NOT NULL DEFAULT '1.000000',
  `estado` enum('PENDIENTE','COMPLETADA','ANULADA') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'COMPLETADA',
  `observaciones` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id_venta`),
  UNIQUE KEY `numero_factura` (`numero_factura`),
  KEY `fk_venta_usuario` (`id_usuario`),
  KEY `fk_venta_moneda` (`id_moneda`),
  KEY `idx_ventas_fecha` (`fecha`),
  KEY `idx_ventas_cliente` (`id_cliente`),
  KEY `idx_ventas_estado` (`estado`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `ventas`
--

INSERT INTO `ventas` (`id_venta`, `numero_factura`, `id_cliente`, `id_usuario`, `fecha`, `subtotal`, `descuento`, `impuesto`, `total`, `id_moneda`, `tasas_cambio`, `tipo_cambio`, `estado`, `observaciones`) VALUES
(1, 'F-20260813134350-25', NULL, 1, '2026-08-13 13:43:50', 20.00, 0.00, 0.00, 20.00, 2, NULL, 1.000000, 'COMPLETADA', NULL),
(2, 'F-20260813151310-35', 2, 1, '2026-08-13 15:13:10', 15.00, 0.00, 0.00, 15.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(3, 'F-20260813160726-64', 2, 1, '2026-08-13 16:07:26', 8.00, 0.00, 0.00, 8.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(4, 'F-20260813160802-61', NULL, 1, '2026-08-13 16:08:02', 17.00, 0.00, 0.00, 17.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(5, 'F-20260813161337-11', NULL, 1, '2026-08-13 16:13:37', 34.00, 0.00, 0.00, 34.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(6, 'F-20260813161411-24', 2, 1, '2026-08-13 16:14:11', 8.00, 0.00, 0.00, 8.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(7, 'F-20260813161437-36', NULL, 1, '2026-08-13 16:14:37', 75.00, 0.00, 0.00, 75.00, 2, NULL, 1.000000, 'COMPLETADA', NULL),
(8, 'F-20260813161504-30', NULL, 1, '2026-08-13 16:15:04', 85.00, 0.00, 0.00, 85.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(9, 'F-20260813161538-55', NULL, 1, '2026-08-13 16:15:38', 40.00, 0.00, 0.00, 40.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(10, 'F-20260813161602-37', 2, 1, '2026-08-13 16:16:02', 51.00, 0.00, 0.00, 51.00, 2, NULL, 1.000000, 'COMPLETADA', NULL),
(11, 'F-20260813161652-41', 2, 1, '2026-08-13 16:16:52', 90.00, 0.00, 0.00, 90.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(12, 'F-20260813171041-37', 2, 1, '2026-08-13 17:10:41', 75.00, 0.00, 0.00, 75.00, 4, NULL, 1.000000, 'ANULADA', NULL),
(14, 'F-20260815181326-12', NULL, 1, '2026-08-15 18:13:26', 30.00, 0.00, 0.00, 30.00, 4, NULL, 1.000000, 'COMPLETADA', NULL),
(15, 'F-20260818103714-35', NULL, 1, '2026-08-18 10:37:14', 95205.00, 0.00, 0.00, 95205.00, 1, '{\"USD\":1,\"VES\":0.002,\"COP\":0.000286}', 1.000000, 'COMPLETADA', NULL);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_compras`
-- (Véase abajo para la vista actual)
--
DROP VIEW IF EXISTS `vista_compras`;
CREATE TABLE IF NOT EXISTS `vista_compras` (
`descuento` decimal(12,2)
,`estado` enum('PENDIENTE','COMPLETADA','ANULADA')
,`fecha` datetime
,`id_compra` int
,`impuesto` decimal(12,2)
,`moneda` varchar(10)
,`numero_factura` varchar(50)
,`proveedor` varchar(150)
,`subtotal` decimal(12,2)
,`total` decimal(12,2)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_ganancias_ventas`
-- (Véase abajo para la vista actual)
--
DROP VIEW IF EXISTS `vista_ganancias_ventas`;
CREATE TABLE IF NOT EXISTS `vista_ganancias_ventas` (
`cantidad` decimal(12,3)
,`codigo` varchar(50)
,`costo_unitario` decimal(12,2)
,`fecha` datetime
,`ganancia_bruta` decimal(25,5)
,`id_producto` int
,`id_venta` int
,`numero_factura` varchar(50)
,`precio_unitario` decimal(12,2)
,`producto` varchar(150)
,`subtotal` decimal(12,2)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_inventario`
-- (Véase abajo para la vista actual)
--
DROP VIEW IF EXISTS `vista_inventario`;
CREATE TABLE IF NOT EXISTS `vista_inventario` (
`categoria` varchar(100)
,`codigo` varchar(50)
,`costo_promedio` decimal(12,2)
,`estado_stock` varchar(10)
,`id_producto` int
,`nombre` varchar(150)
,`precio_compra` decimal(12,2)
,`precio_venta` decimal(12,2)
,`stock_actual` decimal(12,3)
,`stock_minimo` decimal(12,3)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_compras`
--
DROP TABLE IF EXISTS `vista_compras`;

DROP VIEW IF EXISTS `vista_compras`;
CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_compras`  AS SELECT `c`.`id_compra` AS `id_compra`, `c`.`numero_factura` AS `numero_factura`, `c`.`fecha` AS `fecha`, `pr`.`nombre` AS `proveedor`, `m`.`codigo` AS `moneda`, `c`.`subtotal` AS `subtotal`, `c`.`descuento` AS `descuento`, `c`.`impuesto` AS `impuesto`, `c`.`total` AS `total`, `c`.`estado` AS `estado` FROM ((`compras` `c` join `proveedores` `pr` on((`c`.`id_proveedor` = `pr`.`id_proveedor`))) join `monedas` `m` on((`c`.`id_moneda` = `m`.`id_moneda`))) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_ganancias_ventas`
--
DROP TABLE IF EXISTS `vista_ganancias_ventas`;

DROP VIEW IF EXISTS `vista_ganancias_ventas`;
CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_ganancias_ventas`  AS SELECT `v`.`id_venta` AS `id_venta`, `v`.`numero_factura` AS `numero_factura`, `v`.`fecha` AS `fecha`, `p`.`id_producto` AS `id_producto`, `p`.`codigo` AS `codigo`, `p`.`nombre` AS `producto`, `dv`.`cantidad` AS `cantidad`, `dv`.`precio_unitario` AS `precio_unitario`, `dv`.`costo_unitario` AS `costo_unitario`, ((`dv`.`precio_unitario` - `dv`.`costo_unitario`) * `dv`.`cantidad`) AS `ganancia_bruta`, `dv`.`subtotal` AS `subtotal` FROM ((`ventas` `v` join `detalle_ventas` `dv` on((`v`.`id_venta` = `dv`.`id_venta`))) join `productos` `p` on((`dv`.`id_producto` = `p`.`id_producto`))) WHERE (`v`.`estado` = 'COMPLETADA') ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_inventario`
--
DROP TABLE IF EXISTS `vista_inventario`;

DROP VIEW IF EXISTS `vista_inventario`;
CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_inventario`  AS SELECT `p`.`id_producto` AS `id_producto`, `p`.`codigo` AS `codigo`, `p`.`nombre` AS `nombre`, `c`.`nombre` AS `categoria`, `p`.`precio_compra` AS `precio_compra`, `p`.`precio_venta` AS `precio_venta`, `p`.`costo_promedio` AS `costo_promedio`, `p`.`stock_actual` AS `stock_actual`, `p`.`stock_minimo` AS `stock_minimo`, (case when (`p`.`stock_actual` = 0) then 'AGOTADO' when (`p`.`stock_actual` <= `p`.`stock_minimo`) then 'STOCK BAJO' else 'DISPONIBLE' end) AS `estado_stock` FROM (`productos` `p` left join `categorias` `c` on((`p`.`id_categoria` = `c`.`id_categoria`))) WHERE (`p`.`activo` = true) ;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `compras`
--
ALTER TABLE `compras`
  ADD CONSTRAINT `fk_compra_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_compra_proveedor` FOREIGN KEY (`id_proveedor`) REFERENCES `proveedores` (`id_proveedor`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_compra_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `detalle_compras`
--
ALTER TABLE `detalle_compras`
  ADD CONSTRAINT `fk_detalle_compra` FOREIGN KEY (`id_compra`) REFERENCES `compras` (`id_compra`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_detalle_compra_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `detalle_ventas`
--
ALTER TABLE `detalle_ventas`
  ADD CONSTRAINT `fk_detalle_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_detalle_venta_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `metodos_pago`
--
ALTER TABLE `metodos_pago`
  ADD CONSTRAINT `fk_metodo_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `movimientos_inventario`
--
ALTER TABLE `movimientos_inventario`
  ADD CONSTRAINT `fk_mov_compra` FOREIGN KEY (`id_compra`) REFERENCES `compras` (`id_compra`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mov_detalle_compra` FOREIGN KEY (`id_detalle_compra`) REFERENCES `detalle_compras` (`id_detalle_compra`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mov_detalle_venta` FOREIGN KEY (`id_detalle_venta`) REFERENCES `detalle_ventas` (`id_detalle_venta`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mov_producto` FOREIGN KEY (`id_producto`) REFERENCES `productos` (`id_producto`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mov_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_mov_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Filtros para la tabla `pagos_ventas`
--
ALTER TABLE `pagos_ventas`
  ADD CONSTRAINT `fk_pago_venta` FOREIGN KEY (`id_venta`) REFERENCES `ventas` (`id_venta`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_pago_venta_metodo` FOREIGN KEY (`id_metodo_pago`) REFERENCES `metodos_pago` (`id_metodo_pago`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `productos`
--
ALTER TABLE `productos`
  ADD CONSTRAINT `fk_producto_categoria` FOREIGN KEY (`id_categoria`) REFERENCES `categorias` (`id_categoria`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Filtros para la tabla `respaldos`
--
ALTER TABLE `respaldos`
  ADD CONSTRAINT `fk_respaldo_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Filtros para la tabla `usuarios`
--
ALTER TABLE `usuarios`
  ADD CONSTRAINT `fk_usuario_rol` FOREIGN KEY (`id_rol`) REFERENCES `roles` (`id_rol`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Filtros para la tabla `ventas`
--
ALTER TABLE `ventas`
  ADD CONSTRAINT `fk_venta_cliente` FOREIGN KEY (`id_cliente`) REFERENCES `clientes` (`id_cliente`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_venta_moneda` FOREIGN KEY (`id_moneda`) REFERENCES `monedas` (`id_moneda`) ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_venta_usuario` FOREIGN KEY (`id_usuario`) REFERENCES `usuarios` (`id_usuario`) ON DELETE RESTRICT ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
