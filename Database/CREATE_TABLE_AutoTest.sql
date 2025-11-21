-- =============================================
-- Tabla: AutoTest
-- Propósito: Valores esperados para casos de prueba
-- Uso: Validación automática de cálculos
-- =============================================

USE Actif_RMF;
GO

-- Eliminar tabla si existe
IF OBJECT_ID('dbo.AutoTest', 'U') IS NOT NULL
    DROP TABLE dbo.AutoTest;
GO

CREATE TABLE dbo.AutoTest (
    -- =============================================
    -- IDENTIFICACIÓN
    -- =============================================
    ID_Test BIGINT IDENTITY(1,1) PRIMARY KEY,
    Numero_Caso INT NOT NULL,                           -- 1, 2, 3, etc.
    Nombre_Caso NVARCHAR(200) NOT NULL,                 -- "Edificio totalmente depreciado"
    ID_NUM_ACTIVO INT NOT NULL,                         -- Folio del activo
    ID_Compania INT NOT NULL,
    Año_Calculo INT NOT NULL,

    -- =============================================
    -- DATOS BÁSICOS ESPERADOS
    -- =============================================
    MOI_Esperado DECIMAL(18,4) NOT NULL,
    Tasa_Anual_Esperada DECIMAL(10,6) NOT NULL,
    Tasa_Mensual_Esperada DECIMAL(10,6) NOT NULL,

    -- =============================================
    -- FECHAS ESPERADAS
    -- =============================================
    Fecha_Adquisicion_Esperada DATE NOT NULL,
    Fecha_Inicio_Depreciacion_Esperada DATE NOT NULL,
    Fecha_Fin_Depreciacion_Esperada DATE NULL,
    Fecha_Baja_Esperada DATE NULL,

    -- =============================================
    -- MESES ESPERADOS
    -- =============================================
    Meses_Uso_Inicio_Ejercicio_Esperado INT NOT NULL,
    Meses_Uso_En_Ejercicio_Esperado INT NOT NULL,

    -- =============================================
    -- DEPRECIACIÓN ESPERADA
    -- =============================================
    Dep_Acum_Inicio_Esperada DECIMAL(18,4) NOT NULL,
    Saldo_Inicio_Año_Esperado DECIMAL(18,4) NOT NULL,
    Dep_Fiscal_Ejercicio_Esperada DECIMAL(18,4) NOT NULL,

    -- =============================================
    -- INPC ESPERADOS
    -- =============================================
    INPCCompra_Esperado DECIMAL(18,6) NOT NULL,
    INPC_Mitad_Ejercicio_Esperado DECIMAL(18,6) NOT NULL,
    INPC_Mitad_Periodo_Esperado DECIMAL(18,6) NOT NULL,

    -- =============================================
    -- FACTORES FISCALES ESPERADOS
    -- =============================================
    Factor_Actualizacion_Saldo_Esperado DECIMAL(18,10) NOT NULL,
    Factor_Actualizacion_Dep_Esperado DECIMAL(18,10) NOT NULL,
    Saldo_Actualizado_Esperado DECIMAL(18,4) NOT NULL,
    Dep_Actualizada_Esperada DECIMAL(18,4) NOT NULL,
    Valor_Promedio_Esperado DECIMAL(18,4) NOT NULL,
    Proporcion_Esperada DECIMAL(18,4) NOT NULL,

    -- =============================================
    -- SAFE HARBOR ESPERADO
    -- =============================================
    INPC_SH_Junio_Esperado DECIMAL(18,6) NOT NULL,
    Factor_SH_Esperado DECIMAL(18,10) NOT NULL,
    Saldo_SH_Actualizado_Esperado DECIMAL(18,4) NOT NULL,
    Dep_SH_Actualizada_Esperada DECIMAL(18,4) NOT NULL,
    Valor_SH_Promedio_Esperado DECIMAL(18,4) NOT NULL,
    Proporcion_SH_Esperada DECIMAL(18,4) NOT NULL,

    -- =============================================
    -- VALORES FINALES ESPERADOS
    -- =============================================
    Prueba_10_Pct_MOI_Esperada DECIMAL(18,4) NOT NULL,
    Valor_Reportable_MXN_Esperado DECIMAL(18,4) NOT NULL,
    Valor_SH_Reportable_Esperado DECIMAL(18,4) NOT NULL,
    Aplica_10_Pct_Esperado BIT NOT NULL,

    -- =============================================
    -- TOLERANCIA Y CONTROL
    -- =============================================
    Tolerancia_Decimal DECIMAL(18,4) DEFAULT 0.01,     -- Tolerancia ±0.01
    Activo BIT DEFAULT 1,                               -- 1=Activo, 0=Desactivado
    Fecha_Creacion DATETIME DEFAULT GETDATE(),
    Usuario_Creacion NVARCHAR(100) DEFAULT SUSER_NAME(),
    Observaciones NVARCHAR(MAX) NULL
);
GO

-- Índices
CREATE INDEX IX_AutoTest_Caso ON AutoTest(Numero_Caso);
CREATE INDEX IX_AutoTest_Folio ON AutoTest(ID_NUM_ACTIVO, Año_Calculo);
CREATE INDEX IX_AutoTest_Compania ON AutoTest(ID_Compania, Año_Calculo);
GO

PRINT 'Tabla AutoTest creada exitosamente';
GO
