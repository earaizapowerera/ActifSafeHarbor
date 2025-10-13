-- =============================================
-- Script para asegurar que tabla Calculo_RMF existe
-- =============================================

-- Solo crear la tabla si NO existe
IF OBJECT_ID('dbo.Calculo_RMF', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Calculo_RMF (
        -- PK
        ID_Calculo BIGINT IDENTITY(1,1) PRIMARY KEY,

        -- Referencias
        ID_Staging BIGINT NOT NULL,
        ID_Compania INT NOT NULL,
        ID_NUM_ACTIVO INT NOT NULL,
        Año_Calculo INT NOT NULL,

        -- Clasificación del activo
        Tipo_Activo NVARCHAR(50) NOT NULL,
        ID_PAIS INT NOT NULL,

        -- Ruta de cálculo
        Ruta_Calculo NVARCHAR(20) NOT NULL,
        Descripcion_Ruta NVARCHAR(200) NOT NULL,

        -- Datos de entrada
        MOI DECIMAL(18,4) NOT NULL,
        Tasa_Mensual DECIMAL(10,6) NOT NULL,
        Dep_Acum_Inicio DECIMAL(18,4) NOT NULL,

        -- Meses calculados
        Meses_Uso_Inicio_Ejercicio INT NOT NULL,
        Meses_Uso_Hasta_Mitad_Periodo INT NOT NULL,
        Meses_Uso_En_Ejercicio INT NOT NULL,

        -- Cálculos intermedios
        Saldo_Inicio_Año DECIMAL(18,4) NOT NULL,
        Dep_Fiscal_Ejercicio DECIMAL(18,4) NOT NULL,
        Monto_Pendiente DECIMAL(18,4) NULL,
        Proporcion DECIMAL(18,4) NULL,

        -- Regla 10% MOI
        Prueba_10_Pct_MOI DECIMAL(18,4) NULL,
        Aplica_10_Pct BIT NULL,

        -- Actualización INPC
        INPC_Adqu DECIMAL(18,6) NULL,
        INPC_Mitad_Ejercicio DECIMAL(18,6) NULL,
        INPC_Mitad_Periodo DECIMAL(18,6) NULL,
        Factor_Actualizacion_Saldo DECIMAL(10,6) NULL,
        Factor_Actualizacion_Dep DECIMAL(10,6) NULL,
        Saldo_Actualizado DECIMAL(18,4) NULL,
        Dep_Actualizada DECIMAL(18,4) NULL,
        Valor_Promedio DECIMAL(18,4) NULL,

        -- Tipo de cambio
        Tipo_Cambio_30_Junio DECIMAL(10,6) NULL,

        -- Resultado final
        Valor_Reportable_MXN DECIMAL(18,4) NOT NULL,

        -- Observaciones
        Observaciones NVARCHAR(500) NULL,

        -- Control
        Fecha_Calculo DATETIME NOT NULL DEFAULT GETDATE(),
        Lote_Calculo UNIQUEIDENTIFIER NOT NULL,
        Version_SP NVARCHAR(20) NOT NULL,

        -- FK
        CONSTRAINT FK_Calculo_Staging FOREIGN KEY (ID_Staging)
            REFERENCES dbo.Staging_Activo(ID_Staging)
    );

    PRINT 'Tabla Calculo_RMF creada';
END
ELSE
BEGIN
    PRINT 'Tabla Calculo_RMF ya existe';
END
GO

-- Crear indexes solo si no existen
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Calculo_Compania_Año' AND object_id = OBJECT_ID('dbo.Calculo_RMF'))
    CREATE INDEX IX_Calculo_Compania_Año ON dbo.Calculo_RMF(ID_Compania, Año_Calculo);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Calculo_Ruta' AND object_id = OBJECT_ID('dbo.Calculo_RMF'))
    CREATE INDEX IX_Calculo_Ruta ON dbo.Calculo_RMF(Ruta_Calculo);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Calculo_Lote' AND object_id = OBJECT_ID('dbo.Calculo_RMF'))
    CREATE INDEX IX_Calculo_Lote ON dbo.Calculo_RMF(Lote_Calculo);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Calculo_TipoActivo' AND object_id = OBJECT_ID('dbo.Calculo_RMF'))
    CREATE INDEX IX_Calculo_TipoActivo ON dbo.Calculo_RMF(Tipo_Activo);
GO
