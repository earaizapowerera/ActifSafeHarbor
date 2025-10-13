-- =============================================
-- Script: Creación de Base de Datos Actif_RMF
-- Descripción: Sistema de cálculo RMF para activos NO propios
-- Fecha: 2025-10-12
-- =============================================

USE master;
GO

-- Crear base de datos si no existe
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'Actif_RMF')
BEGIN
    CREATE DATABASE Actif_RMF;
    PRINT 'Base de datos Actif_RMF creada exitosamente';
END
ELSE
BEGIN
    PRINT 'Base de datos Actif_RMF ya existe';
END
GO

USE Actif_RMF;
GO

PRINT 'Contexto cambiado a Actif_RMF';
GO
