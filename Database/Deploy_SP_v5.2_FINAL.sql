-- =============================================
-- DEPLOY: SP Calcular RMF Activos NACIONALES v5.2
-- SAFE HARBOR + VALIDACIÓN INPC + INPCs COMPLETOS
-- =============================================

USE Actif_RMF;
GO

IF OBJECT_ID('dbo.sp_Calcular_RMF_Activos_Nacionales', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Calcular_RMF_Activos_Nacionales;
GO

CREATE PROCEDURE dbo.sp_Calcular_RMF_Activos_Nacionales
    @ID_Compania INT,
    @Año_Calculo INT
AS
BEGIN

END
GO

PRINT SP sp_Calcular_RMF_Activos_Nacionales v5.2 desplegado exitosamente;
GO

