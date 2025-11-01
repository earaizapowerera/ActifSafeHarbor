-- =============================================
-- Stored Procedure: sp_ETL_Importar_Activos_Directo
-- Descripción: ETL simplificado que usa cross-database queries directas
--              (sin OPENROWSET, para SQL Server Linux)
-- Versión: 1.0.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_ETL_Importar_Activos_Directo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ETL_Importar_Activos_Directo;
GO

CREATE PROCEDURE dbo.sp_ETL_Importar_Activos_Directo
    @ID_Compania INT,
    @Año_Calculo INT,
    @Usuario NVARCHAR(100) = 'Sistema'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Lote_Importacion UNIQUEIDENTIFIER = NEWID();
    DECLARE @ID_Log BIGINT;
    DECLARE @Fecha_Inicio DATETIME = GETDATE();
    DECLARE @Registros_Procesados INT = 0;
    DECLARE @Mensaje_Error NVARCHAR(MAX) = NULL;
    DECLARE @Nombre_Compania NVARCHAR(200);
    DECLARE @Año_Anterior INT = @Año_Calculo - 1;

    BEGIN TRY
        -- =============================================
        -- 1. VALIDACIONES
        -- =============================================

        SELECT @Nombre_Compania = Nombre_Compania
        FROM dbo.ConfiguracionCompania
        WHERE ID_Compania = @ID_Compania
          AND Activo = 1;

        IF @Nombre_Compania IS NULL
        BEGIN
            RAISERROR('La compañía %d no existe o no está activa', 16, 1, @ID_Compania);
            RETURN;
        END

        PRINT '==================================='
        PRINT 'ETL IMPORTACIÓN DIRECTA (CROSS-DATABASE)'
        PRINT '==================================='
        PRINT 'Compañía: ' + @Nombre_Compania + ' (ID: ' + CAST(@ID_Compania AS VARCHAR) + ')'
        PRINT 'Año Cálculo: ' + CAST(@Año_Calculo AS VARCHAR)
        PRINT 'Lote: ' + CAST(@Lote_Importacion AS VARCHAR(50))
        PRINT ''

        -- =============================================
        -- 2. REGISTRAR INICIO DE PROCESO EN LOG
        -- =============================================

        INSERT INTO dbo.Log_Ejecucion_ETL
            (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
             Fecha_Inicio, Estado, Usuario)
        VALUES
            (@ID_Compania, @Año_Calculo, @Lote_Importacion, 'ETL_DIRECTO',
             @Fecha_Inicio, 'En Proceso', @Usuario);

        SET @ID_Log = SCOPE_IDENTITY();

        -- =============================================
        -- 3. IMPORTAR DATOS (CROSS-DATABASE QUERY)
        -- =============================================

        PRINT 'Ejecutando importación...'
        PRINT ''

        INSERT INTO Actif_RMF.dbo.Staging_Activo
            (ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
             Nombre_TipoActivo, DESCRIPCION, COSTO_ADQUISICION, ID_MONEDA, Nombre_Moneda,
             ID_PAIS, Nombre_Pais, FECHA_COMPRA, FECHA_BAJA, FECHA_INICIO_DEP, STATUS,
             FLG_PROPIO, Tasa_Anual, Tasa_Mensual, Dep_Acum_Inicio_Año,
             INPC_Adquisicion, INPC_Mitad_Ejercicio,
             FLG_NOCAPITALIZABLE_2, FLG_NOCAPITALIZABLE_3,
             FECHA_INIC_DEPREC_3, COSTO_REEXPRESADO, Costo_Fiscal,
             Año_Calculo, Lote_Importacion)
        SELECT
            -- Identificación
            @ID_Compania AS ID_Compania,
            a.ID_NUM_ACTIVO,
            a.ID_ACTIVO AS Placa,
            a.ID_TIPO_ACTIVO,
            a.ID_SUBTIPO_ACTIVO,
            ta.DESCRIPCION AS Nombre_TipoActivo,
            a.DESCRIPCION,

            -- Datos financieros
            a.COSTO_ADQUISICION AS MOI,
            a.ID_MONEDA,
            m.NOMBRE AS Nombre_Moneda,

            -- País
            a.ID_PAIS,
            p.NOMBRE AS Nombre_Pais,

            -- Fechas
            a.FECHA_COMPRA,
            a.FECHA_BAJA,
            a.FECHA_INIC_DEPREC,
            a.STATUS,

            -- Ownership
            a.FLG_PROPIO,

            -- Tasa de depreciación FISCAL
            pd.PORC_SEGUNDO_ANO AS Tasa_Anual,
            pd.PORC_SEGUNDO_ANO / 12.0 AS Tasa_Mensual,

            -- Depreciación acumulada al INICIO del año (Dic año anterior)
            ISNULL(c_fiscal.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año,

            -- INPC de adquisición (solo para activos mexicanos)
            inpc_adq.Indice AS INPC_Adquisicion,

            -- INPC de mitad del ejercicio (junio del año de cálculo)
            inpc_mitad.Indice AS INPC_Mitad_Ejercicio,

            -- *** NUEVOS CAMPOS PARA FISCAL SIMULADO ***
            a.FLG_NOCAPITALIZABLE_2, -- 'S' = tiene fiscal
            a.FLG_NOCAPITALIZABLE_3, -- 'S' = tiene USGAAP
            a.FECHA_INIC_DEPREC3 AS FECHA_INIC_DEPREC_3, -- Fecha inicio USGAAP
            a.COSTO_REEXPRESADO, -- Costo USGAAP

            -- Costo Fiscal: usa COSTO_REVALUADO si existe, sino COSTO_ADQUISICION
            CASE
                WHEN a.COSTO_REVALUADO IS NOT NULL AND a.COSTO_REVALUADO > 0
                    THEN a.COSTO_REVALUADO
                ELSE a.COSTO_ADQUISICION
            END AS Costo_Fiscal,

            -- Control
            @Año_Calculo AS Año_Calculo,
            @Lote_Importacion AS Lote_Importacion

        FROM actif_web_cima_dev.dbo.activo a

        -- Join con tipo_activo
        INNER JOIN actif_web_cima_dev.dbo.tipo_activo ta
            ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

        -- Join con país
        INNER JOIN actif_web_cima_dev.dbo.pais p
            ON a.ID_PAIS = p.ID_PAIS

        -- Join con moneda
        LEFT JOIN actif_web_cima_dev.dbo.moneda m
            ON a.ID_MONEDA = m.ID_MONEDA

        -- Join con porcentaje_depreciacion FISCAL (ID_TIPO_DEP = 2)
        LEFT JOIN actif_web_cima_dev.dbo.porcentaje_depreciacion pd
            ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
            AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO
            AND pd.ID_TIPO_DEP = 2

        -- Depreciación acumulada FISCAL del año ANTERIOR (Diciembre)
        LEFT JOIN actif_web_cima_dev.dbo.calculo c_fiscal
            ON a.ID_NUM_ACTIVO = c_fiscal.ID_NUM_ACTIVO
            AND c_fiscal.ID_COMPANIA = @ID_Compania
            AND c_fiscal.ID_ANO = @Año_Anterior
            AND c_fiscal.ID_MES = 12
            AND c_fiscal.ID_TIPO_DEP = 2

        -- INPC de adquisición (solo para mexicanos, ID_PAIS = 1)
        LEFT JOIN actif_web_cima_dev.dbo.INPC2 inpc_adq
            ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
            AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes
            AND inpc_adq.Id_Pais = 1

        -- INPC de mitad del ejercicio (junio del año actual)
        LEFT JOIN actif_web_cima_dev.dbo.INPC2 inpc_mitad
            ON inpc_mitad.Anio = @Año_Calculo
            AND inpc_mitad.Mes = 6
            AND inpc_mitad.Id_Pais = 1

        WHERE a.ID_COMPANIA = @ID_Compania
          AND a.STATUS = 'A'  -- Solo activos activos
          AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(CAST(@Año_Calculo AS VARCHAR) + '-12-31' AS DATE))
          AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(CAST(@Año_Calculo AS VARCHAR) + '-01-01' AS DATE));

        SET @Registros_Procesados = @@ROWCOUNT;

        PRINT 'Registros importados: ' + CAST(@Registros_Procesados AS VARCHAR)
        PRINT ''

        -- =============================================
        -- 4. ACTUALIZAR LOG - COMPLETADO
        -- =============================================

        UPDATE dbo.Log_Ejecucion_ETL
        SET
            Fecha_Fin = GETDATE(),
            Duracion_Segundos = DATEDIFF(SECOND, @Fecha_Inicio, GETDATE()),
            Registros_Procesados = @Registros_Procesados,
            Registros_Exitosos = @Registros_Procesados,
            Registros_Error = 0,
            Estado = 'Completado'
        WHERE ID_Log = @ID_Log;

        -- =============================================
        -- 5. RETORNAR RESUMEN
        -- =============================================

        SELECT
            @ID_Compania AS ID_Compania,
            @Nombre_Compania AS Nombre_Compania,
            @Año_Calculo AS Año_Calculo,
            @Lote_Importacion AS Lote_Importacion,
            @Registros_Procesados AS Total_Importados,
            COUNT(CASE WHEN FLG_PROPIO = 'S' THEN 1 END) AS Total_Propios,
            COUNT(CASE WHEN FLG_PROPIO <> 'S' THEN 1 END) AS Total_No_Propios,
            COUNT(CASE WHEN ID_PAIS > 1 THEN 1 END) AS Total_Extranjeros,
            COUNT(CASE WHEN ID_PAIS = 1 THEN 1 END) AS Total_Mexicanos,
            COUNT(CASE WHEN FLG_NOCAPITALIZABLE_2 = 'S' THEN 1 END) AS Con_Fiscal,
            COUNT(CASE WHEN FLG_NOCAPITALIZABLE_3 = 'S' THEN 1 END) AS Con_USGAAP,
            COUNT(CASE WHEN FLG_NOCAPITALIZABLE_3 = 'S' AND ISNULL(FLG_NOCAPITALIZABLE_2, 'N') <> 'S' THEN 1 END) AS Requiere_Fiscal_Simulado,
            GETDATE() AS Fecha_Proceso
        FROM dbo.Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND Lote_Importacion = @Lote_Importacion;

        PRINT '==================================='
        PRINT 'ETL COMPLETADO EXITOSAMENTE'
        PRINT '==================================='

    END TRY
    BEGIN CATCH
        SET @Mensaje_Error = ERROR_MESSAGE();

        PRINT 'ERROR EN ETL: ' + @Mensaje_Error

        -- Actualizar log con error
        UPDATE dbo.Log_Ejecucion_ETL
        SET
            Fecha_Fin = GETDATE(),
            Duracion_Segundos = DATEDIFF(SECOND, @Fecha_Inicio, GETDATE()),
            Estado = 'Error',
            Mensaje_Error = @Mensaje_Error
        WHERE ID_Log = @ID_Log;

        -- Re-lanzar error
        THROW;
    END CATCH
END
GO

PRINT 'Stored Procedure sp_ETL_Importar_Activos_Directo creado (Version 1.0.0)';
GO
