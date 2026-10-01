-- =============================================================
-- 01_crear_tablas.sql
-- Crea la base de datos y las tablas necesarias para el análisis.
-- Motor: MySQL 8 / MariaDB 10+
-- =============================================================

CREATE DATABASE IF NOT EXISTS olist_entregas;
USE olist_entregas;

DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS sellers;

CREATE TABLE customers (
    customer_id              CHAR(32) PRIMARY KEY,
    customer_unique_id       CHAR(32),
    customer_zip_code_prefix VARCHAR(5),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2)
);

CREATE TABLE sellers (
    seller_id              CHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2)
);

CREATE TABLE orders (
    order_id                      CHAR(32) PRIMARY KEY,
    customer_id                   CHAR(32),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME NULL,
    order_delivered_carrier_date  DATETIME NULL,  -- cuando el vendedor lo entregó al transporte
    order_delivered_customer_date DATETIME NULL,  -- cuando llegó al cliente (entrega real)
    order_estimated_delivery_date DATETIME,       -- fecha prometida al cliente (entrega planificada)
    INDEX idx_customer (customer_id)
);

CREATE TABLE order_items (
    order_id            CHAR(32),
    order_item_id       INT,
    product_id          CHAR(32),
    seller_id           CHAR(32),
    shipping_limit_date DATETIME,  -- fecha límite para que el vendedor despache
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    INDEX idx_seller (seller_id)
);

CREATE TABLE order_reviews (
    review_id    CHAR(32),
    order_id     CHAR(32),
    review_score TINYINT,
    INDEX idx_order (order_id)
);
