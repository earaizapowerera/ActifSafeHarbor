// Cálculo RMF JavaScript

document.addEventListener('DOMContentLoaded', async function() {
    cargarCompanias();
    cargarHistorial();

    // Event listeners
    document.getElementById('formCalculo').addEventListener('submit', ejecutarCalculo);

    // Watch for company/year changes to load available lotes
    document.getElementById('companiaSelect').addEventListener('change', cargarLotesDisponibles);
    document.getElementById('anioCalculo').addEventListener('change', cargarLotesDisponibles);
});

async function cargarCompanias() {
    try {
        const response = await fetch('/api/companias');
        if (!response.ok) throw new Error('Error al cargar compañías');

        const companias = await response.json();
        const select = document.getElementById('companiaSelect');

        // Filter only active companies
        const activas = companias.filter(c => c.activo);

        if (activas.length === 0) {
            select.innerHTML = '<option value="">No hay compañías activas</option>';
            return;
        }

        select.innerHTML = '<option value="">Seleccione una compañía...</option>' +
            activas.map(c => `<option value="${c.idCompania}">${c.nombreCompania}</option>`).join('');

    } catch (error) {
        console.error('Error:', error);
        document.getElementById('companiaSelect').innerHTML = '<option value="">Error al cargar</option>';
    }
}

async function cargarLotesDisponibles() {
    const companiaSelect = document.getElementById('companiaSelect');
    const anioCalculo = document.getElementById('anioCalculo');
    const loteSelect = document.getElementById('loteSelect');

    const idCompania = parseInt(companiaSelect.value);
    const año = parseInt(anioCalculo.value);

    if (!idCompania || !año) {
        loteSelect.disabled = true;
        loteSelect.innerHTML = '<option value="">Seleccione compañía y año primero...</option>';
        return;
    }

    loteSelect.disabled = true;
    loteSelect.innerHTML = '<option value="">Cargando lotes disponibles...</option>';

    try {
        const response = await fetch(`/api/calculo/lotes-disponibles/${idCompania}/${año}`);

        if (!response.ok) throw new Error('Error al cargar lotes');

        const lotes = await response.json();

        if (lotes.length === 0) {
            loteSelect.innerHTML = '<option value="">No hay lotes ETL disponibles para esta compañía/año</option>';
            return;
        }

        loteSelect.disabled = false;
        loteSelect.innerHTML = '<option value="">Seleccione un lote ETL...</option>' +
            lotes.map(l => {
                const fecha = new Date(l.fechaImportacion).toLocaleString('es-MX');
                const loteCorto = l.loteImportacion.substring(0, 8);
                return `<option value="${l.loteImportacion}">${fecha} - ${l.totalRegistros} registros (${loteCorto}...)</option>`;
            }).join('');

    } catch (error) {
        console.error('Error:', error);
        loteSelect.innerHTML = '<option value="">Error al cargar lotes</option>';
    }
}

let progressInterval = null;

async function ejecutarCalculo(event) {
    event.preventDefault();

    const btnEjecutar = document.getElementById('btnEjecutar');
    const idCompania = parseInt(document.getElementById('companiaSelect').value);
    const añoCalculo = parseInt(document.getElementById('anioCalculo').value);
    const loteImportacion = document.getElementById('loteSelect').value;
    const usuario = document.getElementById('usuario').value;

    if (!idCompania) {
        alert('Debe seleccionar una compañía');
        return;
    }

    if (!loteImportacion) {
        alert('Debe seleccionar un lote ETL');
        return;
    }

    const data = {
        idCompania: idCompania,
        añoCalculo: añoCalculo,
        loteImportacion: loteImportacion,
        usuario: usuario
    };

    // Disable button and show loading
    btnEjecutar.disabled = true;
    btnEjecutar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Ejecutando...';

    // Hide previous results
    document.getElementById('resultadoDiv').style.display = 'none';

    // Show progress bar
    mostrarBarraProgreso();

    try {
        const response = await fetch('/api/calculo/ejecutar', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (!response.ok) {
            throw new Error(result.detail || result.message || 'Error desconocido');
        }

        // Cálculo started - begin monitoring progress
        iniciarMonitoreoProgreso(result.loteCalculo);

        // Wait for completion by polling
        await esperarCompletado(result.loteCalculo);

        // Stop progress monitoring
        if (progressInterval) {
            clearInterval(progressInterval);
            progressInterval = null;
        }

        // Get final result
        const finalProgreso = await fetch(`/api/calculo/progreso/${result.loteCalculo}`);
        const finalResult = await finalProgreso.json();

        // Hide progress bar
        ocultarBarraProgreso();

        // Show success result
        mostrarResultadoFinal(finalResult, result);

        // Reload history
        cargarHistorial();

    } catch (error) {
        console.error('Error:', error);

        // Stop progress monitoring
        if (progressInterval) {
            clearInterval(progressInterval);
            progressInterval = null;
        }

        // Hide progress bar
        ocultarBarraProgreso();

        mostrarResultado({ message: error.message }, false);
    } finally {
        // Re-enable button
        btnEjecutar.disabled = false;
        btnEjecutar.innerHTML = '<i class="fas fa-play"></i> Ejecutar Cálculo';
    }
}

function mostrarResultado(result, success) {
    const resultadoDiv = document.getElementById('resultadoDiv');
    const resultadoCard = document.getElementById('resultadoCard');
    const resultadoContent = document.getElementById('resultadoContent');

    if (success) {
        resultadoCard.classList.remove('border-danger');
        resultadoCard.classList.add('border-success');
        resultadoCard.querySelector('.card-header').classList.remove('bg-danger');
        resultadoCard.querySelector('.card-header').classList.add('bg-success', 'text-white');

        resultadoContent.innerHTML = `
            <div class="alert alert-success">
                <h5><i class="fas fa-check-circle"></i> ${result.message}</h5>
            </div>
            <table class="table table-bordered">
                <tr>
                    <th>ID Compañía:</th>
                    <td>${result.idCompania}</td>
                </tr>
                <tr>
                    <th>Año Cálculo:</th>
                    <td>${result.añoCalculo}</td>
                </tr>
                <tr>
                    <th>Lote Cálculo:</th>
                    <td><code>${result.loteCalculo}</code></td>
                </tr>
                <tr>
                    <th>Registros Calculados:</th>
                    <td><strong>${result.registrosCalculados}</strong></td>
                </tr>
                <tr>
                    <th>Total Valor Reportable:</th>
                    <td><strong>$${result.totalValorReportable.toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})} MXN</strong></td>
                </tr>
                <tr>
                    <th>Activos con 10% MOI:</th>
                    <td><strong>${result.activosCon10PctMOI}</strong></td>
                </tr>
            </table>
            <div class="mt-3">
                <a href="/reporte.html" class="btn btn-primary">
                    <i class="fas fa-file-excel"></i> Ver Reporte
                </a>
            </div>
        `;
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-danger');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-danger', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-circle"></i> Error en el Cálculo';

        resultadoContent.innerHTML = `
            <div class="alert alert-danger">
                <h5><i class="fas fa-exclamation-circle"></i> Error</h5>
                <p>${result.message}</p>
            </div>
        `;
    }

    resultadoDiv.style.display = 'block';
    resultadoDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

async function cargarHistorial() {
    try {
        const tbody = document.getElementById('tbodyHistorial');
        tbody.innerHTML = '<tr><td colspan="7" class="text-center">Cargando historial...</td></tr>';

        const response = await fetch('/api/calculo/historial');

        if (!response.ok) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Error al cargar historial</td></tr>';
            return;
        }

        const historial = await response.json();

        if (historial.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">No hay cálculos registrados</td></tr>';
            return;
        }

        // Render history rows
        tbody.innerHTML = historial.map(h => {
            const fechaInicio = new Date(h.fechaInicio).toLocaleString('es-MX');
            const duracion = h.duracionSegundos ? `${h.duracionSegundos}s` : '-';
            const registros = h.registrosProcesados || '-';

            let estadoBadge = '';
            if (h.estado === 'Completado') {
                estadoBadge = '<span class="badge bg-success">Completado</span>';
            } else if (h.estado === 'Error') {
                estadoBadge = '<span class="badge bg-danger">Error</span>';
            } else {
                estadoBadge = '<span class="badge bg-warning">En Proceso</span>';
            }

            return `
                <tr>
                    <td>${fechaInicio}</td>
                    <td>${h.nombreCompania}</td>
                    <td>${h.añoCalculo}</td>
                    <td><small><code>${h.loteCalculo.substring(0, 8)}...</code></small></td>
                    <td>${registros}</td>
                    <td>${duracion}</td>
                    <td>${estadoBadge}</td>
                </tr>
            `;
        }).join('');

    } catch (error) {
        console.error('Error:', error);
        const tbody = document.getElementById('tbodyHistorial');
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Error al cargar historial</td></tr>';
    }
}

function mostrarBarraProgreso() {
    let progressDiv = document.getElementById('progressDiv');

    if (!progressDiv) {
        // Create progress div if it doesn't exist
        const formCard = document.querySelector('.card-body');
        progressDiv = document.createElement('div');
        progressDiv.id = 'progressDiv';
        progressDiv.className = 'mt-4';
        progressDiv.style.display = 'none';
        progressDiv.innerHTML = `
            <div class="alert alert-info">
                <h6><i class="fas fa-spinner fa-spin"></i> Progreso del Cálculo</h6>
                <div class="progress mt-2" style="height: 25px;">
                    <div id="progressBar" class="progress-bar progress-bar-striped progress-bar-animated bg-success" role="progressbar" style="width: 0%">
                        <span id="progressText">Iniciando...</span>
                    </div>
                </div>
                <small id="progressDetails" class="text-muted mt-2 d-block"></small>
            </div>
        `;
        formCard.appendChild(progressDiv);
    }

    progressDiv.style.display = 'block';
    document.getElementById('progressBar').style.width = '0%';
    document.getElementById('progressText').textContent = 'Iniciando...';
    document.getElementById('progressDetails').textContent = '';
}

function ocultarBarraProgreso() {
    const progressDiv = document.getElementById('progressDiv');
    if (progressDiv) {
        progressDiv.style.display = 'none';
    }
}

function iniciarMonitoreoProgreso(loteCalculo) {
    // Poll every 10 seconds
    progressInterval = setInterval(async () => {
        try {
            const response = await fetch(`/api/calculo/progreso/${loteCalculo}`);

            if (response.ok) {
                const progreso = await response.json();
                actualizarBarraProgreso(progreso);

                // Stop polling if completed or error
                if (progreso.estado === 'Completado' || progreso.estado.startsWith('Error')) {
                    clearInterval(progressInterval);
                    progressInterval = null;
                }
            }
        } catch (error) {
            console.error('Error obteniendo progreso:', error);
        }
    }, 10000); // 10 seconds
}

function actualizarBarraProgreso(progreso) {
    const progressBar = document.getElementById('progressBar');
    const progressText = document.getElementById('progressText');
    const progressDetails = document.getElementById('progressDetails');

    if (progreso.estado === 'Completado') {
        progressBar.style.width = '100%';
        progressBar.classList.remove('progress-bar-animated');
        progressBar.classList.add('bg-success');
        progressText.textContent = `Completado: ${progreso.registrosCalculados} registros`;
        progressDetails.textContent = `Valor Reportable: $${progreso.totalValorReportable.toLocaleString('es-MX', {minimumFractionDigits: 2})} MXN | Activos con 10% MOI: ${progreso.activosCon10PctMOI}`;
    } else if (progreso.estado.startsWith('Error')) {
        progressBar.classList.remove('progress-bar-animated');
        progressBar.classList.add('bg-danger');
        progressText.textContent = 'Error';
        progressDetails.textContent = progreso.estado;
    } else {
        // Show indeterminate progress (since we don't know total)
        progressBar.style.width = '100%';
        progressText.textContent = progreso.estado || 'Calculando...';

        if (progreso.registrosCalculados > 0) {
            progressDetails.textContent = `Registros procesados: ${progreso.registrosCalculados}`;
        } else {
            progressDetails.textContent = 'Ejecutando cálculo...';
        }
    }
}

async function esperarCompletado(loteCalculo) {
    return new Promise((resolve, reject) => {
        const checkInterval = setInterval(async () => {
            try {
                const response = await fetch(`/api/calculo/progreso/${loteCalculo}`);
                if (response.ok) {
                    const progreso = await response.json();
                    if (progreso.estado === 'Completado' || progreso.estado.startsWith('Error')) {
                        clearInterval(checkInterval);
                        resolve(progreso);
                    }
                }
            } catch (error) {
                clearInterval(checkInterval);
                reject(error);
            }
        }, 5000); // Check every 5 seconds for completion
    });
}

function mostrarResultadoFinal(progreso, initialResult) {
    const resultadoDiv = document.getElementById('resultadoDiv');
    const resultadoCard = document.getElementById('resultadoCard');
    const resultadoContent = document.getElementById('resultadoContent');

    if (progreso.estado === 'Completado') {
        resultadoCard.classList.remove('border-danger');
        resultadoCard.classList.add('border-success');
        resultadoCard.querySelector('.card-header').classList.remove('bg-danger');
        resultadoCard.querySelector('.card-header').classList.add('bg-success', 'text-white');

        const duracionSegundos = progreso.fechaFin ?
            Math.round((new Date(progreso.fechaFin) - new Date(progreso.fechaInicio)) / 1000) : 0;

        resultadoContent.innerHTML = `
            <div class="alert alert-success">
                <h5><i class="fas fa-check-circle"></i> Cálculo ejecutado exitosamente</h5>
            </div>
            <table class="table table-bordered">
                <tr>
                    <th>ID Compañía:</th>
                    <td>${initialResult.idCompania}</td>
                </tr>
                <tr>
                    <th>Año Cálculo:</th>
                    <td>${initialResult.añoCalculo}</td>
                </tr>
                <tr>
                    <th>Lote Importación (ETL):</th>
                    <td><small><code>${initialResult.loteImportacion}</code></small></td>
                </tr>
                <tr>
                    <th>Lote Cálculo:</th>
                    <td><code>${progreso.loteCalculo}</code></td>
                </tr>
                <tr>
                    <th>Registros Calculados:</th>
                    <td><strong>${progreso.registrosCalculados}</strong></td>
                </tr>
                <tr>
                    <th>Total Valor Reportable:</th>
                    <td><strong>$${progreso.totalValorReportable.toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})} MXN</strong></td>
                </tr>
                <tr>
                    <th>Activos con 10% MOI:</th>
                    <td><strong>${progreso.activosCon10PctMOI}</strong></td>
                </tr>
                <tr>
                    <th>Duración:</th>
                    <td>${duracionSegundos} segundos</td>
                </tr>
                <tr>
                    <th>Estado:</th>
                    <td><span class="badge bg-success">${progreso.estado}</span></td>
                </tr>
            </table>
            <div class="mt-3">
                <a href="/reporte.html" class="btn btn-primary">
                    <i class="fas fa-file-excel"></i> Ver Reporte
                </a>
            </div>
        `;
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-danger');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-danger', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-circle"></i> Error en el Cálculo';

        resultadoContent.innerHTML = `
            <div class="alert alert-danger">
                <h5><i class="fas fa-exclamation-circle"></i> Error</h5>
                <p>${progreso.estado}</p>
            </div>
        `;
    }

    resultadoDiv.style.display = 'block';
    resultadoDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}
