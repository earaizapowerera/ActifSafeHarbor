# ValidadorAutoTest - Validación Automática de Cálculos RMF

## Propósito

Programa que compara automáticamente los valores calculados en `Calculo_RMF` contra los valores esperados almacenados en la tabla `AutoTest`. Permite validar rápidamente que las correcciones no rompieron casos anteriores.

## Uso

```bash
cd /Users/enrique/ActifRMF/ValidadorAutoTest/ValidadorAutoTest
dotnet run
```

## Campos Validados

El validador compara 12 campos críticos para cada caso:

### Depreciación
1. MOI
2. Dep_Acum_Inicio
3. Saldo_Inicio_Año
4. Dep_Fiscal_Ejercicio

### Factores Fiscales
5. Factor_Actualizacion_Saldo
6. Factor_Actualizacion_Dep
7. Saldo_Actualizado
8. Dep_Actualizada

### Valores Finales Fiscales
9. Valor_Promedio
10. Valor_Reportable_MXN

### Safe Harbor
11. Factor_SH
12. Valor_SH_Reportable

## Tolerancia

Por defecto: **±$0.01**

Configurable en tabla AutoTest campo `Tolerancia_Decimal`

## Salida

### Ejemplo exitoso:
```
===================================================================================
VALIDADOR AUTOTEST - ActifRMF v2.4.0
===================================================================================

CASO 1: Edificio totalmente depreciado (Tasa 5%)
Folio: 50847 | Año: 2025
-----------------------------------------------------------------------------------
   MOI                            ✅ 59,804.0000
   Dep_Acum_Inicio                ✅ 83,974.7832
   ...
   Valor_SH_Reportable            ✅ 5,980.4000
✅ CASO OK - Todos los campos coinciden

RESUMEN DE VALIDACIÓN
-----------------------------------------------------------------------------------
Total casos:        2
Casos OK:           2 ✅
Casos con ERROR:    0 ❌
Porcentaje éxito:   100.00%
```

### Ejemplo con errores:
```
CASO 1: Edificio totalmente depreciado (Tasa 5%)
-----------------------------------------------------------------------------------
   MOI                            ✅ 59,804.0000
   Factor_Actualizacion_Saldo     ❌ Esperado: 4.8820 | Calc: 1.0000 | Diff: 3.8820
   ...
❌ CASO ERROR - 2 diferencias encontradas:
   Factor_Actualizacion_Saldo: Diferencia 3.8820 (tolerancia: 0.01)
   Factor_Actualizacion_Dep: Diferencia 3.8820 (tolerancia: 0.01)
```

## Exit Code

- **0**: Todos los casos OK
- **1**: Uno o más casos con error

Útil para integración en CI/CD.

## Casos de Prueba

Tabla `AutoTest` contiene casos validados manualmente:

| Caso | Nombre | Folio | Status |
|------|--------|-------|--------|
| 1 | Edificio totalmente depreciado (Tasa 5%) | 50847 | ✅ OK |
| 2 | Vehículo totalmente depreciado (Tasa 25%) | 50909 | ✅ OK |

## Agregar Nuevos Casos

```sql
INSERT INTO AutoTest (
    Numero_Caso, Nombre_Caso, ID_NUM_ACTIVO, ID_Compania, Año_Calculo,
    MOI_Esperado, Tasa_Anual_Esperada, Tasa_Mensual_Esperada,
    -- ... todos los campos esperados
)
VALUES (
    3, 'Edificio reciente (Tasa 15%)', 70001, 12, 2025,
    -- ... valores esperados
);
```

Ver: `/Users/enrique/ActifRMF/Database/INSERT_AutoTest_Casos_1_2.sql`

## Arquitectura

```
┌─────────────────┐
│   AutoTest      │  ← Valores esperados (deber ser)
│   (Tabla BD)    │
└────────┬────────┘
         │
         │ JOIN
         │
┌────────▼────────┐
│  Calculo_RMF    │  ← Valores calculados (resultado real)
│   (Tabla BD)    │
└────────┬────────┘
         │
         │ Comparación
         │
┌────────▼────────┐
│  Validador      │  ← Programa C#
│  (Console App)  │     Compara y reporta diferencias
└─────────────────┘
```

## Conexión Base de Datos

```csharp
Server: dbdev.powerera.com
Database: Actif_RMF
User: earaiza
Password: VgfN-n4ju?H1Z4#JFRE
```

## Desarrollo

### Estructura del Proyecto

```
ValidadorAutoTest/
├── ValidadorAutoTest/
│   ├── Program.cs           # Programa principal
│   ├── ValidadorAutoTest.csproj
│   └── ...
└── README.md               # Este archivo
```

### Dependencias

- .NET 9.0
- Microsoft.Data.SqlClient 6.1.3

### Modificar Campos Validados

Editar `Program.cs`, agregar/remover llamadas a `CompararCampo()`:

```csharp
CompararCampo("Nuevo_Campo", reader, idxEsperado, idxCalculado, tolerancia, erroresCaso, ref casoOk);
```

## Integración CI/CD

```bash
#!/bin/bash
cd /Users/enrique/ActifRMF/ValidadorAutoTest/ValidadorAutoTest
dotnet run

if [ $? -eq 0 ]; then
    echo "✅ Todos los casos de prueba pasaron"
else
    echo "❌ Falló uno o más casos de prueba"
    exit 1
fi
```

## Notas

- **Tolerancia**: Los cálculos con decimales pueden tener pequeñas diferencias de redondeo. La tolerancia de $0.01 es suficiente para validar corrección matemática.

- **Campos NULL**: El validador maneja correctamente campos NULL, comparando que ambos sean NULL o reportando la diferencia.

- **Performance**: Valida 2 casos en ~1 segundo. Escalable a cientos de casos.

## Versión

- **Programa**: v2.4.0
- **Tabla AutoTest**: v1.0
- **Fecha**: 20-nov-2025
