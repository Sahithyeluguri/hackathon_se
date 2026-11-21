-- Seed data for the Employee Portal (runs once when the db container is created)
CREATE TABLE employees (
    id      INT PRIMARY KEY,
    name    TEXT NOT NULL,
    dept    TEXT NOT NULL,
    role    TEXT NOT NULL,
    salary  INT  NOT NULL
);
INSERT INTO employees VALUES
 (1, 'Asha Rao',      'Engineering', 'Engineer',        85000),
 (2, 'Vikram Shah',   'Finance',     'Accountant',      64000),
 (3, 'Meera Iyer',    'HR',          'HR Manager',      72000),
 (4, 'Rahul Verma',   'IT',          'SysAdmin',        78000),
 (5, 'Divya Menon',   'Sales',       'Sales Lead',      69000);
