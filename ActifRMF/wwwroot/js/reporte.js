// Reporte Safe Harbor JavaScript con AG-Grid

let gridApi;
let gridColumnApi;
let currentData = [];

document.addEventListener('DOMContentLoaded', function() {
    cargarCompanias();
    inicializarAños();
    inicializarGrid();

    document.getElementById('btnCargarReporte').addEventListener('click', cargarReporte);
    document.getElementById('btnExportarExcel').addEventListener('click', exportarExcel);
});

function inicializarAños() {
    const añoSelect = document.getElementById('añoSelect');
    const añoActual = new Date().getFullYear();

    añoSelect.innerHTML = '<option value="">Seleccionar...</option>';
    for (let año = añoActual; año >= añoActual - 10; año--) {
        añoSelect.innerHTML += `<option value="${año}">${año}</option>`;
    }
}

async function cargarCompanias() {
    try {
        const response = await fetch('/api/companias');
        if (!response.ok) throw new Error('Error al cargar compañías');

        const companias = await response.json();
        const select = document.getElementById('companiaSelect');

        select.innerHTML = '<option value="">Seleccionar...</option>';
        companias.forEach(c => {
            select.innerHTML += `<option value="${c.idCompania}">${c.nombreCompania}</option>`;
        });
    } catch (error) {
        console.error('Error:', error);
        alert('Error al cargar las compañías');
    }
}

function inicializarGrid() {
    const columnDefs = [
        {
            headerName: 'ID Activo',
            field: 'idNumActivo',
            filter: 'agNumberColumnFilter',
            width: 120,
            pinned: 'left'
        },
        {
            headerName: 'Placa',
            field: 'placa',
            filter: 'agTextColumnFilter',
            width: 150,
            pinned: 'left'
        },
        {
            headerName: 'Descripción',
            field: 'descripcion',
            filter: 'agTextColumnFilter',
            width: 300
        },
        {
            headerName: 'Tipo Activo',
            field: 'tipoActivo',
            filter: 'agTextColumnFilter',
            width: 180
        },
        {
            headerName: 'País',
            field: 'pais',
            filter: 'agTextColumnFilter',
            width: 150
        },
        {
            headerName: 'Ruta',
            field: 'rutaCalculo',
            filter: 'agTextColumnFilter',
            width: 100
        },
        {
            headerName: 'Descripción Ruta',
            field: 'descripcionRuta',
            filter: 'agTextColumnFilter',
            width: 250
        },
        {
            headerName: 'MOI (USD)',
            field: 'moi',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'INPC Adq.',
            field: 'inpcAdquisicion',
            filter: 'agNumberColumnFilter',
            width: 130,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'INPC Mitad Ej.',
            field: 'inpcMitadEjercicio',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'Meses Inicio',
            field: 'mesesInicio',
            filter: 'agNumberColumnFilter',
            width: 130,
            type: 'numericColumn'
        },
        {
            headerName: 'Meses Mitad',
            field: 'mesesMitad',
            filter: 'agNumberColumnFilter',
            width: 130,
            type: 'numericColumn'
        },
        {
            headerName: 'Meses Ejercicio',
            field: 'mesesEjercicio',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn'
        },
        {
            headerName: 'Saldo Inicio',
            field: 'saldoInicio',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Dep. Ejercicio',
            field: 'depEjercicio',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Monto Pendiente',
            field: 'montoPendiente',
            filter: 'agNumberColumnFilter',
            width: 150,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Proporción',
            field: 'proporcion',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Prueba 10%',
            field: 'prueba10Pct',
            filter: 'agNumberColumnFilter',
            width: 140,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ''
        },
        {
            headerName: 'Aplica 10%',
            field: 'aplica10Pct',
            filter: 'agSetColumnFilter',
            width: 120,
            valueFormatter: params => params.value ? 'Sí' : 'No'
        },
        {
            headerName: 'T/C 30-Jun',
            field: 'tipoCambio',
            filter: 'agNumberColumnFilter',
            width: 130,
            type: 'numericColumn',
            valueFormatter: params => params.value ? params.value.toFixed(6) : ''
        },
        {
            headerName: 'Valor Reportable MXN',
            field: 'valorReportable',
            filter: 'agNumberColumnFilter',
            width: 180,
            type: 'numericColumn',
            valueFormatter: params => params.value ? '$' + params.value.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2}) : '',
            cellStyle: {'font-weight': 'bold', 'color': '#0d6efd'}
        },
        {
            headerName: 'Observaciones',
            field: 'observaciones',
            filter: 'agTextColumnFilter',
            width: 400
        },
        {
            headerName: 'Fecha Cálculo',
            field: 'fechaCalculo',
            filter: 'agDateColumnFilter',
            width: 180,
            valueFormatter: params => {
                if (!params.value) return '';
                const date = new Date(params.value);
                return date.toLocaleDateString('es-MX', {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                });
            }
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
        pagination: true,
        paginationPageSize: 50,
        paginationPageSizeSelector: [20, 50, 100, 200],
        rowSelection: 'multiple',
        enableRangeSelection: true,
        suppressRowClickSelection: true,
        animateRows: true,
        overlayNoRowsTemplate: '<span style="padding: 20px; font-size: 16px; color: #666;">No hay registros para mostrar</span>',
        onGridReady: function(params) {
            gridApi = params.api;
            gridColumnApi = params.columnApi;
        }
    };

    const gridDiv = document.querySelector('#reporteGrid');
    agGrid.createGrid(gridDiv, gridOptions);
}

async function cargarReporte() {
    const idCompania = document.getElementById('companiaSelect').value;
    const añoCalculo = document.getElementById('añoSelect').value;

    if (!idCompania || !añoCalculo) {
        alert('Por favor seleccione compañía y año');
        return;
    }

    try {
        const btnCargar = document.getElementById('btnCargarReporte');
        btnCargar.disabled = true;
        btnCargar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Cargando...';

        const response = await fetch(`/api/reporte/${idCompania}/${añoCalculo}`);
        if (!response.ok) throw new Error('Error al cargar reporte');

        const data = await response.json();
        currentData = data;

        gridApi.setGridOption('rowData', data);

        document.getElementById('contadorRegistros').textContent = `${data.length} registros`;
        document.getElementById('btnExportarExcel').disabled = false;

        // Calcular y mostrar totales
        if (data.length > 0) {
            const totalMOI = data.reduce((sum, row) => sum + (row.moi || 0), 0);
            const totalValor = data.reduce((sum, row) => sum + (row.valorReportable || 0), 0);
            const totalActivos10Pct = data.filter(row => row.aplica10Pct).length;

            // Actualizar tarjeta de totales
            document.getElementById('totalRegistros').textContent = data.length.toLocaleString('en-US');
            document.getElementById('totalMOI').textContent = '$' + totalMOI.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});
            document.getElementById('totalActivos10Pct').textContent = totalActivos10Pct.toLocaleString('en-US');
            document.getElementById('totalValorReportable').textContent = '$' + totalValor.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2});

            // Mostrar contenedor de totales
            document.getElementById('totalesContainer').style.display = 'block';

            // Mensaje de éxito
            console.log('Reporte cargado exitosamente:', {
                totalActivos: data.length,
                totalMOI: totalMOI,
                activosCon10Pct: totalActivos10Pct,
                valorTotalReportable: totalValor
            });
        } else {
            gridApi.showNoRowsOverlay();
            document.getElementById('totalesContainer').style.display = 'none';
        }

        btnCargar.disabled = false;
        btnCargar.innerHTML = '<i class="fas fa-search"></i> Cargar Reporte';

    } catch (error) {
        console.error('Error:', error);
        alert('Error al cargar el reporte: ' + error.message);

        const btnCargar = document.getElementById('btnCargarReporte');
        btnCargar.disabled = false;
        btnCargar.innerHTML = '<i class="fas fa-search"></i> Cargar Reporte';
    }
}

function exportarExcel() {
    if (!currentData || currentData.length === 0) {
        alert('No hay datos para exportar');
        return;
    }

    const companiaText = document.getElementById('companiaSelect').selectedOptions[0].text;
    const año = document.getElementById('añoSelect').value;
    const fecha = new Date().toISOString().split('T')[0];

    const params = {
        fileName: `Reporte_SafeHarbor_${companiaText.replace(/\s+/g, '_')}_${año}_${fecha}.csv`,
        sheetName: `Safe Harbor ${año}`,
        columnKeys: [
            'idNumActivo', 'placa', 'descripcion', 'tipoActivo', 'pais',
            'rutaCalculo', 'descripcionRuta', 'moi', 'inpcAdquisicion', 'inpcMitadEjercicio',
            'mesesInicio', 'mesesMitad', 'mesesEjercicio', 'saldoInicio', 'depEjercicio',
            'montoPendiente', 'proporcion', 'prueba10Pct', 'aplica10Pct', 'tipoCambio',
            'valorReportable', 'observaciones', 'fechaCalculo'
        ],
        processCellCallback: function(params) {
            // Formatear valores booleanos
            if (params.column.getColId() === 'aplica10Pct') {
                return params.value ? 'Sí' : 'No';
            }
            return params.value;
        }
    };

    // Exportar como CSV (ag-Grid Community no soporta Excel nativo, necesitaría Enterprise)
    gridApi.exportDataAsCsv(params);

    console.log(`Archivo exportado: ${params.fileName}`);
    console.log(`Total registros exportados: ${currentData.length}`);
}
