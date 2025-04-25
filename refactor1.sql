-- 1. Создаем нормализованные таблицы с правильными индексами и ограничениями
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- Таблица customers с оптимальными индексами
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,  -- Заменяем два индекса на UNIQUE CONSTRAINT
    created_at TIMESTAMP DEFAULT now() NOT NULL
);

-- Создаем один индекс для email
CREATE INDEX idx_customers_email ON customers(email);

-- Таблица orders с необходимыми индексами и внешними ключами
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(id),
    amount DECIMAL(10,2) CHECK (amount >= 0),
    order_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    notes TEXT,
    CONSTRAINT valid_status CHECK (status IN ('pending', 'completed', 'canceled'))
);

-- Индексы для частых запросов
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_orders_status ON orders(status);

-- Таблица order_items с оптимальными индексами
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0)
);

-- Индексы для соединений и фильтрации
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_items_quantity ON order_items(quantity);

-- 2. Заполняем таблицы тестовыми данными
INSERT INTO customers (name, email)
SELECT 
    'Customer ' || i,
    'customer' || i || CASE WHEN i%2=0 THEN '@gmail.com' ELSE '@example.com' END
FROM generate_series(1, 10000) AS i;

-- 100,000 заказов (по 10 на клиента)
INSERT INTO orders (customer_id, amount, order_date, status)
SELECT 
    (random() * 9999)::int + 1,
    (random() * 1000)::numeric(10,2),
    (now() - (random() * 365)::int * '1 day'::interval)::date,
    CASE WHEN random() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 100000);

-- 300,000 позиций заказов (по 3 на заказ)
INSERT INTO order_items (order_id, product_id, quantity, price)
SELECT 
    (random() * 99999)::int + 1,
    (random() * 100)::int + 1,
    (random() * 10)::int + 1,
    (random() * 500)::numeric(10,2)
FROM generate_series(1, 300000);

-- 3. Анализируем статистику таблиц
ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;

-- 4. Запускаем проблемные запросы с EXPLAIN ANALYZE

-- Запрос 1: Явный выбор полей + оптимизированные JOIN
EXPLAIN ANALYZE
SELECT 
    o.id AS order_id,
    o.order_date,
    c.name AS customer_name,
    c.email,
    oi.product_id,
    oi.quantity
FROM orders o
JOIN customers c ON o.customer_id = c.id
JOIN order_items oi ON o.id = oi.order_id
WHERE c.email LIKE '%@gmail.com'
  AND o.order_date BETWEEN '2023-01-01' AND CURRENT_DATE
ORDER BY o.order_date DESC;

-- Запрос 2: Замена подзапроса на JOIN
EXPLAIN ANALYZE
SELECT 
    c.name,
    COUNT(o.id) AS order_count
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
WHERE c.created_at > '2023-01-01'
GROUP BY c.id;

-- Запрос 3: Используем функциональный индекс
EXPLAIN ANALYZE
SELECT id, name, email
FROM customers
WHERE LOWER(name) = 'customer 5000';

-- Запрос 4: Пагинация и фильтрация по префиксу
EXPLAIN ANALYZE
SELECT 
    c.id AS customer_id,
    c.name,
    o.id AS order_id,
    oi.product_id
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
LEFT JOIN order_items oi ON o.id = oi.order_id
WHERE c.name LIKE 'Customer 1%'
LIMIT 100;

-- Запрос 5: Оптимизация условия даты
EXPLAIN ANALYZE
UPDATE orders
SET notes = 'processed'
WHERE order_date BETWEEN '2023-01-01' AND '2023-12-31';

-- Запрос 6: Использование индекса для диапазона
EXPLAIN ANALYZE
DELETE FROM order_items
WHERE quantity < 2;
