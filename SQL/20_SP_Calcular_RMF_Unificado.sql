-- ====================================================================================
-- Stored Procedure: sp_Calcular_RMF_Unificado
-- Descripción: Calcula RMF para TODOS los activos (extranjeros y nacionales)
--              Usa clasificación por slots de costo (COSTO_REEXPRESADO vs COSTO_REVALUADO)
--              Aplica fórmulas diferentes según tipo de activo
-- Versión: 3.0.0 - Unificado con fórmulas correctas del Excel
-- Autor: Sistema ActifRMF
-- Fecha: 2025-10-29
-- ====================================================================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Unificado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Unificado;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Unificado
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '3.0.0-Unificado';
    DECLARE @Registros_Procesados INT = 0;
    DECLARE @Registros_Extranjeros INT = 0;
    DECLARE @Registros_Nacionales INT = 0;
    DECLARE @Registros_Ambiguos INT = 0;

    -- Obtener tipo de cambio del 30 de junio
    DECLARE @Tipo_Cambio_30_Junio DECIMAL(10,6);

    SELECT @Tipo_Cambio_30_Junio = Tipo_Cambio
    FROM dbo.Tipo_Cambio
    WHERE Año = @Año_Calculo
      AND MONTH(Fecha) = 6
      AND DAY(Fecha) = 30
      AND ID_Moneda = 2; -- USD

    IF @Tipo_Cambio_30_Junio IS NULL
    BEGIN
        RAISERROR('No se encontró tipo de cambio para el 30 de junio de %d', 16, 1, @Año_Calculo);
        RETURN;
    END

    PRINT '==========================================';
    PRINT 'CÁLCULO RMF UNIFICADO (V3.0)';
    PRINT '==========================================';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR);
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR);
    PRINT 'Tipo Cambio 30-Jun: ' + CAST(@Tipo_Cambio_30_Junio AS VARCHAR);
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50));
    PRINT '';

    -- ====================================================================================
    -- PASO 1: DETECTAR Y REPORTAR ACTIVOS AMBIGUOS
    -- ====================================================================================

    SELECT @Registros_Ambiguos = COUNT(*)
    FROM dbo.Staging_Activo
    WHERE ID_Compania = @ID_Compania
      AND Año_Calculo = @Año_Calculo
      AND Lote_Importacion = @Lote_Importacion
      AND COSTO_REEXPRESADO > 0
      AND COSTO_REVALUADO > 0;

    IF @Registros_Ambiguos > 0
    BEGIN
        PRINT '⚠️ ADVERTENCIA: Se encontraron ' + CAST(@Registros_Ambiguos AS VARCHAR) + ' activos ambiguos';
        PRINT '   (tienen ambos: COSTO_REEXPRESADO y COSTO_REVALUADO > 0)';
        PRINT '   Estos activos NO se procesarán y deben corregirse en sistema origen.';
        PRINT '';

        -- Insertar en tabla de log de ambigüedad
        INSERT INTO dbo.Log_Activos_Ambiguos (
            ID_Staging, ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
            COSTO_REEXPRESADO, COSTO_REVALUADO,
            Lote_Calculo, Fecha_Deteccion
        )
        SELECT
            ID_Staging, ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, DESCRIPCION,
            COSTO_REEXPRESADO, COSTO_REVALUADO,
            @Lote_Calculo, GETDATE()
        FROM dbo.Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND Lote_Importacion = @Lote_Importacion
          AND COSTO_REEXPRESADO > 0
          AND COSTO_REVALUADO > 0;
    END

    -- ====================================================================================
    -- PASO 2: PROCESAR ACTIVOS EXTRANJEROS
    -- Criterio: COSTO_REEXPRESADO > 0 AND COSTO_REVALUADO = 0
    -- Fórmula: SIN INPC, CON regla 10% MOI mínimo
    -- ====================================================================================

    PRINT '==========================================';
    PRINT 'PROCESANDO ACTIVOS EXTRANJEROS';
    PRINT '==========================================';

    INSERT INTO dbo.Calculo_RMF (
        ID_Staging, ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, Año_Calculo,
        Tipo_Activo, Descripcion, ID_PAIS, Nombre_Pais,

        -- Datos base
        MOI, Tasa_Anual, Tasa_Mensual,
        FECHA_COMPRA, FECHA_BAJA,

        -- Cálculos
        Meses_Uso_Inicio_Ejercicio,
        Meses_Uso_Hasta_Mitad_Periodo,
        Meses_Uso_En_Ejercicio,

        Dep_Acum_Inicio_Año,
        Saldo_Inicio_Año,
        Dep_Fiscal_Ejercicio,
        Monto_Pendiente,
        Proporcion,
        Prueba_10_Pct_MOI,
        Aplica_10_Pct,

        -- Resultado
        Valor_Reportable_USD,
        Tipo_Cambio_30_Junio,
        Valor_Reportable_MXN,

        -- Metadatos
        Ruta_Calculo,
        Descripcion_Ruta,
        Observaciones,
        Fuente_Dep_Acum,
        Lote_Calculo,
        Fecha_Calculo,
        Version_SP
    )
    SELECT
        s.ID_Staging,
        s.ID_Compania,
        s.ID_NUM_ACTIVO,
        s.ID_ACTIVO,
        s.Año_Calculo,

        'Extranjero' AS Tipo_Activo,
        s.DESCRIPCION,
        s.ID_PAIS,
        s.Nombre_Pais,

        -- Datos base: Usar COSTO_REEXPRESADO para extranjeros
        s.COSTO_REEXPRESADO AS MOI,
        s.Tasa_Anual,
        s.Tasa_Mensual,
        s.FECHA_COMPRA,
        s.FECHA_BAJA,

        -- Meses de uso al inicio del ejercicio (hasta 31-Dic año anterior)
        CASE
            WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo - 1 AS VARCHAR) + '-12-31' AS DATE)) + 1
            ELSE 0
        END AS Meses_Uso_Inicio_Ejercicio,

        -- Meses de uso hasta la MITAD del periodo (CRÍTICO para extranjeros)
        CASE
            -- Caso: Dado de baja en el año
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                THEN CASE
                    WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA)
                    ELSE 6
                END

            -- Caso: Activo existente (adquirido antes del año)
            WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                THEN 6  -- Enero a Junio completo

            -- Caso: Activo adquirido en el año ANTES de junio
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))

            -- Caso: Activo adquirido DESPUÉS de junio
            -- Usa la mitad del periodo desde adquisición hasta diciembre
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                THEN (13 - MONTH(s.FECHA_COMPRA)) / 2

            ELSE 6
        END AS Meses_Uso_Hasta_Mitad_Periodo,

        -- Meses de uso en el ejercicio completo
        CASE
            -- Caso: Dado de baja en el año
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                THEN MONTH(s.FECHA_BAJA)

            -- Caso: Activo adquirido en el año
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                THEN 13 - MONTH(s.FECHA_COMPRA)

            -- Caso: Activo existente
            ELSE 12
        END AS Meses_Uso_En_Ejercicio,

        -- Depreciación acumulada al inicio del año
        -- Prioridad: 1) Fiscal simulado, 2) Fiscal real
        COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio_Año,

        -- Saldo por deducir ISR al inicio del año
        s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0) AS Saldo_Inicio_Año,

        -- Depreciación fiscal del ejercicio (hasta MITAD del periodo)
        s.COSTO_REEXPRESADO * s.Tasa_Mensual *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                    THEN 6
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                    THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                    THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                ELSE 6
            END AS Dep_Fiscal_Ejercicio,

        -- Monto pendiente por deducir
        (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
            (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                CASE
                    WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                        THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                    WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                        THEN 6
                    WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                        THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                    WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                        THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                    ELSE 6
                END
            ) AS Monto_Pendiente,

        -- Proporción del monto pendiente (fórmula Excel: Monto_Pendiente / 12 * Meses_Ejercicio)
        (
            (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
            (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                CASE
                    WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                        THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                    WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                        THEN 6
                    WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                        THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                    WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                        THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                    ELSE 6
                END
            )
        ) / 12.0 *
        CASE
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                THEN MONTH(s.FECHA_BAJA)
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                THEN 13 - MONTH(s.FECHA_COMPRA)
            ELSE 12
        END AS Proporcion,

        -- Prueba 10% MOI
        s.COSTO_REEXPRESADO * 0.10 AS Prueba_10_Pct_MOI,

        -- Aplica regla 10% MOI (si proporción < 10% MOI)
        CASE
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                    CASE
                        WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                            THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                        WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                            THEN 6
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                        ELSE 6
                    END
                )
            ) / 12.0 *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN MONTH(s.FECHA_BAJA)
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                    THEN 13 - MONTH(s.FECHA_COMPRA)
                ELSE 12
            END <= (s.COSTO_REEXPRESADO * 0.10)
        THEN 1 ELSE 0
        END AS Aplica_10_Pct,

        -- VALOR REPORTABLE EN USD (con regla 10% MOI)
        CASE
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                    CASE
                        WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                            THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                        WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                            THEN 6
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                        ELSE 6
                    END
                )
            ) / 12.0 *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN MONTH(s.FECHA_BAJA)
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                    THEN 13 - MONTH(s.FECHA_COMPRA)
                ELSE 12
            END > (s.COSTO_REEXPRESADO * 0.10)
        THEN
            -- Usar proporción calculada
            (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                    CASE
                        WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                            THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                        WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                            THEN 6
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                        ELSE 6
                    END
                )
            ) / 12.0 *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN MONTH(s.FECHA_BAJA)
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                    THEN 13 - MONTH(s.FECHA_COMPRA)
                ELSE 12
            END
        ELSE
            -- Usar 10% MOI mínimo
            s.COSTO_REEXPRESADO * 0.10
        END AS Valor_Reportable_USD,

        -- Tipo de cambio
        @Tipo_Cambio_30_Junio AS Tipo_Cambio_30_Junio,

        -- VALOR REPORTABLE EN MXN (USD × TC)
        (CASE
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                    CASE
                        WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                            THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                        WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                            THEN 6
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                        ELSE 6
                    END
                )
            ) / 12.0 *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN MONTH(s.FECHA_BAJA)
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                    THEN 13 - MONTH(s.FECHA_COMPRA)
                ELSE 12
            END > (s.COSTO_REEXPRESADO * 0.10)
        THEN
            (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual *
                    CASE
                        WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                            THEN CASE WHEN MONTH(s.FECHA_BAJA) <= 6 THEN MONTH(s.FECHA_BAJA) ELSE 6 END
                        WHEN YEAR(s.FECHA_COMPRA) < @Año_Calculo
                            THEN 6
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN DATEDIFF(MONTH, s.FECHA_COMPRA, CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE))
                        WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                            THEN (13 - MONTH(s.FECHA_COMPRA)) / 2
                        ELSE 6
                    END
                )
            ) / 12.0 *
            CASE
                WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                    THEN MONTH(s.FECHA_BAJA)
                WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo
                    THEN 13 - MONTH(s.FECHA_COMPRA)
                ELSE 12
            END
        ELSE
            s.COSTO_REEXPRESADO * 0.10
        END) * @Tipo_Cambio_30_Junio AS Valor_Reportable_MXN,

        -- Ruta de cálculo
        CASE
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo THEN 'EXT-BAJA'
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE) THEN 'EXT-ANTES-JUN'
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE) THEN 'EXT-DESP-JUN'
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual * 6)
            ) / 12.0 * 12 <= (s.COSTO_REEXPRESADO * 0.10) THEN 'EXT-10PCT'
            ELSE 'EXT-NORMAL'
        END AS Ruta_Calculo,

        -- Descripción de la ruta
        CASE
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo THEN 'Activo extranjero dado de baja en ' + CAST(@Año_Calculo AS VARCHAR)
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE) THEN 'Activo extranjero adquirido antes de junio ' + CAST(@Año_Calculo AS VARCHAR)
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE) THEN 'Activo extranjero adquirido después de junio ' + CAST(@Año_Calculo AS VARCHAR)
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual * 6)
            ) / 12.0 * 12 <= (s.COSTO_REEXPRESADO * 0.10) THEN 'Activo extranjero con regla 10% MOI (Art 182 LISR)'
            ELSE 'Activo extranjero en uso normal en ' + CAST(@Año_Calculo AS VARCHAR)
        END AS Descripcion_Ruta,

        -- Observaciones
        CASE
            WHEN s.FECHA_BAJA IS NOT NULL AND YEAR(s.FECHA_BAJA) = @Año_Calculo
                THEN 'Activo dado de baja en ' + DATENAME(MONTH, s.FECHA_BAJA) + ' ' + CAST(YEAR(s.FECHA_BAJA) AS VARCHAR)
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                THEN 'Activo adquirido en 2024 antes de junio'
            WHEN YEAR(s.FECHA_COMPRA) = @Año_Calculo AND s.FECHA_COMPRA > CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE)
                THEN 'Activo adquirido en 2024 después de junio. Depreciación a mitad del periodo'
            WHEN (
                (s.COSTO_REEXPRESADO - COALESCE(fs.Dep_Acum_Año_Anterior_Simulada, s.Dep_Acum_Inicio_Año, 0)) -
                (s.COSTO_REEXPRESADO * s.Tasa_Mensual * 6)
            ) / 12.0 * 12 <= (s.COSTO_REEXPRESADO * 0.10)
                THEN 'Activo en uso prueba 10% MOI - Proporción menor a 10% del MOI'
            ELSE 'Activo en uso en ' + CAST(@Año_Calculo AS VARCHAR)
        END AS Observaciones,

        -- Fuente depreciación acumulada
        CASE
            WHEN fs.Dep_Acum_Año_Anterior_Simulada IS NOT NULL THEN 'Fiscal Simulado'
            WHEN s.Dep_Acum_Inicio_Año IS NOT NULL AND s.Dep_Acum_Inicio_Año > 0 THEN 'Fiscal Real'
            ELSE 'Sin Depreciación'
        END AS Fuente_Dep_Acum,

        -- Control
        @Lote_Calculo,
        GETDATE(),
        @Version_SP

    FROM dbo.Staging_Activo s

    -- JOIN con fiscal simulado (si existe)
    LEFT JOIN dbo.Calculo_Fiscal_Simulado fs
        ON s.ID_Staging = fs.ID_Staging
        AND fs.Año_Calculo = @Año_Calculo

    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.Lote_Importacion = @Lote_Importacion
      AND s.COSTO_REEXPRESADO > 0          -- Tiene costo USGAAP
      AND ISNULL(s.COSTO_REVALUADO, 0) = 0 -- NO tiene costo fiscal
      AND s.STATUS = 'A';                   -- Solo activos activos

    SET @Registros_Extranjeros = @@ROWCOUNT;
    PRINT 'Activos extranjeros calculados: ' + CAST(@Registros_Extranjeros AS VARCHAR);
    PRINT '';

    -- ====================================================================================
    -- PASO 3: PROCESAR ACTIVOS NACIONALES/MEXICANOS
    -- Criterio: COSTO_REVALUADO > 0 AND COSTO_REEXPRESADO = 0
    -- Fórmula: CON INPC, valor promedio, SIN regla 10% MOI
    -- ====================================================================================

    -- TODO: Implementar cálculo de activos nacionales
    -- (Se implementará en el siguiente paso, por ahora solo extranjeros)

    PRINT '==========================================';
    PRINT 'ACTIVOS NACIONALES: Por implementar';
    PRINT '==========================================';
    PRINT '';

    -- ====================================================================================
    -- PASO 4: RESUMEN
    -- ====================================================================================

    SET @Registros_Procesados = @Registros_Extranjeros + @Registros_Nacionales;

    PRINT '==========================================';
    PRINT 'RESUMEN DEL CÁLCULO';
    PRINT '==========================================';
    PRINT 'Total activos procesados: ' + CAST(@Registros_Procesados AS VARCHAR);
    PRINT '  - Extranjeros: ' + CAST(@Registros_Extranjeros AS VARCHAR);
    PRINT '  - Nacionales: ' + CAST(@Registros_Nacionales AS VARCHAR);
    PRINT '  - Ambiguos (no procesados): ' + CAST(@Registros_Ambiguos AS VARCHAR);
    PRINT '';

    -- Retornar resultado
    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        @Registros_Procesados AS Total_Activos,
        @Registros_Extranjeros AS Activos_Extranjeros,
        @Registros_Nacionales AS Activos_Nacionales,
        @Registros_Ambiguos AS Activos_Ambiguos,
        SUM(CASE WHEN Tipo_Activo = 'Extranjero' THEN Valor_Reportable_MXN ELSE 0 END) AS Total_Valor_Extranjeros_MXN,
        SUM(CASE WHEN Tipo_Activo = 'Nacional' THEN Valor_Reportable_MXN ELSE 0 END) AS Total_Valor_Nacionales_MXN,
        SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable_MXN,
        COUNT(CASE WHEN Aplica_10_Pct = 1 THEN 1 END) AS Activos_Con_Regla_10_Pct,
        COUNT(CASE WHEN Fuente_Dep_Acum = 'Fiscal Simulado' THEN 1 END) AS Activos_Con_Fiscal_Simulado,
        @Lote_Calculo AS Lote_Calculo
    FROM dbo.Calculo_RMF
    WHERE Lote_Calculo = @Lote_Calculo
    GROUP BY @ID_Compania, @Año_Calculo, @Lote_Calculo;

    PRINT '==========================================';
    PRINT 'CÁLCULO COMPLETADO';
    PRINT '==========================================';

END
GO

PRINT 'Stored Procedure sp_Calcular_RMF_Unificado creado exitosamente (v3.0.0)';
GO
