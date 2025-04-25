-- 1. Создаем тестовые таблицы с проблемами индексации
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

-- Таблица customers с избыточными индексами
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT now()
);

-- Дублирующийся индекс (избыточность)
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_email_duplicate ON customers(email); -- Дубликат!

-- Таблица orders без важных индексов
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT, -- Нет индекса для JOIN
    amount DECIMAL(10,2),
    order_date DATE, -- Нет индекса для частых запросов по дате
    status VARCHAR(20),
    notes TEXT
);

-- Таблица order_items без индексов для соединений
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT, -- Нет индекса для JOIN
    product_id INT, -- Нет индекса
    quantity INT, -- Нет индекса для фильтрации
    price DECIMAL(10,2)
);

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

-- Запрос 1: Полное сканирование с SELECT * и сложными JOIN
EXPLAIN ANALYZE
SELECT *
FROM orders o
JOIN customers c ON o.customer_id = c.id
JOIN order_items oi ON o.id = oi.order_id
WHERE c.email LIKE '%@gmail.com'
  AND o.order_date > '2023-01-01'
ORDER BY o.order_date DESC;

-- Запрос 2: Неэффективный подзапрос вместо JOIN
EXPLAIN ANALYZE
SELECT 
    c.name,
    (SELECT COUNT(*) FROM orders WHERE customer_id = c.id) AS order_count
FROM customers c
WHERE c.created_at > '2023-01-01';

-- Запрос 3: Использование функции в WHERE обходит индексы
EXPLAIN ANALYZE
SELECT *
FROM customers
WHERE LOWER(name) = 'customer 5000';

-- Запрос 4: Множественные LEFT JOIN с избыточными данными
EXPLAIN ANALYZE
SELECT *
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
LEFT JOIN order_items oi ON o.id = oi.order_id
WHERE c.name LIKE 'Customer 1%';

-- Запрос 5: UPDATE с полным сканированием
EXPLAIN ANALYZE
UPDATE orders
SET notes = 'processed'
WHERE DATE_PART('year', order_date) = 2023;

-- Запрос 6: DELETE без использования индекса
EXPLAIN ANALYZE
DELETE FROM order_items
WHERE quantity < 2;
