# Примеры использования функций
На вход каждой функции подаются:
+ схема, в которой работает студент
+ схема, в которой работает преподаватель
+ возможное решение задания

## Таблицы - check_table_structure()

Функция вернёт:
+ 0.2 балла за существование таблицы с правильным названием
+ 0.2 балла за правильный первичный ключ
+ по 0.6/n баллов за каждую правильную колонку, где n - количество колонок
Если таблицы не существует, сразу возвращается 0. Результат округляется до десятых.

### Задание
Создайте таблицу `employees` с полями: `emp_id` типа `SERIAL`, `emp_name` типа `VARCHAR(100)`, `position` типа `VARCHAR(50)` и `salary` типа `DECIMAL(10, 2)`. Установите первичный ключ по полю `emp_id`.

### Решение
```sql
DROP TABLE IF EXISTS employees;
CREATE TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(100),
    position VARCHAR(50),
    salary DECIMAL(10, 2)
);
```
### Запуск функции
```sql
SELECT check_table_structure(
    'public', -- схема студента,
    'teacher_check', -- схема учителя
    'CREATE TABLE employees (
        emp_id SERIAL PRIMARY KEY,
        emp_name VARCHAR(100),
        position VARCHAR(50),
        salary DECIMAL(10, 2)
    )'
);

```
## Представления - check_view()
Функция вернёт:
+ 0.2 балла за существование представления с правильным названием
+ 0.3 балла, если количество колонок и их имена верные
+ 0.5 балла, если содержимое представления верное
Если представления не существует, сразу возвращается 0. 
### Задание
Создать представление `max_salary_position`, отображающее максимальную зарплату по каждой позиции из таблицы `employees`. В первой колонке - `position` - должно быть указано название позиции, во второй – `max_salary` - максимальная зарплата среди сотрудников этой позиции.
### Решение
```sql
DROP TABLE IF EXISTS employees CASCADE;
CREATE TABLE employees (
	emp_id SERIAL PRIMARY KEY,
	emp_name VARCHAR(100),
	position VARCHAR(50),
	salary DECIMAL(10, 2)
);
INSERT INTO employees (emp_name, position, salary) VALUES
('Alice', 'Developer', 9000.00),
('Bob', 'Developer', 9500.00),
('Charlie', 'Manager', 12000.00),
('David', 'Manager', 11000.00),
('Eve', 'Developer', 8500.00);
DROP VIEW IF EXISTS max_salary_position;

CREATE VIEW max_salary_position AS
SELECT
    position,
    MAX(salary) AS max_salary
FROM
    employees
GROUP BY
    position;

```
### Запуск функции
```sql
SELECT check_view(
    'public', -- схема студента
'teacher_check', -- схема учителя
    'CREATE VIEW max_salary_position AS
     SELECT
         position,
         MAX(salary) AS max_salary
     FROM
         employees
     GROUP BY
         position'
);

```

## Материализованные представления - check_materialized_view()
Функция вернёт:
0.2 балла за существование мат. представления с правильным названием
+ 0.3 балла, если количество колонок и их имена верные
+ 0.5 балла, если содержимое мат. представления верное
Если мат. представления не существует, сразу возвращается 0. 

### Задание
Создать материализованное представление max_salary_position, отображающее максимальную зарплату по каждой позиции из таблицы employees. В первой колонке - position - должно быть указано название позиции, во второй – max_salary - максимальная зарплата среди сотрудников этой позиции.
### Решение
```sql
DROP TABLE IF EXISTS employees CASCADE;
CREATE TABLE employees (
	emp_id SERIAL PRIMARY KEY,
	emp_name VARCHAR(100),
	position VARCHAR(50),
	salary DECIMAL(10, 2)
);
INSERT INTO employees (emp_name, position, salary) VALUES
('Alice', 'Developer', 9000.00),
('Bob', 'Developer', 9500.00),
('Charlie', 'Manager', 12000.00),
('David', 'Manager', 11000.00),
('Eve', 'Developer', 8500.00);
DROP MATERIALIZED VIEW IF EXISTS max_salary_position;

CREATE MATERIALIZED VIEW max_salary_position AS
SELECT 
    position, 
    MAX(salary) AS max_salary
FROM 
    employees
GROUP BY 
    position;
```
### Запуск функции
```sql
SELECT check_materialized_view(
    'public', -- схема студента
    'teacher_check', -- схема учителя
    'CREATE MATERIALIZED VIEW max_salary_position AS
     SELECT 
         position, 
         MAX(salary) AS max_salary
     FROM 
         employees
     GROUP BY 
         position'
);
```
## Ограничения целостности - check_constraints()
Функция вернёт:
по 1/n балла за каждое правильное ограничение, где n - кол-во ограничений
### Задание
Проставьте такие ограничения таблицы employees, чтобы поле emp_id стало первичным ключом, поле emp_name не могло содержать пустых записей, а значения поля salary не превышали 500000.
### Решение
```sql
DROP TABLE IF EXISTS employees CASCADE;
CREATE TABLE employees (
	emp_id SERIAL,
	emp_name VARCHAR(100),
	position VARCHAR(50),
	salary DECIMAL(10, 2)
);
ALTER TABLE employees
ADD CONSTRAINT pk_emp_id PRIMARY KEY (emp_id);

ALTER TABLE employees
ALTER COLUMN emp_name SET NOT NULL;

ALTER TABLE employees
ADD CONSTRAINT chk_salary_max CHECK (salary <= 500000);
```
### Запуск функции
```sql
SELECT check_constraints(
    'public', -- схема студента
    'teacher_check', -- схема учителя
    'ALTER TABLE employees
     ADD CONSTRAINT pk_emp_id PRIMARY KEY (emp_id);
     ALTER TABLE employees
     ALTER COLUMN emp_name SET NOT NULL;
     ALTER TABLE employees
     ADD CONSTRAINT chk_salary_max CHECK (salary <= 500000);'
);
```
## Последовательности - check_sequence()
Функция вернёт:
0.2 балла за существование последовательности с правильным названием
+ 0.3 балла, если один из параметров (начальное значение, шаг) правильный
+ 0.5 балла, если второй параметр правильный
Если последовательности не существует, сразу возвращается 0. 

### Задание
Создайте последовательность test_sequence, которая начинается с 10 и возрастает с шагом 5. 
### Решение
```sql
DROP SEQUENCE IF EXISTS test_sequence;
CREATE SEQUENCE test_sequence
    START WITH 10
    INCREMENT BY 5;
```

### Запуск функции
```sql
SELECT check_sequence(
    'public',
    'teacher_check',
    'CREATE SEQUENCE test_sequence
     START WITH 10
     INCREMENT BY 5;'
);

```
## Триггеры - check_trigger()
Функция вернёт:
0.5 балла за существование триггера с правильным названием, таблицей и функцией
+ 0.5 балла, если тип триггера правильный
Если подходящий триггер не нашёлся, сразу возвращается 0.

### Задание
Создайте триггер check_update,  который срабатывает перед обновлением таблицы employees и запускает функцию f_updated_emp() для каждой обновлённой записи.
### Решение
```sql
DROP TABLE IF EXISTS employees CASADE;
CREATE TABLE employees (
	emp_id SERIAL PRIMARY KEY,
	emp_name VARCHAR(100),
	position VARCHAR(50),
	salary DECIMAL(10, 2)
);
DROP TRIGGER IF EXISTS check_update ON employees;
CREATE OR REPLACE FUNCTION f_updated_emp() RETURNS TRIGGER AS $$
BEGIN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_update
BEFORE UPDATE ON employees
FOR EACH ROW
EXECUTE FUNCTION f_updated_emp();
```
### Запуск функции
```sql
SELECT check_trigger(
    'public', -- схема студента,
    'teacher_check', -- схема учителя
    'CREATE TRIGGER check_update
     BEFORE UPDATE ON employees
     FOR EACH ROW
     EXECUTE FUNCTION f_updated_emp();');
```
## Индексы - check_index()
Функция вернёт:
1 балл за верное решение
0 баллов, если индекс не найден 
### Задание
Создайте индекс на столбце emp_name в таблице employees.
### Решение
```sql
DROP TABLE IF EXISTS employees;
CREATE TABLE employees (
	emp_id SERIAL PRIMARY KEY,
	emp_name VARCHAR(100),
	position VARCHAR(50),
	salary DECIMAL(10, 2)
);
DROP INDEX IF EXISTS idx_emp_name;
CREATE INDEX idx_emp_name ON employees (emp_name);
```
### Запуск функции
```sql
SELECT check_index(
    'public', -- схема студента
    'teacher_check', -- схема учителя
    'CREATE INDEX idx_emp_name ON employees (emp_name);'
);
```
