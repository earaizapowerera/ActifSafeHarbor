-- =============================================
-- Tablas auxiliares para lógica INPC según SAT
-- =============================================

USE Actif_RMF;
GO

-- Tabla 1: INPCSegunMes
-- Mapeo del mes de cálculo al mes INPC correspondiente (para activos activos)
IF OBJECT_ID('dbo.INPCSegunMes', 'U') IS NOT NULL
    DROP TABLE dbo.INPCSegunMes;
GO

CREATE TABLE dbo.INPCSegunMes (
    MesCalculo INT NOT NULL,
    MesINPC INT NOT NULL,
    AñoINPC INT NOT NULL,
    CONSTRAINT PK_INPCSegunMes PRIMARY KEY (MesCalculo)
);
GO

INSERT INTO dbo.INPCSegunMes (MesCalculo, MesINPC, AñoINPC) VALUES
(1, 1, 0),   -- Enero → Enero mismo año
(2, 1, 0),   -- Febrero → Enero mismo año
(3, 1, 0),   -- Marzo → Enero mismo año
(4, 2, 0),   -- Abril → Febrero mismo año
(5, 2, 0),   -- Mayo → Febrero mismo año
(6, 3, 0),   -- Junio → Marzo mismo año
(7, 3, 0),   -- Julio → Marzo mismo año
(8, 4, 0),   -- Agosto → Abril mismo año
(9, 4, 0),   -- Septiembre → Abril mismo año
(10, 5, 0),  -- Octubre → Mayo mismo año
(11, 5, 0),  -- Noviembre → Mayo mismo año
(12, 6, 0);  -- Diciembre → Junio mismo año (Safe Harbor anual)
GO

-- Tabla 2: INPCbajas
-- Mapeo del mes anterior a la baja al mes INPC correspondiente
IF OBJECT_ID('dbo.INPCbajas', 'U') IS NOT NULL
    DROP TABLE dbo.INPCbajas;
GO

CREATE TABLE dbo.INPCbajas (
    Id_Mes INT NOT NULL,
    Id_MesINPC INT NOT NULL,
    AñoINPC INT NOT NULL,
    CONSTRAINT PK_INPCbajas PRIMARY KEY (Id_Mes)
);
GO

INSERT INTO dbo.INPCbajas (Id_Mes, Id_MesINPC, AñoINPC) VALUES
(1, 1, 0),   -- Enero → Enero mismo año
(2, 1, 0),   -- Febrero → Enero mismo año
(3, 1, 0),   -- Marzo → Enero mismo año
(4, 2, 0),   -- Abril → Febrero mismo año
(5, 2, 0),   -- Mayo → Febrero mismo año
(6, 3, 0),   -- Junio → Marzo mismo año
(7, 3, 0),   -- Julio → Marzo mismo año
(8, 4, 0),   -- Agosto → Abril mismo año
(9, 4, 0),   -- Septiembre → Abril mismo año
(10, 5, 0),  -- Octubre → Mayo mismo año
(11, 5, 0),  -- Noviembre → Mayo mismo año
(12, 6, 0);  -- Diciembre → Junio mismo año
GO

-- Tabla 3: inpcdeprec
-- Mapeo del mes de fin de depreciación al mes INPC correspondiente
IF OBJECT_ID('dbo.inpcdeprec', 'U') IS NOT NULL
    DROP TABLE dbo.inpcdeprec;
GO

CREATE TABLE dbo.inpcdeprec (
    Id_Mes_Fin_Deprec INT NOT NULL,
    Id_Mes_INPC INT NOT NULL,
    AñoINPC INT NOT NULL,
    CONSTRAINT PK_inpcdeprec PRIMARY KEY (Id_Mes_Fin_Deprec)
);
GO

INSERT INTO dbo.inpcdeprec (Id_Mes_Fin_Deprec, Id_Mes_INPC, AñoINPC) VALUES
(1, 6, -1),  -- Enero → Junio año anterior
(2, 1, 0),   -- Febrero → Enero mismo año
(3, 1, 0),   -- Marzo → Enero mismo año
(4, 2, 0),   -- Abril → Febrero mismo año
(5, 2, 0),   -- Mayo → Febrero mismo año
(6, 3, 0),   -- Junio → Marzo mismo año
(7, 3, 0),   -- Julio → Marzo mismo año
(8, 4, 0),   -- Agosto → Abril mismo año
(9, 4, 0),   -- Septiembre → Abril mismo año
(10, 5, 0),  -- Octubre → Mayo mismo año
(11, 5, 0),  -- Noviembre → Mayo mismo año
(12, 6, 0);  -- Diciembre → Junio mismo año
GO

PRINT 'Tablas auxiliares INPC creadas exitosamente';
GO
