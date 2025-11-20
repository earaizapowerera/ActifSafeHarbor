// Reporte Safe Harbor JavaScript con AG-Grid
// Múltiples compañías, grouping y exportación por hojas

let gridApiExtranjeros;
let gridApiNacionales;
let currentDataExtranjeros = [];
let currentDataNacionales = [];
let companiasList = [];

document.addEventListener('DOMContentLoaded', function() {
    inicializarAños();
    inicializarGrids();

    // Cargar compañías cuando se selecciona un año
    document.getElementById('añoSelect').addEventListener('change', function() {
        const año = this.value;
        if (año) {
            cargarCompaniasPorAño(año);
        } else {
            document.getElementById('companiasContainer').innerHTML = '<div class="text-muted">Seleccione primero un año</div>';
        }
    });

    document.getElementById('btnCargarReporte').addEventListener('click', cargarReporte);
    document.getElementById('btnExportarExcel').addEventListener('click', exportarExcel);
});

function inicializarAños() {
    const añoSelect = document.getElementById('añoSelect');
    const añoActual = new Date().getFullYear();

    añoSelect.innerHTML = '<option value="">Seleccionar año...</option>';
    for (let año = añoActual; año >= añoActual - 10; año--) {
        añoSelect.innerHTML += `<option value="${año}">${año}</option>`;
    }
}

async function cargarCompaniasPorAño(año) {
    try {
        console.log(`[reporte.js] Cargando compañías para año: ${año}`);
        const container = document.getElementById('companiasContainer');
        container.innerHTML = '<div class="text-muted"><i class="fas fa-spinner fa-spin"></i> Cargando compañías...</div>';

        const url = `/api/reporte/companias-con-registros?a%C3%B1o=${encodeURIComponent(año)}&v=${Date.now()}`;
        console.log(`[reporte.js] URL: ${url}`);
        const response = await fetch(url);
        if (!response.ok) {
            console.error(`[reporte.js] Error en respuesta: ${response.status}`);
            throw new Error('Error al cargar compañías');
        }

        companiasList = await response.json();
        console.log(`[reporte.js] Compañías recibidas:`, companiasList);

        if (companiasList.length === 0) {
            container.innerHTML = '<div class="alert alert-warning">No hay compañías con registros calculados para este año</div>';
            return;
        }

        let html = '<div class="mb-2"><input type="checkbox" id="selectAll" class="form-check-input me-2">';
        html += '<label for="selectAll" class="form-check-label fw-bold">Seleccionar Todas</label></div><hr>';

        companiasList.forEach(c => {
            html += `
                <div class="form-check mb-2">
                    <input class="form-check-input compania-check" type="checkbox" value="${c.idCompania}" id="cia_${c.idCompania}">
                    <label class="form-check-label" for="cia_${c.idCompania}">
                        ${c.nombreCompania} <span class="badge bg-primary">${c.totalRegistros || 0} registros</span>
                    </label>
                </div>
            `;
        });

        container.innerHTML = html;

        // Manejar select all
        document.getElementById('selectAll').addEventListener('change', function() {
            document.querySelectorAll('.compania-check').forEach(cb => {
                cb.checked = this.checked;
            });
        });
    } catch (error) {
        console.error('Error:', error);
        document.getElementById('companiasContainer').innerHTML = '<div class="alert alert-danger">Error al cargar compañías</div>';
    }
}

function inicializarGrids() {
    inicializarGridExtranjeros();
    inicializarGridNacionales();
}

function inicializarGridExtranjeros() {
    const columnDefs = [
        {
            headerName: 'Compañía',
            field: 'nombreCompania',
            filter: 'agTextColumnFilter',
            width: 200,
            pinned: 'left',
            rowGroup: true,  // Agrupar por compañía
            hide: true       // Ocultar columna individual, solo mostrar grupos
        },
        {
            headerName: 'Folio',
            field: 'folio',
            filter: 'agNumberColumnFilter',
            width: 100
        },
        {
            headerName: 'Placa',
            field: 'placa',
            filter: 'agTextColumnFilter',
            width: 150
        },
        {
            headerName: 'Descripción',
            field: 'descripcion',
            filter: 'agTextColumnFilter',
            width: 300
        },
        {
            headerName: 'Tipo',
            field: 'tipo',
            filter: 'agTextColumnFilter',
            width: 180
        },
        {
            headerName: 'Fecha Adquisición',
            field: 'fechaAdquisicion',
            filter: 'agDateColumnFilter',
            width: 150,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Inicio Depreciación',
            field: 'fechaInicioDepreciacion',
            filter: 'agDateColumnFilter',
            width: 180,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Fin Depreciación',
            field: 'fechaFinDepreciacion',
            filter: 'agDateColumnFilter',
            width: 180,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Baja',
            field: 'fechaBaja',
            filter: 'agDateColumnFilter',
            width: 130,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'MOI',
            field: 'moi',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            aggFunc: 'sum',  // Sumar en subtotales
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Anual Rate',
            field: 'anualRate',
            filter: 'agNumberColumnFilter',
            width: 120,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(4) : ''
        },
        {
            headerName: 'Month Rate',
            field: 'monthRate',
            filter: 'agNumberColumnFilter',
            width: 120,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'Deprec Anual',
            field: 'deprecAnual',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Meses Uso Inicio Ejerc.',
            field: 'mesesUsoAlInicioEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn'
        },
        {
            headerName: 'Meses Uso Hasta Mitad',
            field: 'mesesUsoHastaMitadPeriodo',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn'
        },
        {
            headerName: 'Meses Uso En Ejercicio',
            field: 'mesesUsoEnEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn'
        },
        {
            headerName: 'Dep Fiscal Acum. Inicio Año',
            field: 'depFiscalAcumuladaInicioAño',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Saldo Por Deducir ISR Inicio',
            field: 'saldoPorDeducirISRAlInicioAño',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Dep Fiscal Ejercicio',
            field: 'depreciacionFiscalDelEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Monto Pendiente',
            field: 'montoPendientePorDeducir',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Proporción',
            field: 'proporcionMontoPendientePorDeducir',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'SH_Prueba 10% MOI',
            field: 'pruebaDel10PctMOI',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'Tipo Cambio 30 Junio',
            field: 'tipoCambio30Junio',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'SH_Valor Reportable MXN',
            field: 'valorProporcionalAñoPesos',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value ? '$' + params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'font-weight': 'bold', 'color': '#198754', 'background-color': '#d1e7dd'}
        },
        {
            headerName: 'Observaciones',
            field: 'observaciones',
            filter: 'agTextColumnFilter',
            width: 400
        }
    ];

    const gridOptions = {
        columnDefs: columnDefs,
        defaultColDef: {
            sortable: true,
            resizable: true,
            filter: true,
            floatingFilter: true
        },
        autoGroupColumnDef: {
            headerName: 'Compañía',
            field: 'nombreCompania',
            width: 250,
            pinned: 'left',
            cellRendererParams: {
                suppressCount: false,  // Mostrar contador de registros
                innerRenderer: params => {
                    // Mostrar nombre de compañía en el grupo
                    if (params.node.group) {
                        return params.value || 'Sin compañía';
                    }
                    return params.value;
                }
            }
        },
        pagination: true,
        paginationPageSize: 50,
        paginationPageSizeSelector: [20, 50, 100, 200],
        rowSelection: 'multiple',
        enableRangeSelection: true,
        suppressRowClickSelection: true,
        animateRows: true,
        groupDisplayType: 'singleColumn',  // Mostrar grupos en una sola columna
        groupDefaultExpanded: 1,            // Expandir primer nivel
        groupIncludeTotalFooter: true,      // Mostrar totales al final
        grandTotalRow: 'bottom',            // Total general al final
        suppressAggFuncInHeader: true,      // No mostrar "sum(" en headers
        overlayNoRowsTemplate: '<span style="padding: 20px; font-size: 16px; color: #666;">No hay activos extranjeros para mostrar</span>',
        onGridReady: function(params) {
            gridApiExtranjeros = params.api;
        }
    };

    const gridDiv = document.querySelector('#gridExtranjeros');
    agGrid.createGrid(gridDiv, gridOptions);
}

function inicializarGridNacionales() {
    const columnDefs = [
        {
            headerName: 'Compañía',
            field: 'nombreCompania',
            filter: 'agTextColumnFilter',
            width: 200,
            pinned: 'left',
            rowGroup: true,  // Agrupar por compañía
            hide: true       // Ocultar columna individual
        },
        {
            headerName: 'Folio',
            field: 'folio',
            filter: 'agNumberColumnFilter',
            width: 100
        },
        {
            headerName: 'Placa',
            field: 'placa',
            filter: 'agTextColumnFilter',
            width: 150
        },
        {
            headerName: 'Descripción',
            field: 'descripcion',
            filter: 'agTextColumnFilter',
            width: 300
        },
        {
            headerName: 'Tipo',
            field: 'tipo',
            filter: 'agTextColumnFilter',
            width: 180
        },
        {
            headerName: 'Fecha Adquisición',
            field: 'fechaAdquisicion',
            filter: 'agDateColumnFilter',
            width: 150,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Inicio Depreciación',
            field: 'fechaInicioDepreciacion',
            filter: 'agDateColumnFilter',
            width: 180,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Fin Depreciación',
            field: 'fechaFinDepreciacion',
            filter: 'agDateColumnFilter',
            width: 180,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'Fecha Baja',
            field: 'fechaBaja',
            filter: 'agDateColumnFilter',
            width: 130,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX');
            }
        },
        {
            headerName: 'MOI',
            field: 'moi',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Anual Rate',
            field: 'anualRate',
            filter: 'agNumberColumnFilter',
            width: 120,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(4) : ''
        },
        {
            headerName: 'Month Rate',
            field: 'monthRate',
            filter: 'agNumberColumnFilter',
            width: 120,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'Deprec Anual',
            field: 'deprecAnual',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Meses Uso Al Ejerc. Anterior',
            field: 'mesesUsoAlEjercicioAnterior',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn'
        },
        {
            headerName: 'Meses Uso En Ejercicio',
            field: 'mesesUsoEnEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn'
        },
        {
            headerName: 'Dep Fiscal Acum. Inicio Año',
            field: 'depFiscalAcumuladaInicioAño',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Saldo Por Deducir ISR Inicio',
            field: 'saldoPorDeducirISRAlInicioAño',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        // PASO 1: INPC Actualización FISCAL
        {
            headerName: 'FI_INPC Adquisición',
            field: 'inpcAdquisicion',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : '',
            cellStyle: {'background-color': '#e7f3ff'}
        },
        {
            headerName: 'FI_INPC Mitad Ejercicio',
            field: 'inpcMitadEjercicio',
            filter: 'agNumberColumnFilter',
            width: 170,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : '',
            cellStyle: {'background-color': '#e7f3ff'}
        },
        {
            headerName: 'FI_Factor Actualiz. (P1)',
            field: 'factorActualizacionPaso1',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(4) : '',
            cellStyle: {'background-color': '#e7f3ff', 'font-weight': 'bold'}
        },
        {
            headerName: 'FI_Saldo Actualizado (P1)',
            field: 'saldoActualizadoPaso1',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#e7f3ff', 'font-weight': 'bold'}
        },
        // PASO 2: Depreciación Actualizada FISCAL
        {
            headerName: 'Dep Fiscal Ejercicio',
            field: 'depreciacionFiscalDelEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#fff3cd'}
        },
        {
            headerName: 'FI_INPC Adquisición (P2)',
            field: 'inpcAdquPaso2',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : '',
            cellStyle: {'background-color': '#fff3cd'}
        },
        {
            headerName: 'FI_INPC Mitad Periodo',
            field: 'inpcMitadPeriodo',
            filter: 'agNumberColumnFilter',
            width: 170,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : '',
            cellStyle: {'background-color': '#fff3cd'}
        },
        {
            headerName: 'FI_Factor Actualiz. (P2)',
            field: 'factorActualizacionPaso2',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(4) : '',
            cellStyle: {'background-color': '#fff3cd', 'font-weight': 'bold'}
        },
        {
            headerName: 'FI_Deprec Fiscal Actualizada',
            field: 'depreciacionFiscalActualizada',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#fff3cd', 'font-weight': 'bold'}
        },
        {
            headerName: 'FI_50% Deprec Fiscal',
            field: 'mitadDepreciacionFiscal',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#fff3cd', 'font-weight': 'bold'}
        },
        // PASO 3: Valor FISCAL
        {
            headerName: 'FI_Valor Promedio',
            field: 'valorPromedio',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#fff3cd'}
        },
        {
            headerName: 'FI_Valor Prom. Prop. Año',
            field: 'valorPromedioProporcionalAño',
            filter: 'agNumberColumnFilter',
            width: 190,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#fff3cd', 'font-weight': 'bold', 'color': '#0d6efd'}
        },
        // CAMPOS SAFE HARBOR
        {
            headerName: 'SH_INPC Junio',
            field: 'inpcSHJunio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_Factor Actualiz.',
            field: 'factorSH',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(4) : '',
            cellStyle: {'background-color': '#d1e7dd', 'font-weight': 'bold'}
        },
        {
            headerName: 'SH_Saldo Actualizado',
            field: 'saldoSHActualizado',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd', 'font-weight': 'bold'}
        },
        {
            headerName: 'SH_Dep Actualizada',
            field: 'depSHActualizada',
            filter: 'agNumberColumnFilter',
            width: 170,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_50% Dep',
            field: 'mitadDepSH',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_Valor Promedio',
            field: 'valorSHPromedio',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_Valor Prom. Prop. Año',
            field: 'valorSHProporcionalAño',
            filter: 'agNumberColumnFilter',
            width: 190,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd', 'font-weight': 'bold'}
        },
        {
            headerName: 'SH_Prueba 10% MOI',
            field: 'pruebaDel10PctMOI',
            filter: 'agNumberColumnFilter',
            width: 160,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_Valor Reportable',
            field: 'valorReportableSafeHarbor',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd', 'font-weight': 'bold', 'color': '#198754', 'font-size': '13px'}
        },
        {
            headerName: 'SH_Saldo Fiscal Deducir Hist.',
            field: 'saldoFiscalPorDeducirHistorico',
            filter: 'agNumberColumnFilter',
            width: 200,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'SH_Saldo Fiscal Deducir Actual.',
            field: 'saldoFiscalPorDeducirActualizado',
            filter: 'agNumberColumnFilter',
            width: 210,
            type: 'numericColumn',
            aggFunc: 'sum',
            valueFormatter: params => params.value != null ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'background-color': '#d1e7dd'}
        },
        {
            headerName: 'Estado (B/A)',
            field: 'estadoActivoBaja',
            filter: 'agTextColumnFilter',
            width: 120,
            cellStyle: params => {
                if (params.value === 'B') {
                    return {'background-color': '#f8d7da', 'font-weight': 'bold'};
                }
                return {'background-color': '#d1e7dd'};
            }
        },
        {
            headerName: 'Observaciones',
            field: 'observaciones',
            filter: 'agTextColumnFilter',
            width: 400
        }
    ];

    const gridOptions = {
        columnDefs: columnDefs,
        defaultColDef: {
            sortable: true,
            resizable: true,
            filter: true,
            floatingFilter: true
        },
        autoGroupColumnDef: {
            headerName: 'Compañía',
            field: 'nombreCompania',
            width: 250,
            pinned: 'left',
            cellRendererParams: {
                suppressCount: false,  // Mostrar contador de registros
                innerRenderer: params => {
                    // Mostrar nombre de compañía en el grupo
                    if (params.node.group) {
                        return params.value || 'Sin compañía';
                    }
                    return params.value;
                }
            }
        },
        pagination: true,
        paginationPageSize: 50,
        paginationPageSizeSelector: [20, 50, 100, 200],
        rowSelection: 'multiple',
        enableRangeSelection: true,
        suppressRowClickSelection: true,
        animateRows: true,
        groupDisplayType: 'singleColumn',
        groupDefaultExpanded: 1,
        groupIncludeTotalFooter: true,
        grandTotalRow: 'bottom',
        suppressAggFuncInHeader: true,      // No mostrar "sum(" en headers
        overlayNoRowsTemplate: '<span style="padding: 20px; font-size: 16px; color: #666;">No hay activos nacionales para mostrar</span>',
        onGridReady: function(params) {
            gridApiNacionales = params.api;
        }
    };

    const gridDiv = document.querySelector('#gridNacionales');
    agGrid.createGrid(gridDiv, gridOptions);
}

async function cargarReporte() {
    const companiasSeleccionadas = Array.from(document.querySelectorAll('.compania-check:checked')).map(cb => cb.value);
    const añoCalculo = document.getElementById('añoSelect').value;

    if (companiasSeleccionadas.length === 0 || !añoCalculo) {
        alert('Por favor seleccione al menos una compañía y un año');
        return;
    }

    try {
        const btnCargar = document.getElementById('btnCargarReporte');
        btnCargar.disabled = true;
        btnCargar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Cargando...';

        // Cache-busting con timestamp
        const response = await fetch(`/api/reporte?companias=${companiasSeleccionadas.join(',')}&año=${añoCalculo}&v=${Date.now()}`);
        if (!response.ok) throw new Error('Error al cargar reporte');

        const data = await response.json();

        // El backend ahora devuelve: { extranjeros: [], nacionales: [], totales: {} }
        currentDataExtranjeros = data.extranjeros || [];
        currentDataNacionales = data.nacionales || [];

        // Cargar datos en los grids
        gridApiExtranjeros.setGridOption('rowData', currentDataExtranjeros);
        gridApiNacionales.setGridOption('rowData', currentDataNacionales);

        // Mostrar overlays si no hay datos
        if (currentDataExtranjeros.length === 0) {
            gridApiExtranjeros.showNoRowsOverlay();
        }
        if (currentDataNacionales.length === 0) {
            gridApiNacionales.showNoRowsOverlay();
        }

        // Calcular totales combinados
        const totalRegistros = currentDataExtranjeros.length + currentDataNacionales.length;
        document.getElementById('contadorRegistros').textContent = `${totalRegistros} registros (${currentDataExtranjeros.length} extranjeros, ${currentDataNacionales.length} nacionales)`;
        document.getElementById('btnExportarExcel').disabled = totalRegistros === 0;

        // Calcular y mostrar totales
        if (totalRegistros > 0) {
            // MOI: suma de ambos arrays
            const totalMOI_Ext = currentDataExtranjeros.reduce((sum, row) => sum + (row.moi || 0), 0);
            const totalMOI_Nac = currentDataNacionales.reduce((sum, row) => sum + (row.moi || 0), 0);
            const totalMOI = totalMOI_Ext + totalMOI_Nac;

            // Valor Reportable: extranjeros usan Valor_Reportable_MXN, nacionales usan Valor_Promedio_Proporcional_Año
            const totalValor_Ext = currentDataExtranjeros.reduce((sum, row) => sum + (row.valorProporcionalAñoPesos || 0), 0);
            const totalValor_Nac = currentDataNacionales.reduce((sum, row) => sum + (row.valorPromedioProporcionalAño || 0), 0);
            const totalValor = totalValor_Ext + totalValor_Nac;

            // Activos con 10% MOI: solo extranjeros tienen esta prueba
            const totalActivos10Pct = currentDataExtranjeros.filter(row => (row.pruebaDel10PctMOI || 0) > 0).length;

            // Actualizar tarjeta de totales
            document.getElementById('totalRegistros').textContent = totalRegistros.toLocaleString('en-US');
            document.getElementById('totalMOI').textContent = '$' + totalMOI.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});
            document.getElementById('totalActivos10Pct').textContent = totalActivos10Pct.toLocaleString('en-US');
            document.getElementById('totalValorReportable').textContent = '$' + totalValor.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});

            // Mostrar contenedor de totales
            document.getElementById('totalesContainer').style.display = 'block';

            // Mensaje de éxito
            console.log('Reporte cargado exitosamente:', {
                totalExtranjeros: currentDataExtranjeros.length,
                totalNacionales: currentDataNacionales.length,
                totalMOI: totalMOI,
                activosCon10Pct: totalActivos10Pct,
                valorTotalReportable: totalValor
            });
        } else {
            document.getElementById('totalesContainer').style.display = 'none';
        }

        btnCargar.disabled = false;
        btnCargar.innerHTML = '<i class="fas fa-search"></i> Cargar';

    } catch (error) {
        console.error('Error:', error);
        alert('Error al cargar el reporte: ' + error.message);

        const btnCargar = document.getElementById('btnCargarReporte');
        btnCargar.disabled = false;
        btnCargar.innerHTML = '<i class="fas fa-search"></i> Cargar';
    }
}

function exportarExcel() {
    const totalRegistros = currentDataExtranjeros.length + currentDataNacionales.length;

    if (totalRegistros === 0) {
        alert('No hay datos para exportar');
        return;
    }

    const año = document.getElementById('añoSelect').value;
    const fecha = new Date().toISOString().split('T')[0];

    // Agrupar datos por compañía e idCompania
    const companiaGroups = {};

    // Procesar extranjeros
    currentDataExtranjeros.forEach(row => {
        const key = `${row.nombreCompania}|${row.idCompania}`;
        if (!companiaGroups[key]) {
            companiaGroups[key] = {
                nombre: row.nombreCompania,
                idCompania: row.idCompania,
                extranjeros: [],
                nacionales: []
            };
        }
        companiaGroups[key].extranjeros.push(row);
    });

    // Procesar nacionales
    currentDataNacionales.forEach(row => {
        const key = `${row.nombreCompania}|${row.idCompania}`;
        if (!companiaGroups[key]) {
            companiaGroups[key] = {
                nombre: row.nombreCompania,
                idCompania: row.idCompania,
                extranjeros: [],
                nacionales: []
            };
        }
        companiaGroups[key].nacionales.push(row);
    });

    // Crear un nuevo libro de Excel
    const workbook = XLSX.utils.book_new();
    let sheetsAdded = 0;

    // Obtener las definiciones de columnas (sin las ocultas)
    const colDefsExtranjeros = gridApiExtranjeros.getColumnDefs().filter(col => !col.hide);
    const colDefsNacionales = gridApiNacionales.getColumnDefs().filter(col => !col.hide);

    // Función auxiliar para convertir datos a worksheet
    function createWorksheet(data, columnDefs) {
        // Crear headers
        const headers = columnDefs.map(col => col.headerName);

        // Crear filas de datos - USAR VALORES RAW, NO FORMATTERS
        const rows = data.map(row => {
            return columnDefs.map(col => {
                const value = row[col.field];

                // Si es null o undefined, retornar vacío
                if (value === null || value === undefined) return '';

                // Si es fecha, formatear como string para Excel
                if (col.field.includes('fecha') || col.field.includes('Fecha')) {
                    if (!value) return '';
                    const date = new Date(value);
                    return date.toLocaleDateString('es-MX');
                }

                // Para números, retornar el valor raw (Excel lo formateará automáticamente)
                // NO usar valueFormatter ya que puede causar problemas de tipo
                return value;
            });
        });

        // Combinar headers y rows
        const wsData = [headers, ...rows];

        // Crear worksheet
        const ws = XLSX.utils.aoa_to_sheet(wsData);

        // Aplicar formato de moneda SOLO a columnas monetarias
        const range = XLSX.utils.decode_range(ws['!ref']);

        // Campos monetarios (que representan dinero)
        const camposMonetarios = [
            'moi', 'deprecAnual', 'depFiscalAcumuladaInicioAño',
            'saldoPorDeducirISRAlInicioAño', 'depreciacionFiscalDelEjercicio',
            'montoPendientePorDeducir', 'proporcionMontoPendientePorDeducir',
            'pruebaDel10PctMOI', 'valorProporcionalAñoPesos',
            'valorPromedioProporcionalAño', 'costoRevaluado', 'factorActualizacion',
            'moiActualizado', 'depAcumActual', 'saldoPorDepreciarInicioPeriodo',
            'depEjercicioActualizada', 'saldoPorDepreciarDespuesDelEjercicio',
            'promedioActivoFijoAcumuladoAnual',
            // Campos Safe Harbor Nacionales
            'saldoActualizadoPaso1', 'depreciacionFiscalActualizada', 'mitadDepreciacionFiscal',
            'valorPromedio', 'valorReportableSafeHarbor', 'saldoFiscalPorDeducirHistorico',
            'saldoFiscalPorDeducirActualizado'
        ];

        for (let R = range.s.r + 1; R <= range.e.r; ++R) {
            for (let C = range.s.c; C <= range.e.c; ++C) {
                const cellAddress = XLSX.utils.encode_cell({ r: R, c: C });
                const cell = ws[cellAddress];

                if (!cell) continue;

                const colDef = columnDefs[C];
                const value = cell.v;

                // Si es un número Y la columna es monetaria, aplicar formato de moneda
                if (typeof value === 'number' && cell.t === 'n' && colDef && camposMonetarios.includes(colDef.field)) {
                    cell.z = '$#,##0.00';
                }
            }
        }

        // Aplicar estilos de color a las columnas (si la celda tiene estilo definido)
        for (let R = range.s.r; R <= range.e.r; ++R) {
            for (let C = range.s.c; C <= range.e.c; ++C) {
                const cellAddress = XLSX.utils.encode_cell({ r: R, c: C });
                const cell = ws[cellAddress];

                if (!cell) continue;

                const colDef = columnDefs[C];
                if (!colDef || !colDef.cellStyle) continue;

                // Obtener color de fondo del cellStyle
                const bgColor = colDef.cellStyle['background-color'];

                if (bgColor) {
                    // Inicializar objeto s si no existe
                    if (!cell.s) cell.s = {};

                    // Convertir color hex a RGB para Excel
                    let fillColor = 'FFFFFF'; // Blanco por defecto

                    if (bgColor === '#e7f3ff') fillColor = 'E7F3FF'; // Azul claro (Fiscal Paso 1)
                    else if (bgColor === '#fff3cd') fillColor = 'FFF3CD'; // Amarillo claro (Fiscal Paso 2)
                    else if (bgColor === '#d1e7dd') fillColor = 'D1E7DD'; // Verde claro (Safe Harbor)

                    // Aplicar estilo (nota: SheetJS básico no soporta esto, pero lo dejamos para futuras versiones)
                    cell.s.fill = { fgColor: { rgb: fillColor } };

                    // Si es bold según cellStyle
                    if (colDef.cellStyle['font-weight'] === 'bold') {
                        if (!cell.s.font) cell.s.font = {};
                        cell.s.font.bold = true;
                    }
                }
            }
        }

        // Ajustar anchos de columna
        const colWidths = columnDefs.map(col => ({
            wch: Math.max(col.width ? col.width / 8 : 15, (col.headerName || '').length + 2)
        }));
        ws['!cols'] = colWidths;

        return ws;
    }

    // Función para sanear nombres de hojas (Excel tiene límite de 31 caracteres y no permite ciertos caracteres)
    function sanitizeSheetName(name) {
        // Reemplazar caracteres no permitidos en nombres de hojas de Excel
        let sanitized = name.replace(/[:\\\/\?\*\[\]]/g, '_');
        // Limitar a 31 caracteres
        if (sanitized.length > 31) {
            sanitized = sanitized.substring(0, 31);
        }
        return sanitized;
    }

    // Procesar cada compañía y agregar hojas al libro
    Object.values(companiaGroups).forEach(group => {
        const companiaNombre = group.nombre;

        // Agregar hoja de extranjeros si hay datos
        if (group.extranjeros.length > 0) {
            const sheetName = sanitizeSheetName(`${companiaNombre} - Extranjeros`);
            const worksheet = createWorksheet(group.extranjeros, colDefsExtranjeros);
            XLSX.utils.book_append_sheet(workbook, worksheet, sheetName);
            sheetsAdded++;
        }

        // Agregar hoja de nacionales si hay datos
        if (group.nacionales.length > 0) {
            const sheetName = sanitizeSheetName(`${companiaNombre} - Nacionales`);
            const worksheet = createWorksheet(group.nacionales, colDefsNacionales);
            XLSX.utils.book_append_sheet(workbook, worksheet, sheetName);
            sheetsAdded++;
        }
    });

    // Exportar el libro como archivo XLSX
    const fileName = `SafeHarbor_${año}_${fecha}.xlsx`;
    XLSX.writeFile(workbook, fileName);

    alert(`Exportación completada:\n${sheetsAdded} hojas en el archivo ${fileName}`);
}
