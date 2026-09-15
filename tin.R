library(DBI)
library(RSQLite)

con <- dbConnect(RSQLite::SQLite(), "chinook.db")

# EJERCICIO 1

# 1.1
r1 <- dbGetQuery(con, "
  SELECT
    c.FirstName || ' ' || c.LastName AS cliente,
    e.FirstName || ' ' || e.LastName AS rep,
    COALESCE(j.FirstName || ' ' || j.LastName, 'Sin jefe') AS jefe
  FROM Customer c
  INNER JOIN Employee e ON c.SupportRepId = e.EmployeeId
  LEFT JOIN Employee j ON e.ReportsTo = j.EmployeeId
  ORDER BY cliente
")
print(head(r1, 15))

# 1.2
r2 <- dbGetQuery(con, "
  SELECT
    c.CustomerId,
    c.FirstName || ' ' || c.LastName AS cliente,
    c.SupportRepId,
    ROUND((SELECT SUM(i.Total) FROM Invoice i WHERE i.CustomerId = c.CustomerId), 2) AS gasto
  FROM Customer c
  WHERE
    (SELECT SUM(i.Total) FROM Invoice i WHERE i.CustomerId = c.CustomerId)
    >
    (SELECT AVG(otros.total)
     FROM (
       SELECT c2.CustomerId, SUM(i2.Total) AS total
       FROM Customer c2
       JOIN Invoice i2 ON c2.CustomerId = i2.CustomerId
       WHERE c2.SupportRepId = c.SupportRepId AND c2.CustomerId <> c.CustomerId
       GROUP BY c2.CustomerId
     ) AS otros)
  ORDER BY gasto DESC
")
print(r2)

# 1.3
r3 <- dbGetQuery(con, "
  SELECT e.EmployeeId, e.FirstName || ' ' || e.LastName AS empleado, e.Title
  FROM Employee e
  WHERE e.EmployeeId IN (
    SELECT EmployeeId FROM Employee
    EXCEPT
    SELECT SupportRepId FROM Customer WHERE SupportRepId IS NOT NULL
  )
")
print(r3)

# 1.4
r4 <- dbGetQuery(con, "
  WITH emp_resumen AS (
    SELECT
      e.EmployeeId,
      e.FirstName || ' ' || e.LastName AS empleado,
      COUNT(DISTINCT c.CustomerId) AS clientes,
      ROUND(SUM(i.Total), 2) AS ingreso
    FROM Employee e
    JOIN Customer c ON c.SupportRepId = e.EmployeeId
    JOIN Invoice i ON i.CustomerId = c.CustomerId
    GROUP BY e.EmployeeId
  )
  SELECT * FROM emp_resumen ORDER BY ingreso DESC
")
print(r4)

# EJERCICIO 2

# 2.1
r5 <- dbGetQuery(con, "
  WITH mes AS (
    SELECT
      SUBSTR(InvoiceDate, 1, 7) AS fecha,
      ROUND(SUM(Total), 2) AS ventas
    FROM Invoice
    GROUP BY fecha
  )
  SELECT
    fecha,
    ventas,
    LAG(ventas) OVER (ORDER BY fecha) AS anterior,
    LEAD(ventas) OVER (ORDER BY fecha) AS siguiente,
    ROUND((ventas - LAG(ventas) OVER (ORDER BY fecha)) * 100.0 / 
          LAG(ventas) OVER (ORDER BY fecha), 2) AS var_pct
  FROM mes
  ORDER BY fecha
")
print(r5)

# 2.2
r6 <- dbGetQuery(con, "
  WITH mes AS (
    SELECT
      SUBSTR(InvoiceDate, 1, 4) AS anio,
      SUBSTR(InvoiceDate, 1, 7) AS fecha,
      ROUND(SUM(Total), 2) AS ventas
    FROM Invoice
    GROUP BY fecha
  ),
  rank_mes AS (
    SELECT
      anio, fecha, ventas,
      RANK() OVER (PARTITION BY anio ORDER BY ventas DESC) AS rk_top,
      RANK() OVER (PARTITION BY anio ORDER BY ventas ASC) AS rk_bot
    FROM mes
  )
  SELECT
    anio,
    MAX(CASE WHEN rk_top = 1 THEN fecha END) AS mes_mayor,
    MAX(CASE WHEN rk_top = 1 THEN ventas END) AS venta_mayor,
    MAX(CASE WHEN rk_bot = 1 THEN fecha END) AS mes_menor,
    MAX(CASE WHEN rk_bot = 1 THEN ventas END) AS venta_menor
  FROM rank_mes
  GROUP BY anio
  ORDER BY anio
")
print(r6)

# 2.3
r7 <- dbGetQuery(con, "
  WITH genero_ventas AS (
    SELECT
      SUBSTR(i.InvoiceDate, 1, 4) AS anio,
      g.Name AS genero,
      ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS ingreso
    FROM InvoiceLine il
    JOIN Invoice i ON il.InvoiceId = i.InvoiceId
    JOIN Track t ON il.TrackId = t.TrackId
    JOIN Genre g ON t.GenreId = g.GenreId
    GROUP BY anio, genero
  ),
  rank_genero AS (
    SELECT
      anio, genero, ingreso,
      RANK() OVER (PARTITION BY anio ORDER BY ingreso DESC) AS pos
    FROM genero_ventas
  )
  SELECT anio, genero, ingreso
  FROM rank_genero
  WHERE pos = 1
  ORDER BY anio
")
print(r7)

# 2.4
r8 <- dbGetQuery(con, "
  WITH gasto AS (
    SELECT c.CustomerId, SUM(i.Total) AS total
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  ),
  cuartil AS (
    SELECT CustomerId, total, NTILE(4) OVER (ORDER BY total) AS q
    FROM gasto
  ),
  resumen AS (
    SELECT q, ROUND(SUM(total), 2) AS ingreso
    FROM cuartil
    GROUP BY q
  )
  SELECT
    q,
    ingreso,
    ROUND(ingreso * 100.0 / (SELECT SUM(ingreso) FROM resumen), 2) AS pct
  FROM resumen
  ORDER BY q DESC
")
print(r8)

# EJERCICIO 3

# 3.1
r9 <- dbGetQuery(con, "SELECT MAX(InvoiceDate) AS fecha_max FROM Invoice")
print(r9)

# 3.2 y 3.3
r10 <- dbGetQuery(con, "
  WITH max_fecha AS (
    SELECT MAX(InvoiceDate) AS fecha_max FROM Invoice
  ),
  cliente_base AS (
    SELECT
      c.CustomerId,
      c.FirstName || ' ' || c.LastName AS cliente,
      MAX(i.InvoiceDate) AS fecha_compra,
      ROUND(SUM(i.Total), 2) AS gasto_total
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  ),
  segmento AS (
    SELECT
      b.*,
      ROUND((JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
             JULIANDAY(b.fecha_compra)) / 30.0, 1) AS meses_sin_compra,
      CASE
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 6 THEN 'activo'
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 12 THEN 'riesgo'
        ELSE 'inactivo'
      END AS estado
    FROM cliente_base b
  )
  SELECT * FROM segmento
")
print(head(r10, 15))

# 3.4 - Resumen
r11 <- dbGetQuery(con, "
  WITH max_fecha AS (
    SELECT MAX(InvoiceDate) AS fecha_max FROM Invoice
  ),
  cliente_base AS (
    SELECT
      c.CustomerId,
      c.FirstName || ' ' || c.LastName AS cliente,
      MAX(i.InvoiceDate) AS fecha_compra,
      ROUND(SUM(i.Total), 2) AS gasto_total
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  ),
  segmento AS (
    SELECT
      b.*,
      CASE
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 6 THEN 'activo'
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 12 THEN 'riesgo'
        ELSE 'inactivo'
      END AS estado
    FROM cliente_base b
  )
  SELECT
    estado,
    COUNT(*) AS num_clientes,
    ROUND(AVG(gasto_total), 2) AS promedio,
    ROUND(SUM(gasto_total), 2) AS total
  FROM segmento
  GROUP BY estado
  ORDER BY total DESC
")
print(r11)

# 3.4 - Top 3
r12 <- dbGetQuery(con, "
  WITH max_fecha AS (
    SELECT MAX(InvoiceDate) AS fecha_max FROM Invoice
  ),
  cliente_base AS (
    SELECT
      c.CustomerId,
      c.FirstName || ' ' || c.LastName AS cliente,
      MAX(i.InvoiceDate) AS fecha_compra,
      ROUND(SUM(i.Total), 2) AS gasto_total
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId
  ),
  segmento AS (
    SELECT
      b.*,
      CASE
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 6 THEN 'activo'
        WHEN (JULIANDAY((SELECT fecha_max FROM max_fecha)) - 
              JULIANDAY(b.fecha_compra)) / 30.0 <= 12 THEN 'riesgo'
        ELSE 'inactivo'
      END AS estado
    FROM cliente_base b
  ),
  top3 AS (
    SELECT
      estado, cliente, gasto_total,
      RANK() OVER (PARTITION BY estado ORDER BY gasto_total DESC) AS rank
    FROM segmento
  )
  SELECT estado, cliente, gasto_total, rank
  FROM top3
  WHERE rank <= 3
  ORDER BY estado, rank
")
print(r12)

dbDisconnect(con)
