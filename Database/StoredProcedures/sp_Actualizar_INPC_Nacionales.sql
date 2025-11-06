-- =============================================
-- Stored Procedure: sp_Actualizar_INPC_Nacionales
-- Descripción: Actualiza INPC_Mitad_Periodo en Staging_Activo
--              según la lógica fiscal del SAT
--
-- Debe ejecutarse DESPUÉS del ETL y ANTES del cálculo RMF
-- =============================================

CREATE OR ALTER PROCEDURE dbo.sp_Actualizar_INPC_Nacionales
    @ID_Compania INT,
    @Año_Calculo INT
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '========================================';
    PRINT 'Actualizando INPC para activos nacionales';
    PRINT 'Compañía: ' + CAST(@ID_Compania AS VARCHAR(10));
    PRINT 'Año: ' + CAST(@Año_Calculo AS VARCHAR(10));
    PRINT '========================================';

    DECLARE @ActualizadosTotal INT = 0;

    -- ================================================
    -- CASO 1: Activos DADOS DE BAJA en el año
    -- ================================================
    -- Lógica: Usar mes ANTERIOR a la fecha de baja
    --         Mapear con tabla INPCbajas
    -- ================================================

    PRINT '';
    PRINT '--- CASO 1: Activos dados de baja en el año ---';

    UPDATE s
    SET s.INPC_Mitad_Periodo = i2.Indice
    FROM Staging_Activo s
    INNER JOIN (
        -- Obtener mes anterior a la baja
        SELECT
            ID_Staging,
            MONTH(DATEADD(MONTH, -1, FECHA_BAJA)) AS Mes_Anterior_Baja
        FROM Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND ManejaFiscal = 'S'  -- Solo nacionales
          AND FECHA_BAJA IS NOT NULL
          AND YEAR(FECHA_BAJA) = @Año_Calculo
    ) bajas ON s.ID_Staging = bajas.ID_Staging
    INNER JOIN dbo.INPCbajas ib ON ib.Id_Mes = bajas.Mes_Anterior_Baja
    INNER JOIN [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2 i2 ON
        i2.Anio = @Año_Calculo + ib.AñoINPC  -- AñoINPC puede ser 0 (mismo año) o -1 (año anterior)
        AND i2.Mes = ib.Id_MesINPC
        AND i2.Id_Pais = 1  -- México
        AND (i2.Id_Grupo_Simulacion = 1 OR i2.Id_Grupo_Simulacion IS NULL);

    SET @ActualizadosTotal = @@ROWCOUNT;
    PRINT 'Activos con baja actualizados: ' + CAST(@ActualizadosTotal AS VARCHAR(10));

    -- ================================================
    -- CASO 2: Activos ADQUIRIDOS en el año
    -- ================================================
    -- Lógica: Calcular "mes medio" con fórmula SAT
    --         mes_medio = ROUND((12 - (mes_compra - 1)) / 2, 0, 1) + (mes_compra - 1)
    -- ================================================

    PRINT '';
    PRINT '--- CASO 2: Activos adquiridos en el año ---';

    UPDATE s
    SET s.INPC_Mitad_Periodo = i2.Indice
    FROM Staging_Activo s
    INNER JOIN (
        -- Calcular mes medio según fórmula SAT
        SELECT
            ID_Staging,
            FECHA_COMPRA,
            ROUND((12.0 - (MONTH(FECHA_COMPRA) - 1)) / 2.0, 0, 1) + (MONTH(FECHA_COMPRA) - 1) AS Mes_Medio
        FROM Staging_Activo
        WHERE ID_Compania = @ID_Compania
          AND Año_Calculo = @Año_Calculo
          AND ManejaFiscal = 'S'  -- Solo nacionales
          AND YEAR(FECHA_COMPRA) = @Año_Calculo
          AND (FECHA_BAJA IS NULL OR YEAR(FECHA_BAJA) <> @Año_Calculo)  -- Excluir casos de baja (ya procesados)
    ) adq ON s.ID_Staging = adq.ID_Staging
    INNER JOIN [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2 i2 ON
        i2.Anio = @Año_Calculo
        AND i2.Mes = adq.Mes_Medio
        AND i2.Id_Pais = 1  -- México
        AND (i2.Id_Grupo_Simulacion = 1 OR i2.Id_Grupo_Simulacion IS NULL);

    PRINT 'Activos adquiridos en el año actualizados: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    SET @ActualizadosTotal = @ActualizadosTotal + @@ROWCOUNT;

    -- ================================================
    -- CASO 3: Activos ACTIVOS de años anteriores
    -- ================================================
    -- Lógica: Usar tabla INPCSegunMes
    --         Para cálculo anual (diciembre): mes 12 → mes 6 (junio)
    -- ================================================

    PRINT '';
    PRINT '--- CASO 3: Activos activos de años anteriores ---';

    UPDATE s
    SET s.INPC_Mitad_Periodo = i2.Indice
    FROM Staging_Activo s
    INNER JOIN dbo.INPCSegunMes ism ON ism.MesCalculo = 12  -- Diciembre (Safe Harbor anual)
    INNER JOIN [dbdev.powerera.com].actif_web_cima_dev.dbo.inpc2 i2 ON
        i2.Anio = @Año_Calculo + ism.AñoINPC
        AND i2.Mes = ism.MesINPC
        AND i2.Id_Pais = 1  -- México
        AND (i2.Id_Grupo_Simulacion = 1 OR i2.Id_Grupo_Simulacion IS NULL)
    WHERE s.ID_Compania = @ID_Compania
      AND s.Año_Calculo = @Año_Calculo
      AND s.ManejaFiscal = 'S'  -- Solo nacionales
      AND YEAR(s.FECHA_COMPRA) < @Año_Calculo  -- De años anteriores
      AND (s.FECHA_BAJA IS NULL OR YEAR(s.FECHA_BAJA) <> @Año_Calculo)  -- No dados de baja en el año
      AND s.INPC_Mitad_Periodo IS NULL;  -- Solo los que no se actualizaron antes

    PRINT 'Activos de años anteriores actualizados: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    SET @ActualizadosTotal = @ActualizadosTotal + @@ROWCOUNT;

    -- ================================================
    -- RESUMEN
    -- ================================================

    PRINT '';
    PRINT '========================================';
    PRINT 'TOTAL ACTIVOS ACTUALIZADOS: ' + CAST(@ActualizadosTotal AS VARCHAR(10));

    -- Verificar si quedaron activos sin INPC
    DECLARE @SinINPC INT;
    SELECT @SinINPC = COUNT(*)
    FROM Staging_Activo
    WHERE ID_Compania = @ID_Compania
      AND Año_Calculo = @Año_Calculo
      AND ManejaFiscal = 'S'
      AND INPC_Mitad_Periodo IS NULL;

    IF @SinINPC > 0
    BEGIN
        PRINT '';
        PRINT '⚠️ ADVERTENCIA: ' + CAST(@SinINPC AS VARCHAR(10)) + ' activos quedaron sin INPC_Mitad_Periodo';
        PRINT 'Revisar casos especiales (depreciados, etc.)';
    END

    PRINT '========================================';

    RETURN @ActualizadosTotal;
END
GO
