-- =============================================
-- Stored Procedure: sp_Calcular_RMF_Activos_Extranjeros
-- Descripción: Calcula el valor reportable para activos extranjeros (ID_PAIS > 1)
--              Aplica regla del 10% MOI según Art 182 LISR
--              Documenta la ruta de cálculo utilizada
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Extranjeros', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Activos_Extranjeros
    @ID_Compania INT,
    @Año_Calculo INT,
    @Lote_Importacion UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Lote_Calculo UNIQUEIDENTIFIER = NEWID();
    DECLARE @Version_SP NVARCHAR(20) = '1.0.0';
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
    PRINT 'CÁLCULO RMF - ACTIVOS EXTRANJEROS';
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
    DECLARE @Tasa_Mensual DECIMAL(10,6);
    DECLARE @Dep_Acum_Inicio DECIMAL(18,4);
    DECLARE @Fecha_Compra DATETIME;
    DECLARE @Fecha_Baja DATETIME;
    DECLARE @ID_PAIS INT;

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

    -- Cursor para procesar cada activo extranjero
    DECLARE cur_activos CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            ID_Staging,
            ID_NUM_ACTIVO,
            COSTO_ADQUISICION,
            Tasa_Mensual,
            Dep_Acum_Inicio_Año,
            FECHA_COMPRA,
            FECHA_BAJA,
            ID_PAIS
        FROM dbo.Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND Lote_Importacion = @Lote_Importacion
          AND ID_PAIS > 1  -- Solo extranjeros
          AND Tasa_Mensual > 0  -- Excluir terrenos
        ORDER BY ID_NUM_ACTIVO;

    OPEN cur_activos;

    FETCH NEXT FROM cur_activos INTO
        @ID_Staging, @ID_NUM_ACTIVO, @MOI, @Tasa_Mensual, @Dep_Acum_Inicio,
        @Fecha_Compra, @Fecha_Baja, @ID_PAIS;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Inicializar variables
        SET @Observaciones = '';
        SET @Aplica_10_Pct = 0;

        -- =============================================
        -- PASO 1: CALCULAR MESES
        -- =============================================

        DECLARE @Inicio_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-01-01' AS DATE);
        DECLARE @Mitad_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-06-30' AS DATE);
        DECLARE @Fin_Ejercicio DATE = CAST(CAST(@Año_Calculo AS VARCHAR) + '-12-31' AS DATE);

        -- Meses de uso al inicio del ejercicio (hasta 31-Dic año anterior)
        IF YEAR(@Fecha_Compra) < @Año_Calculo
        BEGIN
            SET @Meses_Inicio = DATEDIFF(MONTH, @Fecha_Compra, @Inicio_Ejercicio);
        END
        ELSE
        BEGIN
            SET @Meses_Inicio = 0;
        END

        -- Determinar escenario y calcular meses hasta mitad y meses en ejercicio
        IF @Fecha_Baja IS NOT NULL AND YEAR(@Fecha_Baja) = @Año_Calculo
        BEGIN
            -- ESCENARIO: Activo dado de baja en el año
            SET @Meses_Ejercicio = MONTH(@Fecha_Baja);
            SET @Meses_Mitad = CASE
                WHEN MONTH(@Fecha_Baja) <= 6 THEN MONTH(@Fecha_Baja)
                ELSE 6
            END;

            SET @Ruta_Calculo = '1.3.1';
            SET @Descripcion_Ruta = 'Extranjero - Baja en año';
            SET @Observaciones = 'Activo dado de baja en ' +
                DATENAME(MONTH, @Fecha_Baja) + ' ' + CAST(YEAR(@Fecha_Baja) AS VARCHAR);
        END
        ELSE IF YEAR(@Fecha_Compra) < @Año_Calculo
        BEGIN
            -- ESCENARIO: Activo existente (antes del año de cálculo)
            SET @Meses_Ejercicio = 12;
            SET @Meses_Mitad = 6;

            SET @Ruta_Calculo = '1.1.3';
            SET @Descripcion_Ruta = 'Extranjero - Existente - Todo el año';
            SET @Observaciones = 'Activo en uso en ' + CAST(@Año_Calculo AS VARCHAR);
        END
        ELSE IF YEAR(@Fecha_Compra) = @Año_Calculo
        BEGIN
            -- ESCENARIO: Activo adquirido en el año de cálculo
            IF @Fecha_Compra <= @Mitad_Ejercicio
            BEGIN
                -- Adquirido ANTES de junio
                SET @Meses_Mitad = DATEDIFF(MONTH, @Fecha_Compra, @Mitad_Ejercicio);
                SET @Meses_Ejercicio = 13 - MONTH(@Fecha_Compra);

                SET @Ruta_Calculo = '1.2.1';
                SET @Descripcion_Ruta = 'Extranjero - Nuevo en año - Antes de Junio';
                SET @Observaciones = 'Activo adquirido en ' + CAST(@Año_Calculo AS VARCHAR) + ' antes de junio';
            END
            ELSE
            BEGIN
                -- Adquirido DESPUÉS de junio
                SET @Meses_Ejercicio = 13 - MONTH(@Fecha_Compra);
                SET @Meses_Mitad = @Meses_Ejercicio / 2;

                SET @Ruta_Calculo = '1.2.2';
                SET @Descripcion_Ruta = 'Extranjero - Nuevo en año - Después de Junio';
                SET @Observaciones = 'Activo adquirido en ' + CAST(@Año_Calculo AS VARCHAR) + ' después de junio';
            END
        END

        -- =============================================
        -- PASO 1.5: OBTENER INPC
        -- =============================================

        -- INPC del mes y año de adquisición
        SELECT @INPC_Adquisicion = Indice
        FROM dbo.INPC_Importado
        WHERE Anio = YEAR(@Fecha_Compra)
          AND Mes = MONTH(@Fecha_Compra);

        -- INPC de junio del año de cálculo (mitad del ejercicio)
        SELECT @INPC_Mitad_Ejercicio = Indice
        FROM dbo.INPC_Importado
        WHERE Anio = @Año_Calculo
          AND Mes = 6;

        -- Si no se encuentran INPC, registrar advertencia
        IF @INPC_Adquisicion IS NULL OR @INPC_Mitad_Ejercicio IS NULL
        BEGIN
            SET @Observaciones = @Observaciones + 'ADVERTENCIA: INPC no encontrado. ';
        END

        -- =============================================
        -- PASO 2: CÁLCULOS DE DEPRECIACIÓN
        -- =============================================

        -- Saldo por deducir ISR al inicio del año
        SET @Saldo_Inicio = @MOI - @Dep_Acum_Inicio;
        IF @Saldo_Inicio < 0 SET @Saldo_Inicio = 0;

        -- Depreciación fiscal del ejercicio (usa meses hasta MITAD)
        SET @Dep_Ejercicio = @MOI * @Tasa_Mensual * @Meses_Mitad;

        -- Monto pendiente por deducir
        SET @Monto_Pendiente = @Saldo_Inicio - @Dep_Ejercicio;
        IF @Monto_Pendiente < 0 SET @Monto_Pendiente = 0;

        -- Proporción del monto pendiente
        IF @Meses_Ejercicio > 0
            SET @Proporcion = (@Monto_Pendiente / 12.0) * @Meses_Ejercicio;
        ELSE
            SET @Proporcion = 0;

        -- =============================================
        -- PASO 3: APLICAR REGLA DEL 10% MOI (Art 182)
        -- =============================================

        SET @Prueba_10_Pct = @MOI * 0.10;

        IF @Proporcion > @Prueba_10_Pct
        BEGIN
            SET @Valor_USD = @Proporcion;
            SET @Aplica_10_Pct = 0;
            SET @Ruta_Calculo = @Ruta_Calculo + '.1'; -- Ruta normal
        END
        ELSE
        BEGIN
            SET @Valor_USD = @Prueba_10_Pct;
            SET @Aplica_10_Pct = 1;
            SET @Ruta_Calculo = @Ruta_Calculo + '.2'; -- Ruta con 10% MOI
            SET @Descripcion_Ruta = @Descripcion_Ruta + ' - Aplica 10% MOI';

            IF @Observaciones <> ''
                SET @Observaciones = @Observaciones + '. ';

            SET @Observaciones = @Observaciones +
                'Aplica regla del 10% MOI (Art 182 LISR). ' +
                'Proporción calculada: ' + FORMAT(@Proporcion, 'N2') + ' USD < ' +
                '10% MOI: ' + FORMAT(@Prueba_10_Pct, 'N2') + ' USD';
        END

        -- =============================================
        -- PASO 4: CONVERSIÓN A PESOS
        -- =============================================

        SET @Valor_Final_MXN = @Valor_USD * @Tipo_Cambio_30_Junio;

        -- =============================================
        -- PASO 5: GUARDAR RESULTADO
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
            'Extranjero', @ID_PAIS,
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
            @ID_Staging, @ID_NUM_ACTIVO, @MOI, @Tasa_Mensual, @Dep_Acum_Inicio,
            @Fecha_Compra, @Fecha_Baja, @ID_PAIS;
    END

    CLOSE cur_activos;
    DEALLOCATE cur_activos;

    PRINT 'Activos extranjeros procesados: ' + CAST(@Registros_Procesados AS VARCHAR);
    PRINT '';

    -- Retornar resumen
    SELECT
        @ID_Compania AS ID_Compania,
        @Año_Calculo AS Año_Calculo,
        'Extranjero' AS Tipo_Activo,
        @Registros_Procesados AS Registros_Calculados,
        @Lote_Calculo AS Lote_Calculo,
        SUM(Valor_Reportable_MXN) AS Total_Valor_Reportable_MXN,
        COUNT(CASE WHEN Aplica_10_Pct = 1 THEN 1 END) AS Activos_Con_Regla_10_Pct
    FROM dbo.Calculo_RMF
    WHERE Lote_Calculo = @Lote_Calculo
    GROUP BY @ID_Compania, @Año_Calculo, @Lote_Calculo;

END
GO

PRINT 'Stored Procedure sp_Calcular_RMF_Activos_Extranjeros creado';
GO
