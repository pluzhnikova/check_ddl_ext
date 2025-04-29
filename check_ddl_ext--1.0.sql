\echo Use "CREATE EXTENSION check_ddl_ext" to load this file. \quit

CREATE OR REPLACE FUNCTION check_table_structure(
    student_schema TEXT,
    teacher_schema TEXT,
    expected_creation_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    table_name TEXT;
    total_score NUMERIC := 0.0;
    column_count INT := 0;
    correct_columns INT := 0;
    pk_check BOOLEAN := FALSE;
    teacher_table_oid OID;
    student_table_oid OID;
BEGIN
    -- Извлекаем имя таблицы из SQL-запроса
    table_name := (regexp_matches(expected_creation_sql, 'CREATE TABLE\s+([^\s(]+)', 'i'))[1];
    -- Удаляем старую эталонную таблицу
    EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', teacher_schema, table_name);
    
    -- Создаем эталонную таблицу
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE expected_creation_sql;
        EXECUTE format('SET search_path TO public');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE format('SET search_path TO public');
        RAISE EXCEPTION 'Ошибка при создании эталонной таблицы: %', SQLERRM;
    END;
    
    -- Получаем OID таблиц
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''r''', 
        teacher_schema, table_name)
    INTO teacher_table_oid;
    
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''r''', 
        student_schema, table_name)
    INTO student_table_oid;
    
    -- Если таблица у студента не существует, возвращаем 0
    IF student_table_oid IS NULL THEN
        RETURN 0.0;
    END IF;
    total_score := total_score + 0.2;

    -- Проверяем первичный ключ
    IF teacher_table_oid IS NOT NULL THEN
        EXECUTE format('
            SELECT EXISTS (
                SELECT 1 FROM (
                    SELECT conkey, contype 
                    FROM pg_constraint 
                    WHERE conrelid = %L AND contype = ''p''
                ) student_pk
                JOIN (
                    SELECT conkey, contype 
                    FROM pg_constraint 
                    WHERE conrelid = %L AND contype = ''p''
                ) teacher_pk ON student_pk.conkey = teacher_pk.conkey
            )', student_table_oid, teacher_table_oid)
        INTO pk_check;
        
        IF pk_check THEN
            total_score := total_score + 0.2;
        END IF;
    END IF;

    -- Получаем количество столбцов в эталонной таблице
    IF teacher_table_oid IS NOT NULL THEN
        EXECUTE format('
            SELECT COUNT(*) 
            FROM pg_attribute a
            WHERE a.attrelid = %L
            AND a.attnum > 0
            AND NOT a.attisdropped', 
            teacher_table_oid)
        INTO column_count;
    END IF;

    -- Если колонок нет, возвращаем текущий балл
    IF column_count = 0 THEN
        RETURN round(total_score, 1);
    END IF;

    -- Проверяем только требуемые столбцы
    IF teacher_table_oid IS NOT NULL AND student_table_oid IS NOT NULL THEN
        EXECUTE format('
            SELECT COUNT(*) 
            FROM (
                SELECT 
                    a.attname AS col_name,
                    t.typname AS col_type,
                    a.atttypmod AS col_mod
                FROM pg_attribute a
                JOIN pg_type t ON t.oid = a.atttypid
                WHERE a.attrelid = %L
                AND a.attnum > 0
                AND NOT a.attisdropped
            ) teacher_cols
            WHERE EXISTS (
                SELECT 1
                FROM pg_attribute a2
                JOIN pg_type t2 ON t2.oid = a2.atttypid
                WHERE a2.attrelid = %L
                AND a2.attnum > 0
                AND NOT a2.attisdropped
                AND a2.attname = teacher_cols.col_name
                AND t2.typname = teacher_cols.col_type
                AND (
                    (a2.atttypmod = teacher_cols.col_mod) OR
                    (a2.atttypmod IS NULL AND teacher_cols.col_mod IS NULL)
                )
            )',
            teacher_table_oid, student_table_oid)
        INTO correct_columns;
    END IF;

    IF column_count > 0 THEN
        total_score := total_score + (0.6 * (correct_columns::NUMERIC / column_count));
    END IF;

    RETURN round(total_score, 1);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_view(
    student_schema TEXT,
    teacher_schema TEXT,
    expected_view_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    view_name TEXT;
    teacher_data JSONB;
    student_data JSONB;
    teacher_view_oid OID;
    student_view_oid OID;
    required_columns TEXT[];
    missing_column TEXT;
    column_exists BOOLEAN;
    type_mismatch BOOLEAN;
BEGIN
    -- Извлекаем имя представления из SQL-запроса
    view_name := (regexp_matches(expected_view_sql, 'CREATE VIEW\s+([^\s(]+)', 'i'))[1];
       
    -- Создаем эталонное представление
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', teacher_schema, view_name);
    
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE expected_view_sql;
        EXECUTE format('SET search_path TO public');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE format('SET search_path TO public');
        RAISE EXCEPTION 'Ошибка при создании эталонного представления: %', SQLERRM;
    END;
    
    -- Получаем OID представлений
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''v''', 
        teacher_schema, view_name)
    INTO teacher_view_oid;
    
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''v''', 
        student_schema, view_name)
    INTO student_view_oid;
    
    -- Проверяем существование представления у студента
    IF student_view_oid IS NULL THEN
        RETURN 0.0;
    END IF;

    -- Проверяем наличие всех обязательных столбцов у студента
    EXECUTE format('
        SELECT array_agg(a.attname)
        FROM pg_attribute a
        WHERE a.attrelid = %L
        AND a.attnum > 0
        AND NOT a.attisdropped', 
        teacher_view_oid)
    INTO required_columns;
    
    FOREACH missing_column IN ARRAY required_columns LOOP
        EXECUTE format('
            SELECT NOT EXISTS (
                SELECT 1
                FROM pg_attribute
                WHERE attrelid = %L
                AND attname = %L
                AND attnum > 0
                AND NOT attisdropped
            )', 
            student_view_oid, missing_column)
        INTO column_exists;
        
        IF column_exists THEN
            RETURN 0.3;
        END IF;
    END LOOP;
    
    -- Проверяем типы данных обязательных столбцов
    EXECUTE format('
        SELECT EXISTS (
            SELECT 1 FROM (
                SELECT 
                    a.attname AS col_name,
                    t.typname AS col_type
                FROM pg_attribute a
                JOIN pg_type t ON t.oid = a.atttypid
                WHERE a.attrelid = %L
                AND a.attnum > 0
                AND NOT a.attisdropped
                AND a.attname = ANY(%L)
            ) teacher_cols
            JOIN (
                SELECT 
                    a.attname AS col_name,
                    t.typname AS col_type
                FROM pg_attribute a
                JOIN pg_type t ON t.oid = a.atttypid
                WHERE a.attrelid = %L
                AND a.attnum > 0
                AND NOT a.attisdropped
                AND a.attname = ANY(%L)
            ) student_cols ON teacher_cols.col_name = student_cols.col_name
            WHERE teacher_cols.col_type <> student_cols.col_type
        )', 
        teacher_view_oid, required_columns,
        student_view_oid, required_columns)
    INTO type_mismatch;
    
    IF type_mismatch THEN
        RETURN 0.3;
    END IF;
    
    -- Проверка данных по обязательным столбцам
    BEGIN
        EXECUTE format('
            SELECT jsonb_agg(row_to_json(t))
            FROM (SELECT %s FROM %I.%I ORDER BY 1) t', 
            array_to_string(required_columns, ', '), teacher_schema, view_name)
        INTO teacher_data;
        
        EXECUTE format('
            SELECT jsonb_agg(row_to_json(t))
            FROM (SELECT %s FROM %I.%I ORDER BY 1) t', 
            array_to_string(required_columns, ', '), student_schema, view_name)
        INTO student_data;
        
        IF teacher_data::TEXT <> student_data::TEXT THEN
            RETURN 0.7;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN 0.3;
    END;
    
    RETURN 1.0;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_materialized_view(
    student_schema TEXT,
    teacher_schema TEXT,
    expected_view_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    view_name TEXT;
    teacher_data JSONB;
    student_data JSONB;
    teacher_view_oid OID;
    student_view_oid OID;
    required_columns TEXT[];
    missing_column TEXT;
    column_exists BOOLEAN;
    type_mismatch BOOLEAN;
BEGIN
    -- Извлекаем имя представления 
    view_name := (regexp_matches(expected_view_sql, 'CREATE MATERIALIZED VIEW\s+([^\s(]+)', 'i'))[1];
    
    -- Создаем эталонное представление
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I.%I CASCADE', teacher_schema, view_name);
    
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE expected_view_sql;
        EXECUTE format('SET search_path TO public');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE format('SET search_path TO public');
        RAISE EXCEPTION 'Ошибка при создании эталонного материализованного представления: %', SQLERRM;
    END;
    
    -- Получаем OID представлений
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''m''', 
        teacher_schema, view_name)
    INTO teacher_view_oid;
    
    EXECUTE format('
        SELECT c.oid 
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = %L
        AND c.relname = %L
        AND c.relkind = ''m''', 
        student_schema, view_name)
    INTO student_view_oid;
    
    -- Проверяем существование представления у студента
    IF student_view_oid IS NULL THEN
        RETURN 0.0;
    END IF;

    -- Проверяем наличие всех обязательных столбцов 
    EXECUTE format('
        SELECT array_agg(a.attname)
        FROM pg_attribute a
        WHERE a.attrelid = %L
        AND a.attnum > 0
        AND NOT a.attisdropped', 
        teacher_view_oid)
    INTO required_columns;
    
    FOREACH missing_column IN ARRAY required_columns LOOP
        EXECUTE format('
            SELECT NOT EXISTS (
                SELECT 1
                FROM pg_attribute
                WHERE attrelid = %L
                AND attname = %L
                AND attnum > 0
                AND NOT attisdropped
            )', 
            student_view_oid, missing_column)
        INTO column_exists;
        
        IF column_exists THEN
            RETURN 0.3;
        END IF;
    END LOOP;
    
    -- Проверяем типы данных обязательных столбцов
    EXECUTE format('
        SELECT EXISTS (
            SELECT 1 FROM (
                SELECT 
                    a.attname AS col_name,
                    t.typname AS col_type
                FROM pg_attribute a
                JOIN pg_type t ON t.oid = a.atttypid
                WHERE a.attrelid = %L
                AND a.attnum > 0
                AND NOT a.attisdropped
                AND a.attname = ANY(%L)
            ) teacher_cols
            JOIN (
                SELECT 
                    a.attname AS col_name,
                    t.typname AS col_type
                FROM pg_attribute a
                JOIN pg_type t ON t.oid = a.atttypid
                WHERE a.attrelid = %L
                AND a.attnum > 0
                AND NOT a.attisdropped
                AND a.attname = ANY(%L)
            ) student_cols ON teacher_cols.col_name = student_cols.col_name
            WHERE teacher_cols.col_type <> student_cols.col_type
        )', 
        teacher_view_oid, required_columns,
        student_view_oid, required_columns)
    INTO type_mismatch;
    
    IF type_mismatch THEN
        RETURN 0.3;
    END IF;
    
    -- Проверка данных по обязательным столбцам
    BEGIN
        EXECUTE format('
            SELECT jsonb_agg(row_to_json(t))
            FROM (SELECT %s FROM %I.%I ORDER BY 1) t', 
            array_to_string(required_columns, ', '), teacher_schema, view_name)
        INTO teacher_data;
        
        EXECUTE format('
            SELECT jsonb_agg(row_to_json(t))
            FROM (SELECT %s FROM %I.%I ORDER BY 1) t', 
            array_to_string(required_columns, ', '), student_schema, view_name)
        INTO student_data;
        
        IF teacher_data::TEXT <> student_data::TEXT THEN
            RETURN 0.7;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN 0.3;
    END;
    
    RETURN 1.0;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_constraints(
    student_schema TEXT,
    teacher_schema TEXT,
    constraints_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    table_name TEXT;
    teacher_table_oid OID;
    student_table_oid OID;
    constraint_rec RECORD;
    match_count INT := 0;
    total_constraints INT := 0;
    constraint_lines TEXT[];
    line TEXT;
    table_exists BOOLEAN;
    constraint_match BOOLEAN;
    nn_match BOOLEAN;
    nn_count INT := 0;
    nn_total INT := 0;
BEGIN
    -- Извлекаем имя таблицы 
    table_name := (regexp_matches(constraints_sql, 'ALTER TABLE\s+([^\s;]+)', 'i'))[1];
    
    -- Проверяем существование таблицы в схеме учителя
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = %L AND tablename = %L)',
                  teacher_schema, table_name) INTO table_exists;
    
    IF NOT table_exists THEN
        RAISE EXCEPTION 'Таблица %.% не существует', teacher_schema, table_name;
    END IF;
    
    -- Получаем OID таблиц
    EXECUTE format('SELECT ''%I.%I''::regclass', teacher_schema, table_name) INTO teacher_table_oid;
    EXECUTE format('SELECT ''%I.%I''::regclass', student_schema, table_name) INTO student_table_oid;
   
    constraint_lines := regexp_split_to_array(constraints_sql, E';\n?');
    
    -- Применяем ограничения в схеме учителя (ошибки игнорируются)
    EXECUTE format('SET search_path TO %I', teacher_schema);
    
    FOREACH line IN ARRAY constraint_lines LOOP
        line := trim(line);
        CONTINUE WHEN line = '';
        
        BEGIN
            EXECUTE line;
        EXCEPTION 
            WHEN duplicate_object THEN 
                RAISE NOTICE 'Ограничение уже существует: %', line;
            WHEN OTHERS THEN
                RAISE NOTICE 'Не удалось применить ограничение: %', SQLERRM;
        END;
    END LOOP;
    
    EXECUTE format('SET search_path TO public');
    
    -- Собираем ограничения учителя (кроме NOT NULL)
    FOR constraint_rec IN 
        SELECT 
            c.conname,
            c.contype,
            pg_get_constraintdef(c.oid) AS constraint_def
        FROM pg_constraint c
        WHERE c.conrelid = teacher_table_oid
    LOOP
        total_constraints := total_constraints + 1;
        
        -- Проверяем, есть ли такое же ограничение у студента
        SELECT EXISTS (
            SELECT 1
            FROM pg_constraint sc
            WHERE sc.conrelid = student_table_oid
              AND sc.conname = constraint_rec.conname
              AND sc.contype = constraint_rec.contype
              AND pg_get_constraintdef(sc.oid) = constraint_rec.constraint_def
        ) INTO constraint_match;
        
        IF constraint_match THEN
            match_count := match_count + 1;
        ELSE
            RAISE NOTICE 'Не совпадает ограничение: % (тип: %, определение: %)', 
                constraint_rec.conname, 
                constraint_rec.contype, 
                constraint_rec.constraint_def;
        END IF;
    END LOOP;
    
    -- Проверяем NOT NULL ограничения (из pg_attribute)
    FOR constraint_rec IN 
        SELECT 
            a.attname AS column_name,
            format('ALTER TABLE %I ALTER COLUMN %I SET NOT NULL', table_name, a.attname) AS constraint_def
        FROM pg_attribute a
        WHERE a.attrelid = teacher_table_oid
          AND a.attnotnull
          AND a.attnum > 0
    LOOP
        nn_total := nn_total + 1;
        
        -- Проверяем NOT NULL у студента
        SELECT EXISTS (
            SELECT 1
            FROM pg_attribute sa
            WHERE sa.attrelid = student_table_oid
              AND sa.attname = constraint_rec.column_name
              AND sa.attnotnull
        ) INTO nn_match;
        
        IF nn_match THEN
            nn_count := nn_count + 1;
        ELSE
            RAISE NOTICE 'Отсутствует NOT NULL для столбца: %', constraint_rec.column_name;
        END IF;
    END LOOP;
    
    -- Учитываем NOT NULL в общем результате
    IF nn_total > 0 THEN
        total_constraints := total_constraints + 1;
        IF nn_count = nn_total THEN
            match_count := match_count + 1;
        END IF;
    END IF;
    
    -- Возвращаем долю совпавших ограничений
    IF total_constraints = 0 THEN
        RETURN 1.0;
    ELSE
        RETURN ROUND(match_count::NUMERIC / total_constraints, 1);
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_sequence(
    student_schema TEXT,
    teacher_schema TEXT,
    sequence_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    sequence_name TEXT;
    sequence_exists BOOLEAN;
    teacher_params JSONB := '{}'::JSONB;
    student_params JSONB;
    param TEXT;
    total_params INT := 0;
    matched_params INT := 0;
    param_value TEXT;
BEGIN
    -- Извлекаем имя последовательности
    sequence_name := (regexp_matches(sequence_sql, 'CREATE SEQUENCE\s+([^\s(;]+)', 'i'))[1];
    EXECUTE format('DROP SEQUENCE IF EXISTS %I.%I', teacher_schema, sequence_name);
    
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE sequence_sql;
        EXECUTE format('SET search_path TO %I,public', current_schema());
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Error creating sequence in teacher schema: %', SQLERRM;
    END;
    
    -- Парсим параметры из запроса учителя 
    -- START WITH
    IF sequence_sql ~* 'START WITH\s+(\d+)' THEN
        param_value := (regexp_matches(sequence_sql, 'START WITH\s+(\d+)', 'i'))[1];
        teacher_params := teacher_params || jsonb_build_object('start_value', param_value::bigint);
    END IF;
    
    -- INCREMENT BY
    IF sequence_sql ~* 'INCREMENT BY\s+(\d+)' THEN
        param_value := (regexp_matches(sequence_sql, 'INCREMENT BY\s+(\d+)', 'i'))[1];
        teacher_params := teacher_params || jsonb_build_object('increment_by', param_value::bigint);
    END IF;
    
    -- MINVALUE
    IF sequence_sql ~* 'MINVALUE\s+(\d+)' THEN
        param_value := (regexp_matches(sequence_sql, 'MINVALUE\s+(\d+)', 'i'))[1];
        teacher_params := teacher_params || jsonb_build_object('min_value', param_value::bigint);
    END IF;
    
    -- MAXVALUE
    IF sequence_sql ~* 'MAXVALUE\s+(\d+)' THEN
        param_value := (regexp_matches(sequence_sql, 'MAXVALUE\s+(\d+)', 'i'))[1];
        teacher_params := teacher_params || jsonb_build_object('max_value', param_value::bigint);
    END IF;
    
    -- CYCLE / NO CYCLE
    IF sequence_sql ~* 'CYCLE' THEN
        teacher_params := teacher_params || jsonb_build_object('cycle', true);
    ELSIF sequence_sql ~* 'NO CYCLE' THEN
        teacher_params := teacher_params || jsonb_build_object('cycle', false);
    END IF;
    
    -- CACHE
    IF sequence_sql ~* 'CACHE\s+(\d+)' THEN
        param_value := (regexp_matches(sequence_sql, 'CACHE\s+(\d+)', 'i'))[1];
        teacher_params := teacher_params || jsonb_build_object('cache_size', param_value::bigint);
    END IF;
    
    -- Проверяем существование последовательности у студента
    EXECUTE format('
        SELECT EXISTS (
            SELECT 1
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_sequence s ON c.oid = s.seqrelid
            WHERE n.nspname = %L
            AND c.relname = %L
            AND c.relkind = ''S''
        )', student_schema, sequence_name)
    INTO sequence_exists;
    
    IF NOT sequence_exists THEN 
        RETURN 0.0;
    END IF;
    
    -- Получаем параметры последовательности студента
    EXECUTE format('
        SELECT jsonb_build_object(
            ''start_value'', s.seqstart,
            ''increment_by'', s.seqincrement,
            ''min_value'', s.seqmin,
            ''max_value'', s.seqmax,
            ''cycle'', s.seqcycle,
            ''cache_size'', s.seqcache
        )
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_sequence s ON c.oid = s.seqrelid
        WHERE n.nspname = %L
        AND c.relname = %L', 
        student_schema, sequence_name)
    INTO student_params;
    
    -- Проверяем только те параметры, которые были указаны в запросе учителя
    SELECT COUNT(*) INTO total_params 
    FROM jsonb_object_keys(teacher_params);
    
    FOR param IN SELECT jsonb_object_keys(teacher_params) LOOP
        IF student_params->>param IS NOT NULL AND 
           student_params->>param = teacher_params->>param THEN
            matched_params := matched_params + 1;
        END IF;
    END LOOP;
    
    -- Возвращаем оценку
    IF total_params > 0 AND matched_params = 0 THEN
        RETURN 0.2;  
    ELSIF matched_params > 0 AND matched_params < total_params THEN
        RETURN 0.5; 
    ELSIF matched_params = total_params THEN
        RETURN 1.0; 
    ELSE
        RETURN 1.0;  -- Нет параметров для проверки (все NULL или не указаны)
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_trigger(
    student_schema TEXT,
    teacher_schema TEXT,
    expected_trigger_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    trigger_name TEXT;
    table_name TEXT;
    function_name TEXT;
    is_trigger_exists BOOLEAN;
    teacher_trigger_oid OID;
    student_trigger_oid OID;
    match_count INTEGER;
BEGIN
    -- Извлекаем базовые параметры триггера
    trigger_name := (regexp_matches(expected_trigger_sql, 'CREATE TRIGGER\s+([^\s(]+)', 'i'))[1];
    table_name := (regexp_matches(expected_trigger_sql, 'ON\s+([^\s(;]+)', 'i'))[1];
    function_name := (regexp_matches(expected_trigger_sql, 'EXECUTE FUNCTION\s+([^\s(]+)', 'i'))[1];
    -- Создаем эталонный триггер
    BEGIN
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I', 
                      trigger_name, teacher_schema, table_name);
    EXCEPTION WHEN OTHERS THEN
    END;
    
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE expected_trigger_sql;
        
        EXECUTE format('SET search_path TO public');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE format('SET search_path TO public');
        RAISE EXCEPTION 'Ошибка при создании эталонного триггера: %', SQLERRM;
    END;
    
    -- Получаем OID триггеров
    EXECUTE format('
        SELECT t.oid
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE t.tgname = %L
        AND c.relname = %L
        AND p.proname = %L
        AND n.nspname = %L', 
        trigger_name, table_name, function_name, teacher_schema)
    INTO teacher_trigger_oid;
    
    EXECUTE format('
        SELECT t.oid
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE t.tgname = %L
        AND c.relname = %L
        AND p.proname = %L
        AND n.nspname = %L', 
        trigger_name, table_name, function_name, student_schema)
    INTO student_trigger_oid;
    
    -- Проверяем существование триггера у студента
    IF student_trigger_oid IS NULL THEN
        RETURN 0.0;
    END IF;
    
    -- Сравниваем tgtype триггеров из системных таблиц
    EXECUTE format('
        SELECT COUNT(*) FROM (
            SELECT tgtype
            FROM pg_trigger
            WHERE oid = %L
            EXCEPT
            SELECT tgtype
            FROM pg_trigger
            WHERE oid = %L
        ) AS diff', 
        teacher_trigger_oid, student_trigger_oid)
    INTO match_count;
    
    IF match_count = 0 THEN
        RETURN 1.0;
    ELSE
        RETURN 0.5;
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_index(
    student_schema TEXT,
    teacher_schema TEXT,
    create_index_sql TEXT
) RETURNS NUMERIC AS $$
DECLARE
    index_name TEXT;
    table_name TEXT;
    teacher_index_oid OID;
    student_index_oid OID;
    match_count INTEGER;
BEGIN
    -- Извлекаем имя индекса и таблицы из запроса
    index_name := (regexp_matches(create_index_sql, 'CREATE(?: UNIQUE)? INDEX\s+([^\s(]+)', 'i'))[1];
    table_name := (regexp_matches(create_index_sql, 'ON\s+([^\s(;]+)', 'i'))[1];
    -- Создаем эталонный индекс
    BEGIN
        EXECUTE format('SET search_path TO %I', teacher_schema);
        EXECUTE format('DROP INDEX IF EXISTS %I', index_name);
        EXECUTE create_index_sql;
        
        EXECUTE format('SET search_path TO public');
    EXCEPTION WHEN OTHERS THEN
        EXECUTE format('SET search_path TO public');
        RAISE EXCEPTION 'Ошибка при создании индекса: %', SQLERRM;
    END;
    
    -- Получаем OID индекса учителя
    EXECUTE format('
        SELECT c.oid
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_index i ON i.indexrelid = c.oid
        JOIN pg_class t ON i.indrelid = t.oid
        JOIN pg_namespace tn ON t.relnamespace = tn.oid
        WHERE c.relkind = ''i''
          AND c.relname = %L
          AND t.relname = %L
          AND n.nspname = %L',
        index_name, table_name, teacher_schema)
    INTO teacher_index_oid;
    
    -- Получаем OID индекса студента
    EXECUTE format('
        SELECT c.oid
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_index i ON i.indexrelid = c.oid
        JOIN pg_class t ON i.indrelid = t.oid
        JOIN pg_namespace tn ON t.relnamespace = tn.oid
        WHERE c.relkind = ''i''
          AND c.relname = %L
          AND t.relname = %L
          AND tn.nspname = %L',
        index_name, table_name, student_schema)
    INTO student_index_oid;
    
    -- Проверяем существование индекса у студента
    IF student_index_oid IS NULL THEN
        RETURN 0.0;
    END IF;
    
    -- Сравниваем колонки
    EXECUTE format('
        SELECT COUNT(*) FROM (
            SELECT i.indkey
            FROM pg_index i
            WHERE i.indexrelid = %L
            EXCEPT
            SELECT i.indkey
            FROM pg_index i
            WHERE i.indexrelid = %L
        ) AS diff',
        teacher_index_oid, student_index_oid)
    INTO match_count;
    
    -- Возвращаем результат
    RETURN CASE WHEN match_count = 0 THEN 1.0 ELSE 0.0 END;
END;
$$ LANGUAGE plpgsql;
