-- =============================================
-- Stored Procedure: sp_ETL_Importar_Activos_Completo
-- Descripción: ETL completo que importa TODOS los activos activos (Safe Harbor)
--              Incluye campos para fiscal simulado (FLG_NOCAPITALIZABLE_2/3, COSTO_REEXPRESADO, etc.)
-- Diferencias vs sp_ETL_Importar_Activos:
--   - Carga TODOS los activos (no solo FLG_PROPIO = 0)
--   - Agrega FLG_NOCAPITALIZABLE_2, FLG_NOCAPITALIZABLE_3
--   - Agrega FECHA_INIC_DEPREC_3, COSTO_REEXPRESADO
--   - Agrega Costo_Fiscal (COSTO_REVALUADO o COSTO_ADQUISICION)
-- Versión: 1.0.0
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_ETL_Importar_Activos_Completo', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ETL_Importar_Activos_Completo;
GO

CREATE PROCEDURE dbo.sp_ETL_Importar_Activos_Completo
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
    DECLARE @ConnectionString NVARCHAR(500);
    DECLARE @Nombre_Compania NVARCHAR(200);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Año_Anterior INT = @Año_Calculo - 1;

    BEGIN TRY
        -- =============================================
        -- 1. VALIDACIONES
        -- =============================================

        SELECT
            @ConnectionString = ConnectionString_Actif,
            @Nombre_Compania = Nombre_Compania
        FROM dbo.ConfiguracionCompania
        WHERE ID_Compania = @ID_Compania
          AND Activo = 1;

        IF @ConnectionString IS NULL
        BEGIN
            RAISERROR('La compañía %d no existe o no está activa', 16, 1, @ID_Compania);
            RETURN;
        END

        PRINT '===================================';
        PRINT 'ETL IMPORTACIÓN COMPLETA (SAFE HARBOR + FISCAL SIMULADO)';
        PRINT '===================================';
        PRINT 'Compañía: ' + @Nombre_Compania + ' (ID: ' + CAST(@ID_Compania AS VARCHAR) + ')';
        PRINT 'Año Cálculo: ' + CAST(@Año_Calculo AS VARCHAR);
        PRINT 'Lote: ' + CAST(@Lote_Importacion AS VARCHAR(50));
        PRINT '';

        -- =============================================
        -- 2. REGISTRAR INICIO DE PROCESO EN LOG
        -- =============================================

        INSERT INTO dbo.Log_Ejecucion_ETL
            (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
             Fecha_Inicio, Estado, Usuario)
        VALUES
            (@ID_Compania, @Año_Calculo, @Lote_Importacion, 'ETL_COMPLETO',
             @Fecha_Inicio, 'En Proceso', @Usuario);

        SET @ID_Log = SCOPE_IDENTITY();

        -- =============================================
        -- 3. CONSTRUIR QUERY DINÁMICO
        -- =============================================

        SET @SQL = N'
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
            ' + CAST(@ID_Compania AS VARCHAR) + ' AS ID_Compania,
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
            -- Prioridad: calculo fiscal (ID_TIPO_DEP=2), si no existe usa NULL
            ISNULL(c_fiscal.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año,

            -- INPC de adquisición (solo para activos mexicanos)
            inpc_adq.Indice AS INPC_Adquisicion,

            -- INPC de mitad del ejercicio (junio del año de cálculo)
            inpc_mitad.Indice AS INPC_Mitad_Ejercicio,

            -- *** NUEVOS CAMPOS PARA FISCAL SIMULADO ***
            a.FLG_NOCAPITALIZABLE_2, -- ''S'' = tiene fiscal
            a.FLG_NOCAPITALIZABLE_3, -- ''S'' = tiene USGAAP
            a.FECHA_INIC_DEPREC3 AS FECHA_INIC_DEPREC_3, -- Fecha inicio USGAAP
            a.COSTO_REEXPRESADO, -- Costo USGAAP

            -- Costo Fiscal: usa COSTO_REVALUADO si existe, sino COSTO_ADQUISICION
            CASE
                WHEN a.COSTO_REVALUADO IS NOT NULL AND a.COSTO_REVALUADO > 0
                    THEN a.COSTO_REVALUADO
                ELSE a.COSTO_ADQUISICION
            END AS Costo_Fiscal,

            -- Control
            ' + CAST(@Año_Calculo AS VARCHAR) + ' AS Año_Calculo,
            ''' + CAST(@Lote_Importacion AS VARCHAR(50)) + ''' AS Lote_Importacion

        FROM OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM activo WHERE ID_COMPANIA = ' + CAST(@ID_Compania AS VARCHAR) + ' AND STATUS = ''''A''''''
        ) AS a

        -- Join con tipo_activo
        INNER JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM tipo_activo''
        ) AS ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

        -- Join con país
        INNER JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM pais''
        ) AS p ON a.ID_PAIS = p.ID_PAIS

        -- Join con moneda
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM moneda''
        ) AS m ON a.ID_MONEDA = m.ID_MONEDA

        -- Join con porcentaje_depreciacion FISCAL (ID_TIPO_DEP = 2)
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM porcentaje_depreciacion WHERE ID_TIPO_DEP = 2''
        ) AS pd
            ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
            AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO

        -- Depreciación acumulada FISCAL del año ANTERIOR (Diciembre)
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM calculo
              WHERE ID_COMPANIA = ' + CAST(@ID_Compania AS VARCHAR) + '
                AND ID_ANO = ' + CAST(@Año_Anterior AS VARCHAR) + '
                AND ID_MES = 12
                AND ID_TIPO_DEP = 2''
        ) AS c_fiscal ON a.ID_NUM_ACTIVO = c_fiscal.ID_NUM_ACTIVO

        -- INPC de adquisición (solo para mexicanos, ID_PAIS = 1)
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM INPC2 WHERE Id_Pais = 1''
        ) AS inpc_adq
            ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
            AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes

        -- INPC de mitad del ejercicio (junio del año actual)
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            '''''' + @ConnectionString + '''''',
            ''SELECT * FROM INPC2 WHERE Anio = ' + CAST(@Año_Calculo AS VARCHAR) + ' AND Mes = 6 AND Id_Pais = 1''
        ) AS inpc_mitad ON 1=1

        WHERE a.STATUS = ''A''  -- Solo activos activos (Safe Harbor)
          AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(''' + CAST(@Año_Calculo AS VARCHAR) + '-12-31'' AS DATE))
          AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(''' + CAST(@Año_Calculo AS VARCHAR) + '-01-01'' AS DATE));
        ';

        -- =============================================
        -- 4. EJECUTAR QUERY DINÁMICO
        -- =============================================

        PRINT 'Ejecutando importación...';
        PRINT '';

        EXEC sp_executesql @SQL;

        SET @Registros_Procesados = @@ROWCOUNT;

        PRINT 'Registros importados: ' + CAST(@Registros_Procesados AS VARCHAR);
        PRINT '';

        -- =============================================
        -- 5. ACTUALIZAR LOG - COMPLETADO
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
        -- 6. RETORNAR RESUMEN
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

        PRINT '===================================';
        PRINT 'ETL COMPLETADO EXITOSAMENTE';
        PRINT '===================================';

    END TRY
    BEGIN CATCH
        SET @Mensaje_Error = ERROR_MESSAGE();

        PRINT 'ERROR EN ETL: ' + @Mensaje_Error;

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

PRINT 'Stored Procedure sp_ETL_Importar_Activos_Completo creado (Version 1.0.0)';
GO
