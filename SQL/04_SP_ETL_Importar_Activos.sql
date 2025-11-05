-- =============================================
-- Stored Procedure: sp_ETL_Importar_Activos
-- Descripción: ETL para importar activos NO propios de cada compañía
--              usando el connection string configurado
-- Parámetros:
--   @ID_Compania: ID de la compañía a procesar
--   @Año_Calculo: Año fiscal para el cálculo
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_ETL_Importar_Activos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ETL_Importar_Activos;
GO

CREATE PROCEDURE dbo.sp_ETL_Importar_Activos
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

        -- Verificar que existe la compañía y está activa
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
        PRINT 'ETL IMPORTACIÓN DE ACTIVOS';
        PRINT '===================================';
        PRINT 'Compañía: ' + @Nombre_Compania + ' (ID: ' + CAST(@ID_Compania AS VARCHAR) + ')';
        PRINT 'Año Cálculo: ' + CAST(@Año_Calculo AS VARCHAR);
        PRINT 'Lote: ' + CAST(@Lote_Importacion AS VARCHAR(50));
        PRINT 'Connection String: ' + LEFT(@ConnectionString, 50) + '...';
        PRINT '';

        -- =============================================
        -- 2. REGISTRAR INICIO DE PROCESO EN LOG
        -- =============================================

        INSERT INTO dbo.Log_Ejecucion_ETL
            (ID_Compania, Año_Calculo, Lote_Importacion, Tipo_Proceso,
             Fecha_Inicio, Estado, Usuario)
        VALUES
            (@ID_Compania, @Año_Calculo, @Lote_Importacion, 'ETL',
             @Fecha_Inicio, 'En Proceso', @Usuario);

        SET @ID_Log = SCOPE_IDENTITY();

        -- =============================================
        -- 3. LIMPIAR DATOS ANTERIORES
        -- =============================================

        PRINT 'Limpiando datos anteriores de Staging_Activo...';

        DELETE FROM Actif_RMF.dbo.Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo;

        PRINT 'Registros eliminados: ' + CAST(@@ROWCOUNT AS VARCHAR);
        PRINT '';

        -- =============================================
        -- 4. CONSTRUIR QUERY DINÁMICO
        -- =============================================

        -- Query para extraer activos de la base de datos origen
        -- usando OPENROWSET con el connection string
        SET @SQL = N'
        INSERT INTO Actif_RMF.dbo.Staging_Activo
            (ID_Compania, ID_NUM_ACTIVO, ID_ACTIVO, ID_TIPO_ACTIVO, ID_SUBTIPO_ACTIVO,
             Nombre_TipoActivo, DESCRIPCION, ID_MONEDA, Nombre_Moneda,
             ID_PAIS, Nombre_Pais, FECHA_COMPRA, FECHA_BAJA, FECHA_INICIO_DEP, STATUS,
             FLG_PROPIO, Tasa_Anual, Tasa_Mensual, Dep_Acum_Inicio_Año,
             INPC_Adquisicion, INPC_Mitad_Ejercicio,
             Año_Calculo, Lote_Importacion)
        SELECT
            -- Identificación
            @ID_Compania AS ID_Compania,
            a.ID_NUM_ACTIVO,
            a.ID_ACTIVO AS Placa,
            a.ID_TIPO_ACTIVO,
            a.ID_SUBTIPO_ACTIVO,
            ta.NOMBRE AS Nombre_TipoActivo,
            a.DESCRIPCION,

            -- Datos financieros
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

            -- Ownership (CRÍTICO: Solo FLG_PROPIO = 0)
            a.FLG_PROPIO,

            -- Tasa de depreciación FISCAL
            -- FIX: Convertir de porcentaje entero (8) a decimal (0.08)
            pd.PORCENTAJE / 100.0 AS Tasa_Anual,
            pd.PORCENTAJE / 1200.0 AS Tasa_Mensual,

            -- Depreciación acumulada al INICIO del año (Dic año anterior)
            ISNULL(c.ACUMULADO_HISTORICA, 0) AS Dep_Acum_Inicio_Año,

            -- INPC de adquisición (solo para activos mexicanos)
            inpc_adq.Indice AS INPC_Adquisicion,

            -- INPC de mitad del ejercicio (junio del año de cálculo)
            inpc_mitad.Indice AS INPC_Mitad_Ejercicio,

            -- Control
            @Año_Calculo AS Año_Calculo,
            @Lote_Importacion AS Lote_Importacion

        FROM OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM activo WHERE FLG_PROPIO = 0 AND ID_COMPANIA = ' + CAST(@ID_Compania AS VARCHAR) + '''
        ) AS a

        -- Join con tipo_activo
        INNER JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM tipo_activo''
        ) AS ta ON a.ID_TIPO_ACTIVO = ta.ID_TIPO_ACTIVO

        -- Join con país
        INNER JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM pais''
        ) AS p ON a.ID_PAIS = p.ID_PAIS

        -- Join con moneda
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM moneda''
        ) AS m ON a.ID_MONEDA = m.ID_MONEDA

        -- *** CRITICAL: Join con porcentaje_depreciacion FISCAL ***
        INNER JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM porcentaje_depreciacion WHERE ID_TIPO_DEP = 2''
        ) AS pd
            ON a.ID_TIPO_ACTIVO = pd.ID_TIPO_ACTIVO
            AND a.ID_SUBTIPO_ACTIVO = pd.ID_SUBTIPO_ACTIVO

        -- Depreciación acumulada del año ANTERIOR (Diciembre)
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM calculo WHERE ID_COMPANIA = ' + CAST(@ID_Compania AS VARCHAR) + ' AND ID_ANO = ' + CAST(@Año_Anterior AS VARCHAR) + ' AND ID_MES = 12 AND ID_TIPO_DEP = 2''
        ) AS c ON a.ID_NUM_ACTIVO = c.ID_NUM_ACTIVO

        -- INPC de adquisición (solo para mexicanos, ID_PAIS = 1)
        -- FIX: Agregar filtro Id_Grupo_Simulacion = 8
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM INPC2 WHERE Id_Pais = 1 AND Id_Tipo_Dep = 2 AND Id_Grupo_Simulacion = 8''
        ) AS inpc_adq
            ON YEAR(a.FECHA_COMPRA) = inpc_adq.Anio
            AND MONTH(a.FECHA_COMPRA) = inpc_adq.Mes

        -- INPC de mitad del ejercicio (junio del año actual)
        -- FIX: Agregar filtro Id_Grupo_Simulacion = 8
        LEFT JOIN OPENROWSET(
            ''SQLNCLI'',
            ''' + @ConnectionString + ''',
            ''SELECT * FROM INPC2 WHERE Anio = ' + CAST(@Año_Calculo AS VARCHAR) + ' AND Mes = 6 AND Id_Pais = 1 AND Id_Tipo_Dep = 2 AND Id_Grupo_Simulacion = 8''
        ) AS inpc_mitad ON 1=1

        WHERE a.FLG_PROPIO = 0  -- *** FILTRO CRÍTICO: Solo NO propios ***
          -- Incluir activos activos (A) Y activos dados de baja en el ejercicio (B)
          AND (a.STATUS = ''A'' OR
               (a.STATUS = ''B'' AND a.FECHA_BAJA >= CAST(''' + CAST(@Año_Calculo AS VARCHAR) + '-01-01'' AS DATE)))
          AND (a.FECHA_COMPRA IS NULL OR a.FECHA_COMPRA <= CAST(''' + CAST(@Año_Calculo AS VARCHAR) + '-12-31'' AS DATE))
          AND (a.FECHA_BAJA IS NULL OR a.FECHA_BAJA >= CAST(''' + CAST(@Año_Calculo AS VARCHAR) + '-01-01'' AS DATE))
          AND ISNULL(pd.PORCENTAJE, 0) > 0; -- Excluir terrenos y activos sin tasa
        ';

        PRINT 'Ejecutando query de importación...';
        PRINT '';

        -- =============================================
        -- 5. EJECUTAR IMPORTACIÓN
        -- =============================================

        EXEC sp_executesql @SQL,
            N'@ID_Compania INT, @Año_Calculo INT, @Lote_Importacion UNIQUEIDENTIFIER',
            @ID_Compania = @ID_Compania,
            @Año_Calculo = @Año_Calculo,
            @Lote_Importacion = @Lote_Importacion;

        SET @Registros_Procesados = @@ROWCOUNT;

        PRINT 'Registros importados: ' + CAST(@Registros_Procesados AS VARCHAR);

        -- =============================================
        -- 6. ACTUALIZAR LOG CON ÉXITO
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

        PRINT '';
        PRINT '===================================';
        PRINT 'ETL COMPLETADO EXITOSAMENTE';
        PRINT '===================================';
        PRINT 'Duración: ' + CAST(DATEDIFF(SECOND, @Fecha_Inicio, GETDATE()) AS VARCHAR) + ' segundos';
        PRINT '';

        -- Retornar resumen
        SELECT
            @ID_Compania AS ID_Compania,
            @Nombre_Compania AS Nombre_Compania,
            @Año_Calculo AS Año_Calculo,
            @Lote_Importacion AS Lote_Importacion,
            @Registros_Procesados AS Registros_Importados,
            DATEDIFF(SECOND, @Fecha_Inicio, GETDATE()) AS Duracion_Segundos,
            'Completado' AS Estado;

    END TRY
    BEGIN CATCH
        -- =============================================
        -- MANEJO DE ERRORES
        -- =============================================

        SET @Mensaje_Error =
            'Error ' + CAST(ERROR_NUMBER() AS VARCHAR) + ': ' +
            ERROR_MESSAGE() + ' (Línea ' + CAST(ERROR_LINE() AS VARCHAR) + ')';

        PRINT '';
        PRINT '===================================';
        PRINT 'ERROR EN ETL';
        PRINT '===================================';
        PRINT @Mensaje_Error;
        PRINT '';

        -- Actualizar log con error
        IF @ID_Log IS NOT NULL
        BEGIN
            UPDATE dbo.Log_Ejecucion_ETL
            SET
                Fecha_Fin = GETDATE(),
                Duracion_Segundos = DATEDIFF(SECOND, @Fecha_Inicio, GETDATE()),
                Estado = 'Error',
                Mensaje_Error = @Mensaje_Error
            WHERE ID_Log = @ID_Log;
        END

        -- Re-lanzar el error
        ;THROW;

    END CATCH
END
GO

PRINT 'Stored Procedure sp_ETL_Importar_Activos creado';
GO
