// Dashboard JavaScript
document.addEventListener('DOMContentLoaded', function() {
    inicializarAños();
    document.getElementById('btnRefresh').addEventListener('click', cargarDashboard);
    document.getElementById('añoSelect').addEventListener('change', cargarDashboard);
});

function inicializarAños() {
    const añoSelect = document.getElementById('añoSelect');
    const añoActual = new Date().getFullYear();

    añoSelect.innerHTML = '';
    for (let año = añoActual; año >= añoActual - 5; año--) {
        añoSelect.innerHTML += `<option value="${año}" ${año === añoActual ? 'selected' : ''}>${año}</option>`;
    }

    // Cargar dashboard automáticamente con año actual
    cargarDashboard();
}

async function cargarDashboard() {
    const año = document.getElementById('añoSelect').value;
    if (!año) return;

    const container = document.getElementById('companiesContainer');
    container.innerHTML = '<div class="col-12 text-center"><div class="spinner-border" role="status"><span class="visually-hidden">Cargando...</span></div></div>';

    try {
        const response = await fetch(`/api/dashboard/${año}`);
        if (!response.ok) throw new Error('Error al cargar dashboard');

        const companias = await response.json();

        if (companias.length === 0) {
            container.innerHTML = '<div class="col-12"><div class="alert alert-warning">No hay compañías configuradas</div></div>';
            return;
        }

        container.innerHTML = '';
        companias.forEach(c => {
            const card = crearCardCompania(c, año);
            container.innerHTML += card;
        });

    } catch (error) {
        console.error('Error:', error);
        container.innerHTML = `<div class="col-12"><div class="alert alert-danger">Error al cargar dashboard: ${error.message}</div></div>`;
    }
}

function crearCardCompania(compania, año) {
    const estadoClass = compania.estado === 'Completado' ? 'completado' : 'pendiente';
    const indicatorClass = `status-${estadoClass}`;
    const headerClass = `card-header-${estadoClass}`;

    const fechaETL = compania.fechaETL ? new Date(compania.fechaETL).toLocaleDateString('es-MX') : 'N/A';
    const fechaCalculo = compania.fechaCalculo ? new Date(compania.fechaCalculo).toLocaleDateString('es-MX') : 'N/A';

    return `
        <div class="col-md-6 col-lg-4 mb-4">
            <div class="card status-card h-100">
                <div class="card-header ${headerClass}">
                    <h5>
                        <span class="status-indicator ${indicatorClass}"></span>
                        ${compania.nombreCorto}
                    </h5>
                </div>
                <div class="card-body">
                    <h6 class="card-subtitle mb-3 text-muted">${compania.nombreCompania}</h6>

                    <div class="mb-3">
                        <strong>Estado:</strong>
                        <span class="badge bg-${compania.estado === 'Completado' ? 'success' : 'danger'}">
                            ${compania.estado}
                        </span>
                    </div>

                    <hr>

                    <div class="row text-center mb-2">
                        <div class="col-6">
                            <small class="text-muted">Registros ETL</small>
                            <h4 class="text-primary">${compania.totalRegistrosETL.toLocaleString()}</h4>
                            <small>${fechaETL}</small>
                        </div>
                        <div class="col-6">
                            <small class="text-muted">Registros Cálculo</small>
                            <h4 class="text-success">${compania.totalRegistrosCalculo.toLocaleString()}</h4>
                            <small>${fechaCalculo}</small>
                        </div>
                    </div>

                    ${compania.estado === 'Completado' ? `
                    <hr>
                    <div class="table-responsive">
                        <table class="table table-sm">
                            <tr>
                                <td><small>Total MOI:</small></td>
                                <td class="text-end"><strong>$${compania.totalMOI.toLocaleString('en-US', {minimumFractionDigits: 2})}</strong></td>
                            </tr>
                            <tr>
                                <td><small>Saldo Pendiente:</small></td>
                                <td class="text-end"><strong>$${compania.totalSaldoPendiente.toLocaleString('en-US', {minimumFractionDigits: 2})}</strong></td>
                            </tr>
                            <tr>
                                <td><small>Valor Reportable:</small></td>
                                <td class="text-end"><strong class="text-success">$${compania.totalValorReportable.toLocaleString('en-US', {minimumFractionDigits: 2})}</strong></td>
                            </tr>
                            <tr>
                                <td><small>Activos con 10% MOI:</small></td>
                                <td class="text-end"><strong>${compania.activosCon10Pct}</strong></td>
                            </tr>
                        </table>
                    </div>
                    ` : ''}
                </div>
                <div class="card-footer">
                    <div class="d-grid gap-2">
                        ${compania.estado === 'Pendiente' ? `
                            <a href="/extraccion.html?compania=${compania.idCompania}&año=${año}" class="btn btn-sm btn-warning">
                                <i class="fas fa-download"></i> Ejecutar ETL
                            </a>
                        ` : `
                            <a href="/reporte.html?compania=${compania.idCompania}&año=${año}" class="btn btn-sm btn-primary">
                                <i class="fas fa-file-excel"></i> Ver Reporte
                            </a>
                        `}
                    </div>
                </div>
            </div>
        </div>
    `;
}
