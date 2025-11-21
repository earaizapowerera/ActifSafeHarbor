// Cálculo RMF JavaScript

async function initCalculo() {
    console.log('[initCalculo] Inicializando página de cálculo...');

    inicializarAños();
    cargarHistorial();

    // Event listener para cambio de año
    const añoSelect = document.getElementById('anioCalculo');
    if (añoSelect) {
        añoSelect.addEventListener('change', function() {
            const año = this.value;
            if (año) {
                cargarCompaniasPorAño(año);
            } else {
                document.getElementById('companiasChecklist').innerHTML = '<div class="text-center text-muted">Seleccione primero un año</div>';
            }
        });
    }

    // Event listeners
    const form = document.getElementById('formCalculo');
    if (form) {
        form.addEventListener('submit', ejecutarCalculo);
    }

    // Event listeners para botones de selección
    const btnSeleccionarTodas = document.getElementById('btnSeleccionarTodas');
    const btnDeseleccionarTodas = document.getElementById('btnDeseleccionarTodas');

    if (btnSeleccionarTodas) {
        btnSeleccionarTodas.addEventListener('click', () => {
            const checkboxes = document.querySelectorAll('#companiasChecklist input[type="checkbox"]');
            checkboxes.forEach(cb => cb.checked = true);
        });
    }

    if (btnDeseleccionarTodas) {
        btnDeseleccionarTodas.addEventListener('click', () => {
            const checkboxes = document.querySelectorAll('#companiasChecklist input[type="checkbox"]');
            checkboxes.forEach(cb => cb.checked = false);
        });
    }
}

// Ejecutar inmediatamente si DOM ya está listo, o esperar al evento
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCalculo);
} else {
    initCalculo();
}

function inicializarAños() {
    const añoSelect = document.getElementById('anioCalculo');
    const añoActual = new Date().getFullYear();

    añoSelect.innerHTML = '<option value="">Seleccionar año...</option>';
    for (let año = añoActual; año >= añoActual - 10; año--) {
        añoSelect.innerHTML += `<option value="${año}">${año}</option>`;
    }
}

async function cargarCompaniasPorAño(año) {
    try {
        const checklist = document.getElementById('companiasChecklist');
        checklist.innerHTML = '<div class="text-center text-muted"><i class="fas fa-spinner fa-spin"></i> Cargando compañías...</div>';

        const response = await fetch(`/api/calculo/companias-con-datos?año=${año}&v=${Date.now()}`);
        if (!response.ok) throw new Error('Error al cargar compañías');

        const companias = await response.json();

        if (companias.length === 0) {
            checklist.innerHTML = '<div class="alert alert-warning">No hay compañías con datos importados para este año</div>';
            return;
        }

        checklist.innerHTML = companias.map(c => `
            <div class="form-check">
                <input class="form-check-input" type="checkbox" value="${c.idCompania}" id="comp${c.idCompania}" data-nombre="${c.nombreCompania}" style="cursor: pointer;">
                <label class="form-check-label" for="comp${c.idCompania}" style="cursor: pointer;">
                    ${c.nombreCompania} <span class="badge bg-success">${c.totalRegistros || 0} registros</span>
                </label>
            </div>
        `).join('');

        console.log(`✓ Cargadas ${companias.length} compañías con datos importados para ${año}`);

    } catch (error) {
        console.error('Error:', error);

        // Detectar errores de conexión, timeout o red
        let mensajeError = 'Error al cargar compañías';
        if (error.name === 'TypeError' || error.message.includes('fetch') || error.message.includes('NetworkError')) {
            mensajeError = 'No se pudo conectar a la base de datos';
        }

        document.getElementById('companiasChecklist').innerHTML = `<div class="text-danger">${mensajeError}</div>`;
    }
}


let progressInterval = null;

async function ejecutarCalculo(event) {
    event.preventDefault();

    const btnEjecutar = document.getElementById('btnEjecutar');
    const añoCalculo = parseInt(document.getElementById('anioCalculo').value);
    const usuario = document.getElementById('usuario').value;

    // Get selected companies from checkboxes
    const checkboxes = document.querySelectorAll('#companiasChecklist input[type="checkbox"]:checked');

    if (checkboxes.length === 0) {
        alert('Debe seleccionar al menos una compañía');
        return;
    }

    const companias = Array.from(checkboxes).map(cb => ({
        id: parseInt(cb.value),
        nombre: cb.getAttribute('data-nombre')
    }));

    // Mostrar confirmación
    const confirmacion = confirm(`Se calcularán ${companias.length} compañía(s) en secuencia:\n\n${companias.map(c => `  • ${c.nombre}`).join('\n')}\n\n¿Desea continuar?`);

    if (!confirmacion) {
        return;
    }

    // Disable button and show loading
    btnEjecutar.disabled = true;
    btnEjecutar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Calculando...';

    // Hide previous results
    document.getElementById('resultadoDiv').style.display = 'none';

    // Show progress bar
    mostrarBarraProgreso();

    const resultados = [];
    let todasExitosas = true;

    try {
        // Procesar cada compañía en secuencia
        for (let i = 0; i < companias.length; i++) {
            const compania = companias[i];
            console.log(`[${i+1}/${companias.length}] Calculando ${compania.nombre}...`);

            btnEjecutar.innerHTML = `<i class="fas fa-spinner fa-spin"></i> [${i+1}/${companias.length}] ${compania.nombre}...`;

            const data = {
                idCompania: compania.id,
                añoCalculo: añoCalculo,
                usuario: usuario
            };

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

                console.log(`  ✓ Cálculo iniciado con lote: ${result.loteCalculo}`);

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

                resultados.push({
                    compania: compania.nombre,
                    exitoso: true,
                    resultado: finalResult
                });

                console.log(`  ✓ ${compania.nombre} completado exitosamente`);

            } catch (error) {
                console.error(`  ✗ Error en ${compania.nombre}:`, error);
                resultados.push({
                    compania: compania.nombre,
                    exitoso: false,
                    error: error.message
                });
                todasExitosas = false;
            }
        }

        // Stop progress monitoring (por si acaso)
        if (progressInterval) {
            clearInterval(progressInterval);
            progressInterval = null;
        }

        // Hide progress bar
        ocultarBarraProgreso();

        // Show combined results
        mostrarResultadosMultiples(resultados, todasExitosas);

        // Reload history
        cargarHistorial();

    } catch (error) {
        console.error('Error general:', error);

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
                    <td><strong>$${(result.totalValorReportable || 0).toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})} MXN</strong></td>
                </tr>
                <tr>
                    <th>Activos con 10% MOI:</th>
                    <td><strong>${result.activosCon10PctMOI || 0}</strong></td>
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
        progressText.textContent = `Completado: ${progreso.registrosCalculados || 0} registros`;
        progressDetails.textContent = `Valor Reportable: $${(progreso.totalValorReportable || 0).toLocaleString('es-MX', {minimumFractionDigits: 2})} MXN | Activos con 10% MOI: ${progreso.activosCon10PctMOI || 0}`;
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
                    <th>Lote Cálculo:</th>
                    <td><code>${progreso.loteCalculo}</code></td>
                </tr>
                <tr>
                    <th>Registros Calculados:</th>
                    <td><strong>${progreso.registrosCalculados || 0}</strong></td>
                </tr>
                <tr>
                    <th>Total Valor Reportable:</th>
                    <td><strong>$${(progreso.totalValorReportable || 0).toLocaleString('es-MX', {minimumFractionDigits: 2, maximumFractionDigits: 2})} MXN</strong></td>
                </tr>
                <tr>
                    <th>Activos con 10% MOI:</th>
                    <td><strong>${progreso.activosCon10PctMOI || 0}</strong></td>
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

// Mostrar resultados múltiples consolidados
function mostrarResultadosMultiples(resultados, todasExitosas) {
    const resultadoDiv = document.getElementById('resultadoDiv');
    const resultadoCard = document.getElementById('resultadoCard');
    const resultadoContent = document.getElementById('resultadoContent');

    if (todasExitosas) {
        resultadoCard.classList.remove('border-danger');
        resultadoCard.classList.add('border-success');
        resultadoCard.querySelector('.card-header').classList.remove('bg-danger');
        resultadoCard.querySelector('.card-header').classList.add('bg-success', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-check-circle"></i> Cálculos Múltiples - Todos exitosos';
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-warning');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-warning', 'text-dark');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-triangle"></i> Cálculos Múltiples - Con errores';
    }

    const exitosas = resultados.filter(r => r.exitoso).length;
    const fallidas = resultados.length - exitosas;
    const totalRegistros = resultados.filter(r => r.exitoso).reduce((sum, r) => sum + (r.resultado?.registrosCalculados || 0), 0);

    let html = `
        <div class="alert ${todasExitosas ? 'alert-success' : 'alert-warning'}">
            <h5><i class="fas ${todasExitosas ? 'fa-check-circle' : 'fa-exclamation-triangle'}"></i> Proceso completado</h5>
            <p><strong>${exitosas}</strong> de <strong>${resultados.length}</strong> compañías procesadas exitosamente</p>
            ${fallidas > 0 ? `<p class="text-danger"><strong>${fallidas}</strong> compañías con errores</p>` : ''}
            <p><strong>Total registros calculados:</strong> ${totalRegistros}</p>
        </div>
        <h6>Detalle por compañía:</h6>
        <table class="table table-sm table-striped">
            <thead class="table-dark">
                <tr>
                    <th>Compañía</th>
                    <th>Estado</th>
                    <th>Registros</th>
                    <th>Duración</th>
                    <th>Lote Cálculo</th>
                </tr>
            </thead>
            <tbody>
    `;

    for (const resultado of resultados) {
        if (resultado.exitoso) {
            const progreso = resultado.resultado;
            const duracionSegundos = progreso.fechaFin ?
                Math.round((new Date(progreso.fechaFin) - new Date(progreso.fechaInicio)) / 1000) : 0;

            html += `
                <tr class="table-success">
                    <td><strong>${resultado.compania}</strong></td>
                    <td><span class="badge bg-success">${progreso.estado}</span></td>
                    <td>${progreso.registrosCalculados || 0}</td>
                    <td>${duracionSegundos}s</td>
                    <td><small><code>${progreso.loteCalculo ? progreso.loteCalculo.substring(0, 8) + '...' : 'N/A'}</code></small></td>
                </tr>
            `;
        } else {
            html += `
                <tr class="table-danger">
                    <td><strong>${resultado.compania}</strong></td>
                    <td><span class="badge bg-danger">Error</span></td>
                    <td colspan="3"><small class="text-danger">${resultado.error}</small></td>
                </tr>
            `;
        }
    }

    html += `
            </tbody>
        </table>
        <div class="mt-3">
            <a href="/reporte.html" class="btn btn-primary">
                <i class="fas fa-file-alt"></i> Ver Reporte RMF
            </a>
        </div>
    `;

    resultadoContent.innerHTML = html;
    resultadoDiv.style.display = 'block';
    resultadoDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });

    // Recargar el historial para mostrar los nuevos cálculos
    cargarHistorial();
}
