-- =============================================
-- Script: Modificación a sp_Calcular_RMF_Safe_Harbor
-- Descripción: Integra el cálculo fiscal simulado
--              Usa Dep_Acum_Año_Anterior_Simulada cuando existe
-- Versión: 2.0.0 - Con fiscal simulado integrado
-- =============================================

USE Actif_RMF;
GO

/*
NOTA: Este script muestra la lógica de integración.
Para implementar, modificar sp_Calcular_RMF_Safe_Harbor existente.

CAMBIO PRINCIPAL:
En lugar de usar directamente s.Dep_Acum_Inicio_Año,
primero intentar obtener de Calculo_Fiscal_Simulado.

PSEUDO-CÓDIGO DE LA MODIFICACIÓN:

    -- ANTES (línea ~50-60 del SP original):
    @Dep_Acum = s.Dep_Acum_Inicio_Año

    -- DESPUÉS:
    @Dep_Acum = ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año)

    -- Y agregar LEFT JOIN:
    LEFT JOIN Calculo_Fiscal_Simulado fs
        ON s.ID_Staging = fs.ID_Staging
        AND fs.Año_Calculo = @Año_Calculo
*/

-- =============================================
-- EJEMPLO DE INTEGRACIÓN
-- =============================================

IF OBJECT_ID('dbo.sp_Calcular_RMF_Safe_Harbor_V2', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Safe_Harbor_V2;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Safe_Harbor_V2
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Registros_Procesados INT = 0;

    PRINT '=========================================='
    PRINT 'CÁLCULO RMF SAFE HARBOR V2'
    PRINT 'Con Fiscal Simulado Integrado'
    PRINT '=========================================='
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR)
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR)
    PRINT ''

    -- =============================================
    -- CALCULAR RMF CON FISCAL SIMULADO
    -- =============================================

    INSERT INTO dbo.Calculo_RMF (
        ID_Staging, ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO,
        Año_Calculo, Tipo_Activo, Descripcion,
        Costo_Original_MXN, ID_PAIS, Nombre_Pais,
        Dep_Acum_Año_Anterior, Fuente_Dep_Acum,
        INPC_Adquisicion, INPC_Mitad_Ejercicio, Factor_Actualizacion,
        Costo_Actualizado_MXN, Dep_Acum_Actualizada,
        MOI_Neto_Actualizado, Dep_Ejercicio_Actual,
        Aplica_10_Pct, Ajuste_10_Pct, MOI_Ajustado,
        Tasa_Pais, Valor_Reportable_MXN,
        Lote_Calculo, Fecha_Calculo, Version_SP
    )
    SELECT
        s.ID_Staging,
        s.ID_Compania,
        s.ID_NUM_ACTIVO,
        s.ID_ACTIVO,
        s.Año_Calculo,

        -- Tipo de activo
        CASE
            WHEN s.ID_PAIS = 1 THEN 'Mexicano'
            ELSE 'Extranjero'
        END AS Tipo_Activo,

        s.DESCRIPCION,

        -- Costo original en MXN
        s.CostoMXN AS Costo_Original_MXN,

        s.ID_PAIS,
        s.Nombre_Pais,

        -- *** INTEGRACIÓN FISCAL SIMULADO ***
        -- Prioridad: 1) Fiscal simulado, 2) Fiscal real del ETL
        ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año) AS Dep_Acum_Año_Anterior,

        -- Indicar la fuente de la depreciación
        CASE
            WHEN fs.Dep_Acum_Año_Anterior_Simulada IS NOT NULL THEN 'Fiscal Simulado'
            WHEN s.Dep_Acum_Inicio_Año IS NOT NULL AND s.Dep_Acum_Inicio_Año > 0 THEN 'Fiscal Real'
            ELSE 'Sin Depreciación'
        END AS Fuente_Dep_Acum,

        -- INPC (solo para mexicanos)
        s.INPC_Adquisicion,
        s.INPC_Mitad_Ejercicio,

        -- Factor de actualización (solo para mexicanos)
        CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END AS Factor_Actualizacion,

        -- Costo actualizado
        s.CostoMXN * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END AS Costo_Actualizado_MXN,

        -- Depreciación acumulada actualizada
        ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año) * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END AS Dep_Acum_Actualizada,

        -- MOI Neto Actualizado
        (s.CostoMXN * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END) - (ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año) * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END) AS MOI_Neto_Actualizado,

        -- Depreciación del ejercicio actual (6 meses)
        s.CostoMXN * (ISNULL(s.Tasa_Mensual, 0) / 100.0) * 6 AS Dep_Ejercicio_Actual,

        -- Aplica regla 10%
        CASE
            WHEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)) <= 6
                THEN 1
            ELSE 0
        END AS Aplica_10_Pct,

        -- Ajuste 10%
        CASE
            WHEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)) <= 6
                THEN (s.CostoMXN * CASE
                    WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                        THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
                    ELSE 1.0
                END) * 0.10
            ELSE 0
        END AS Ajuste_10_Pct,

        -- MOI Ajustado
        ((s.CostoMXN * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END) - (ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año) * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END)) + CASE
            WHEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)) <= 6
                THEN (s.CostoMXN * CASE
                    WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                        THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
                    ELSE 1.0
                END) * 0.10
            ELSE 0
        END AS MOI_Ajustado,

        -- Tasa del país (25% default, ajustar según necesidad)
        25.0 AS Tasa_Pais,

        -- Valor reportable (MOI Ajustado * Tasa)
        (((s.CostoMXN * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END) - (ISNULL(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año) * CASE
            WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
            ELSE 1.0
        END)) + CASE
            WHEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)) <= 6
                THEN (s.CostoMXN * CASE
                    WHEN s.ID_PAIS = 1 AND s.INPC_Adquisicion > 0
                        THEN s.INPC_Mitad_Ejercicio / s.INPC_Adquisicion
                    ELSE 1.0
                END) * 0.10
            ELSE 0
        END) * 0.25 AS Valor_Reportable_MXN,

        -- Control
        @Lote_Calculo AS Lote_Calculo,
        GETDATE() AS Fecha_Calculo,
        '2.0.0' AS Version_SP

    FROM dbo.Staging_Activo s

    -- *** JOIN CON FISCAL SIMULADO ***
    LEFT JOIN dbo.Calculo_Fiscal_Simulado fs
        ON s.ID_Staging = fs.ID_Staging
        AND fs.Año_Calculo = @Año_Calculo

    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.Lote_Importacion = @Lote_Importacion
      AND s.CostoMXN IS NOT NULL
      AND s.CostoMXN > 0;

    SET @Registros_Procesados = @@ROWCOUNT;

    PRINT 'Activos calculados: ' + CAST(@Registros_Procesados AS VARCHAR)
    PRINT ''

    -- =============================================
    -- RESUMEN
    -- =============================================

    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        @Registros_Procesados AS Total_Activos,
        COUNT(CASE WHEN Fuente_Dep_Acum = 'Fiscal Simulado' THEN 1 END) AS Con_Fiscal_Simulado,
        COUNT(CASE WHEN Fuente_Dep_Acum = 'Fiscal Real' THEN 1 END) AS Con_Fiscal_Real,
        COUNT(CASE WHEN Fuente_Dep_Acum = 'Sin Depreciación' THEN 1 END) AS Sin_Depreciacion,
        SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable_MXN,
        COUNT(CASE WHEN Aplica_10_Pct = 1 THEN 1 END) AS Con_Ajuste_10_Pct
    FROM dbo.Calculo_RMF
    WHERE Lote_Calculo = @Lote_Calculo;

    PRINT '=========================================='
    PRINT 'CÁLCULO COMPLETADO'
    PRINT '=========================================='

END
GO

PRINT 'Stored Procedure sp_Calcular_RMF_Safe_Harbor_V2 creado (Con fiscal simulado integrado)';
GO
