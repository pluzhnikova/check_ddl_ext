# check_ddl_ext
PostgreSQL extension for ddl-queries validation

# Getting started
After cloning repo, copy extension files to your PostgreSQL extension directory:
```
sudo cp check_ddl_ext* $(pg_config --sharedir)/extension/
```

Or if you want to specify the PostgreSQL version manually:
```
sudo cp check_ddl_ext* /usr/share/postgresql/<version>/extension/
```

In psql, proceed with the classic approach:
```
CREATE EXTENSION check_ddl_ext;
```
## Provided features
This extension provides the following functions:
- check_table_structure(student_schema, teacher_schema, sql_query)
- check_view(student_schema, teacher_schema, sql_query)
- check_materialized_view(student_schema, teacher_schema, sql_query)
- check_constraints(student_schema, teacher_schema, sql_query)
- check_sequence(student_schema, teacher_schema, sql_query)
- check_trigger(student_schema, teacher_schema, sql_query)
- check_index(student_schema, teacher_schema, sql_query)

## Usage examples
In usage_examples.md you can find some ways to use these functions.
