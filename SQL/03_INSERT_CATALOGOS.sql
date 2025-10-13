-- =============================================
-- Script: Inserción de Datos de Catálogos
-- =============================================

USE Actif_RMF;
GO

-- =============================================
-- 1. CONFIGURACIÓN DE COMPAÑÍAS
-- =============================================

-- Por ahora, todas apuntan al mismo connection string para pruebas
-- Después se actualizarán con los connection strings específicos

-- Limpiar tabla - las compañías se insertan en script 09
DELETE FROM dbo.ConfiguracionCompania;
GO

PRINT 'ConfiguracionCompania: Tabla limpiada (compañías se insertan en script 09)';
GO

-- =============================================
-- 2. CATÁLOGO DE RUTAS DE CÁLCULO
-- =============================================

DELETE FROM dbo.Catalogo_Rutas_Calculo;
GO

-- RUTAS PARA ACTIVOS EXTRANJEROS
-- Nivel 1: Tipo (1=Extranjero, 2=Mexicano)
-- Nivel 2: Estado del activo (1=Existente, 2=Nuevo, 3=Baja)
-- Nivel 3: Timing (1=Antes Junio, 2=Después Junio, 3=N/A)
-- Nivel 4: Regla especial (1=Normal, 2=Aplica 10% MOI)

INSERT INTO dbo.Catalogo_Rutas_Calculo
    (Ruta_Calculo, Descripcion_Corta, Descripcion_Larga, Tipo_Activo, Nivel_1, Nivel_2, Nivel_3, Nivel_4)
VALUES
    -- ACTIVOS EXTRANJEROS
    ('1.1.3.1', 'EXT - Existente - Normal',
     'Activo extranjero existente antes del año de cálculo, activo todo el año, sin aplicar regla 10% MOI',
     'Extranjero', 'Extranjero', 'Existente', 'Todo el año', 'Normal'),

    ('1.1.3.2', 'EXT - Existente - 10% MOI',
     'Activo extranjero existente, saldo pendiente < 10% MOI, aplica regla mínima del 10%',
     'Extranjero', 'Extranjero', 'Existente', 'Todo el año', 'Aplica 10% MOI'),

    ('1.2.1.1', 'EXT - Nuevo Antes Jun - Normal',
     'Activo extranjero adquirido en el año antes de junio, sin aplicar regla 10%',
     'Extranjero', 'Extranjero', 'Nuevo en año', 'Antes de Junio', 'Normal'),

    ('1.2.1.2', 'EXT - Nuevo Antes Jun - 10% MOI',
     'Activo extranjero adquirido antes de junio, aplica regla 10% MOI',
     'Extranjero', 'Extranjero', 'Nuevo en año', 'Antes de Junio', 'Aplica 10% MOI'),

    ('1.2.2.1', 'EXT - Nuevo Después Jun - Normal',
     'Activo extranjero adquirido después de junio del año de cálculo, sin regla 10%',
     'Extranjero', 'Extranjero', 'Nuevo en año', 'Después de Junio', 'Normal'),

    ('1.2.2.2', 'EXT - Nuevo Después Jun - 10% MOI',
     'Activo extranjero adquirido después de junio, aplica regla 10% MOI',
     'Extranjero', 'Extranjero', 'Nuevo en año', 'Después de Junio', 'Aplica 10% MOI'),

    ('1.3.1.1', 'EXT - Baja en Año - Normal',
     'Activo extranjero dado de baja en el año de cálculo, sin regla 10%',
     'Extranjero', 'Extranjero', 'Baja en año', 'Baja en ejercicio', 'Normal'),

    ('1.3.1.2', 'EXT - Baja en Año - 10% MOI',
     'Activo extranjero dado de baja en el año, aplica regla 10% MOI',
     'Extranjero', 'Extranjero', 'Baja en año', 'Baja en ejercicio', 'Aplica 10% MOI'),

    -- ACTIVOS MEXICANOS
    ('2.1.3.1', 'MEX - Existente - Normal',
     'Activo mexicano existente antes del año, activo todo el año, con actualización INPC',
     'Mexicano', 'Mexicano', 'Existente', 'Todo el año', 'INPC Completo'),

    ('2.2.1.1', 'MEX - Nuevo Antes Jun',
     'Activo mexicano adquirido antes de junio, con actualización INPC parcial',
     'Mexicano', 'Mexicano', 'Nuevo en año', 'Antes de Junio', 'INPC Parcial'),

    ('2.2.2.1', 'MEX - Nuevo Después Jun',
     'Activo mexicano adquirido después de junio, INPC de mitad de periodo ajustado',
     'Mexicano', 'Mexicano', 'Nuevo en año', 'Después de Junio', 'INPC Ajustado'),

    ('2.3.1.1', 'MEX - Baja en Año',
     'Activo mexicano dado de baja en el año de cálculo, INPC proporcional',
     'Mexicano', 'Mexicano', 'Baja en año', 'Baja en ejercicio', 'INPC Proporcional'),

    -- CASOS ESPECIALES
    ('9.9.9.9', 'ERROR - Terreno',
     'Activo tipo terreno, tasa de depreciación = 0, no se calcula',
     'N/A', 'Especial', 'Terreno', 'No aplica', 'Excluido'),

    ('9.9.9.8', 'ERROR - Sin Tasa',
     'No se encontró tasa de depreciación fiscal para el tipo de activo',
     'N/A', 'Error', 'Sin tasa', 'N/A', 'Error'),

    ('9.9.9.7', 'ERROR - Sin INPC',
     'Activo mexicano sin INPC disponible',
     'N/A', 'Error', 'Sin INPC', 'N/A', 'Error');
GO

PRINT 'Catalogo_Rutas_Calculo: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' registros insertados';
GO

-- =============================================
-- 3. TIPO DE CAMBIO (30 de junio 2024)
-- =============================================

DELETE FROM dbo.Tipo_Cambio;
GO

INSERT INTO dbo.Tipo_Cambio (Año, Fecha, ID_Moneda, Nombre_Moneda, Tipo_Cambio, Fuente)
VALUES
    (2024, '2024-06-30', 2, 'USD', 18.2478, 'Manual - Datos de Excel'),
    (2023, '2023-06-30', 2, 'USD', 17.1500, 'Manual - Estimado'),
    (2025, '2025-06-30', 2, 'USD', 18.5000, 'Manual - Estimado');
GO

PRINT 'Tipo_Cambio: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' registros insertados';
GO

PRINT '';
PRINT '===================================';
PRINT 'CATÁLOGOS INICIALIZADOS';
PRINT '===================================';
GO

-- Mostrar resumen
SELECT 'ConfiguracionCompania' AS Tabla, COUNT(*) AS Registros FROM dbo.ConfiguracionCompania
UNION ALL
SELECT 'Catalogo_Rutas_Calculo', COUNT(*) FROM dbo.Catalogo_Rutas_Calculo
UNION ALL
SELECT 'Tipo_Cambio', COUNT(*) FROM dbo.Tipo_Cambio;
GO
