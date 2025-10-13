-- =============================================
-- Stored Procedure: sp_Calcular_RMF_Safe_Harbor
-- Descripción: Calcula el valor reportable para TODOS los activos en uso (Safe Harbor)
--              Procesa tanto activos propios como no propios
--              Aplica regla del 10% MOI según Art 182 LISR
--              Maneja activos sin depreciación (terrenos, etc.)
-- Versión: 2.0.0 - Safe Harbor
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Safe_Harbor', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Safe_Harbor;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Safe_Harbor
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '2.0.0-SafeHarbor';
    DECLARE @Registros_Procesados INT = 0;

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
    PRINT 'CÁLCULO RMF - SAFE HARBOR (TODOS LOS ACTIVOS EN USO)';
    PRINT '==========================================';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR);
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR);
    PRINT 'Tipo Cambio 30-Jun: ' + CAST(@Tipo_Cambio_30_Junio AS VARCHAR);
    PRINT 'Lote Cálculo: ' + CAST(@Lote_Calculo AS VARCHAR(50));
    PRINT '';

    -- Variables para procesamiento fila por fila
    DECLARE @ID_Staging BIGINT;
    DECLARE @ID_NUM_ACTIVO INT;
    DECLARE @MOI DECIMAL(18,4);
    DECLARE @Costo_Fiscal DECIMAL(18,4);  -- Nuevo: usa COSTO_REVALUADO o COSTO_ADQUISICION
    DECLARE @Tasa_Mensual DECIMAL(10,6);
    DECLARE @Dep_Acum_Inicio DECIMAL(18,4);
    DECLARE @Fecha_Compra DATETIME;
    DECLARE @Fecha_Baja DATETIME;
    DECLARE @ID_PAIS INT;
    DECLARE @FLG_PROPIO CHAR(1);

    -- Variables INPC
    DECLARE @INPC_Adquisicion DECIMAL(18,6);
    DECLARE @INPC_Mitad_Ejercicio DECIMAL(18,6);

    -- Variables de cálculo
    DECLARE @Meses_Inicio INT;
    DECLARE @Meses_Mitad INT;
    DECLARE @Meses_Ejercicio INT;
    DECLARE @Saldo_Inicio DECIMAL(18,4);
    DECLARE @Dep_Ejercicio DECIMAL(18,4);
    DECLARE @Monto_Pendiente DECIMAL(18,4);
    DECLARE @Proporcion DECIMAL(18,4);
    DECLARE @Prueba_10_Pct DECIMAL(18,4);
    DECLARE @Valor_USD DECIMAL(18,4);
    DECLARE @Valor_Final_MXN DECIMAL(18,4);
    DECLARE @Aplica_10_Pct BIT;

    -- Variables de ruta
    DECLARE @Ruta_Calculo NVARCHAR(20);
    DECLARE @Descripcion_Ruta NVARCHAR(200);
    DECLARE @Observaciones NVARCHAR(500);
    DECLARE @Tipo_Activo NVARCHAR(20);

    -- Cursor para procesar TODOS los activos en uso (Safe Harbor)
    DECLARE cur_activos CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            ID_Staging,
            ID_NUM_ACTIVO,
            COSTO_ADQUISICION AS MOI,  -- MOI base
            Costo_Fiscal,  -- Valor fiscal (revaluado o adquisición)
            ISNULL(Tasa_Mensual, 0) AS Tasa_Mensual,  -- Maneja NULL
            ISNULL(Dep_Acum_Inicio_Año, 0) AS Dep_Acum_Inicio,
            FECHA_COMPRA,
            FECHA_BAJA,
            ID_PAIS,
            FLG_PROPIO
        FROM dbo.Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND Lote_Importacion = @Lote_Importacion
          AND STATUS = 'A'  -- Safe Harbor: solo activos en uso
        ORDER BY ID_NUM_ACTIVO;

    OPEN cur_activos;

    FETCH NEXT FROM cur_activos INTO
        @ID_Staging, @ID_NUM_ACTIVO, @MOI, @Costo_Fiscal, @Tasa_Mensual, @Dep_Acum_Inicio,
        @Fecha_Compra, @Fecha_Baja, @ID_PAIS, @FLG_PROPIO;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Inicializar variables
        SET @Observaciones = '';
        SET @Aplica_10_Pct = 0;
        SET @Tipo_Activo = CASE WHEN @ID_PAIS > 1 THEN 'Extranjero' ELSE 'Mexicano' END;

        -- Usar valor fiscal si está disponible
        IF @Costo_Fiscal IS NOT NULL AND @Costo_Fiscal > 0
            SET @MOI = @Costo_Fiscal;

        -- =============================================
        -- MANEJO DE ACTIVOS SIN DEPRECIACIÓN
        -- =============================================
        IF @Tasa_Mensual = 0 OR @Tasa_Mensual IS NULL
        BEGIN
            -- Activos sin depreciación (terrenos, etc.): usar 10% directamente
            SET @Prueba_10_Pct = @MOI * 0.10;
            SET @Valor_USD = @Prueba_10_Pct;
            SET @Aplica_10_Pct = 1;

            SET @Ruta_Calculo = 'SH.0';
            SET @Descripcion_Ruta = 'Safe Harbor - Sin depreciación - 10% directo';
            SET @Observaciones = 'Activo sin depreciación (tasa = 0). Se aplica 10% del MOI directamente.';

            -- Para activos sin depreciación, no calculamos depreciación
            SET @Meses_Inicio = 0;
            SET @Meses_Mitad = 0;
            SET @Meses_Ejercicio = 0;
            SET @Saldo_Inicio = @MOI;
            SET @Dep_Ejercicio = 0;
            SET @Monto_Pendiente = @MOI;
            SET @Proporcion = 0;

            -- Obtener INPC para registro (aunque no se usa en cálculo)
            SELECT @INPC_Adquisicion = Indice
            FROM dbo.INPC_Importado
            WHERE Anio = YEAR(@Fecha_Compra)
              AND Mes = MONTH(@Fecha_Compra)
              AND (Id_GrupoSimulacion = 8 OR Id_GrupoSimulacion IS NULL);

            SELECT @INPC_Mitad_Ejercicio = Indice
            FROM dbo.INPC_Importado
            WHERE Anio = @Año_Calculo
              AND Mes = 6
              AND (Id_GrupoSimulacion = 8 OR Id_GrupoSimulacion IS NULL);
        END
        ELSE
        BEGIN
            -- =============================================
            -- ACTIVOS CON DEPRECIACIÓN - CÁLCULO NORMAL
            -- =============================================

            DECLARE @Inicio_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-01-01' AS DATE);
            DECLARE @Mitad_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE);
            DECLARE @Fin_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-12-31' AS DATE);

            -- Meses de uso al inicio del ejercicio
            IF YEAR(@Fecha_Compra) < @Año_Calculo
                SET @Meses_Inicio = DATEDIFF(MONTH, @Fecha_Compra, @Inicio_Ejercicio);
            ELSE
                SET @Meses_Inicio = 0;

            -- Determinar escenario y calcular meses
            IF @Fecha_Baja IS NOT NULL AND YEAR(@Fecha_Baja) = @Año_Calculo
            BEGIN
                -- Activo dado de baja en el año
                SET @Meses_Ejercicio = MONTH(@Fecha_Baja);
                SET @Meses_Mitad = CASE
                    WHEN MONTH(@Fecha_Baja) <= 6 THEN MONTH(@Fecha_Baja)
                    ELSE 6
                END;

                SET @Ruta_Calculo = CASE WHEN @ID_PAIS > 1 THEN 'SH.1.3' ELSE 'SH.2.3' END;
                SET @Descripcion_Ruta = 'Safe Harbor - ' + @Tipo_Activo + ' - Baja en año';
                SET @Observaciones = 'Activo dado de baja en ' +
                    DATENAME(MONTH, @Fecha_Baja) + ' ' + CAST(YEAR(@Fecha_Baja) AS VARCHAR);
            END
            ELSE IF YEAR(@Fecha_Compra) < @Año_Calculo
            BEGIN
                -- Activo existente
                SET @Meses_Ejercicio = 12;
                SET @Meses_Mitad = 6;

                SET @Ruta_Calculo = CASE WHEN @ID_PAIS > 1 THEN 'SH.1.1' ELSE 'SH.2.1' END;
                SET @Descripcion_Ruta = 'Safe Harbor - ' + @Tipo_Activo + ' - Existente';
                SET @Observaciones = 'Activo en uso todo el año ' + CAST(@Año_Calculo AS VARCHAR);
            END
            ELSE IF YEAR(@Fecha_Compra) = @Año_Calculo
            BEGIN
                -- Activo adquirido en el año
                IF @Fecha_Compra <= @Mitad_Ejercicio
                BEGIN
                    SET @Meses_Mitad = DATEDIFF(MONTH, @Fecha_Compra, @Mitad_Ejercicio);
                    SET @Meses_Ejercicio = 13 - MONTH(@Fecha_Compra);

                    SET @Ruta_Calculo = CASE WHEN @ID_PAIS > 1 THEN 'SH.1.2.1' ELSE 'SH.2.2.1' END;
                    SET @Descripcion_Ruta = 'Safe Harbor - ' + @Tipo_Activo + ' - Nuevo antes junio';
                END
                ELSE
                BEGIN
                    SET @Meses_Ejercicio = 13 - MONTH(@Fecha_Compra);
                    SET @Meses_Mitad = @Meses_Ejercicio / 2;

                    SET @Ruta_Calculo = CASE WHEN @ID_PAIS > 1 THEN 'SH.1.2.2' ELSE 'SH.2.2.2' END;
                    SET @Descripcion_Ruta = 'Safe Harbor - ' + @Tipo_Activo + ' - Nuevo después junio';
                END

                SET @Observaciones = 'Activo adquirido en ' + CAST(@Año_Calculo AS VARCHAR);
            END

            -- OBTENER INPC
            SELECT @INPC_Adquisicion = Indice
            FROM dbo.INPC_Importado
            WHERE Anio = YEAR(@Fecha_Compra)
              AND Mes = MONTH(@Fecha_Compra)
              AND (Id_GrupoSimulacion = 8 OR Id_GrupoSimulacion IS NULL);

            SELECT @INPC_Mitad_Ejercicio = Indice
            FROM dbo.INPC_Importado
            WHERE Anio = @Año_Calculo
              AND Mes = 6
              AND (Id_GrupoSimulacion = 8 OR Id_GrupoSimulacion IS NULL);

            IF @INPC_Adquisicion IS NULL OR @INPC_Mitad_Ejercicio IS NULL
                SET @Observaciones = @Observaciones + ' ADVERTENCIA: INPC no encontrado.';

            -- CÁLCULOS DE DEPRECIACIÓN
            SET @Saldo_Inicio = @MOI - @Dep_Acum_Inicio;
            IF @Saldo_Inicio < 0 SET @Saldo_Inicio = 0;

            SET @Dep_Ejercicio = @MOI * @Tasa_Mensual * @Meses_Mitad;

            SET @Monto_Pendiente = @Saldo_Inicio - @Dep_Ejercicio;
            IF @Monto_Pendiente < 0 SET @Monto_Pendiente = 0;

            IF @Meses_Ejercicio > 0
                SET @Proporcion = (@Monto_Pendiente / 12.0) * @Meses_Ejercicio;
            ELSE
                SET @Proporcion = 0;

            -- APLICAR REGLA DEL 10% MOI
            SET @Prueba_10_Pct = @MOI * 0.10;

            IF @Proporcion > @Prueba_10_Pct
            BEGIN
                SET @Valor_USD = @Proporcion;
                SET @Aplica_10_Pct = 0;
                SET @Ruta_Calculo = @Ruta_Calculo + '.1';
            END
            ELSE
            BEGIN
                SET @Valor_USD = @Prueba_10_Pct;
                SET @Aplica_10_Pct = 1;
                SET @Ruta_Calculo = @Ruta_Calculo + '.2';
                SET @Descripcion_Ruta = @Descripcion_Ruta + ' - 10% MOI';

                IF @Observaciones <> '' SET @Observaciones = @Observaciones + '. ';
                SET @Observaciones = @Observaciones +
                    'Aplica 10% MOI (Art 182). Proporción: ' + FORMAT(@Proporcion, 'N2') +
                    ' < 10% MOI: ' + FORMAT(@Prueba_10_Pct, 'N2');
            END
        END

        -- =============================================
        -- CONVERSIÓN A PESOS (SOLO PARA EXTRANJEROS)
        -- =============================================
        IF @ID_PAIS > 1
            SET @Valor_Final_MXN = @Valor_USD * @Tipo_Cambio_30_Junio;
        ELSE
            SET @Valor_Final_MXN = @Valor_USD;  -- Mexicanos ya están en pesos

        -- Agregar información de FLG_PROPIO a observaciones
        IF @FLG_PROPIO = 'S'
            SET @Observaciones = @Observaciones + ' [Activo PROPIO]';
        ELSE
            SET @Observaciones = @Observaciones + ' [Activo NO PROPIO]';

        -- =============================================
        -- GUARDAR RESULTADO
        -- =============================================

        INSERT INTO dbo.Calculo_RMF (
            ID_Staging, ID_Compania, ID_NUM_ACTIVO, Año_Calculo,
            Tipo_Activo, ID_PAIS,
            Ruta_Calculo, Descripcion_Ruta,
            MOI, Tasa_Mensual, Dep_Acum_Inicio,
            Meses_Uso_Inicio_Ejercicio, Meses_Uso_Hasta_Mitad_Periodo, Meses_Uso_En_Ejercicio,
            Saldo_Inicio_Año, Dep_Fiscal_Ejercicio,
            Monto_Pendiente, Proporcion,
            Prueba_10_Pct_MOI, Aplica_10_Pct,
            INPC_Adqu, INPC_Mitad_Ejercicio,
            Tipo_Cambio_30_Junio,
            Valor_Reportable_MXN,
            Observaciones,
            Lote_Calculo, Version_SP
        )
        VALUES (
            @ID_Staging, @ID_Compania, @ID_NUM_ACTIVO, @Año_Calculo,
            @Tipo_Activo, @ID_PAIS,
            @Ruta_Calculo, @Descripcion_Ruta,
            @MOI, @Tasa_Mensual, @Dep_Acum_Inicio,
            @Meses_Inicio, @Meses_Mitad, @Meses_Ejercicio,
            @Saldo_Inicio, @Dep_Ejercicio,
            @Monto_Pendiente, @Proporcion,
            @Prueba_10_Pct, @Aplica_10_Pct,
            @INPC_Adquisicion, @INPC_Mitad_Ejercicio,
            @Tipo_Cambio_30_Junio,
            @Valor_Final_MXN,
            @Observaciones,
            @Lote_Calculo, @Version_SP
        );

        SET @Registros_Procesados = @Registros_Procesados + 1;

        FETCH NEXT FROM cur_activos INTO
            @ID_Staging, @ID_NUM_ACTIVO, @MOI, @Costo_Fiscal, @Tasa_Mensual, @Dep_Acum_Inicio,
            @Fecha_Compra, @Fecha_Baja, @ID_PAIS, @FLG_PROPIO;
    END

    CLOSE cur_activos;
    DEALLOCATE cur_activos;

    PRINT 'Total activos procesados (Safe Harbor): ' + CAST(@Registros_Procesados AS VARCHAR);
    PRINT '';

    -- Retornar resumen
    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        'Safe Harbor' AS Tipo_Calculo,
        @Registros_Procesados AS Registros_Calculados,
        @Lote_Calculo AS Lote_Calculo,
        SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable_MXN,
        COUNT(CASE WHEN Aplica_10_Pct = 1 THEN 1 END) AS Activos_Con_Regla_10_Pct,
        COUNT(CASE WHEN Tipo_Activo = 'Extranjero' THEN 1 END) AS Total_Extranjeros,
        COUNT(CASE WHEN Tipo_Activo = 'Mexicano' THEN 1 END) AS Total_Mexicanos,
        COUNT(CASE WHEN Ruta_Calculo LIKE 'SH.0%' THEN 1 END) AS Activos_Sin_Depreciacion
    FROM dbo.Calculo_RMF
    WHERE Lote_Calculo = @Lote_Calculo
    GROUP BY @ID_Compania, @Año_Calculo, @Lote_Calculo;

END
GO

PRINT 'Stored Procedure sp_Calcular_RMF_Safe_Harbor creado (Version 2.0.0)';
GO
