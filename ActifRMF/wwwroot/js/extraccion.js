// Extracción ETL JavaScript

async function initExtraccion() {
    console.log('[initExtraccion] Inicializando página de extracción...');

    // Limpiar registros huérfanos al cargar la página
    try {
        await fetch('/api/etl/limpiar-huerfanos', { method: 'POST' });
    } catch (error) {
        console.error('Error limpiando huérfanos:', error);
    }

    cargarCompanias();
    cargarHistorial();

    const form = document.getElementById('formExtraccion');
    if (form) {
        form.addEventListener('submit', ejecutarETL);
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
    document.addEventListener('DOMContentLoaded', initExtraccion);
} else {
    initExtraccion();
}

async function cargarCompanias() {
    try {
        const response = await fetch('/api/companias');
        if (!response.ok) throw new Error('Error al cargar compañías');

        const companias = await response.json();
        const checklist = document.getElementById('companiasChecklist');

        // Filter only active companies
        const activas = companias.filter(c => c.activo);

        if (activas.length === 0) {
            checklist.innerHTML = '<div class="text-center text-muted">No hay compañías activas</div>';
            return;
        }

        checklist.innerHTML = activas.map(c => `
            <div class="form-check">
                <input class="form-check-input" type="checkbox" value="${c.idCompania}" id="comp${c.idCompania}" data-nombre="${c.nombreCompania}" style="cursor: pointer;">
                <label class="form-check-label" for="comp${c.idCompania}" style="cursor: pointer;">
                    ${c.nombreCompania} <small class="text-muted">(${c.nombreCorto})</small>
                </label>
            </div>
        `).join('');

        console.log(`✓ Cargadas ${activas.length} compañías con checkboxes habilitados`);

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
let pollCount = 0;

async function ejecutarETL(event) {
    event.preventDefault();

    const btnEjecutar = document.getElementById('btnEjecutar');
    const añoCalculo = parseInt(document.getElementById('anioCalculo').value);
    const usuario = document.getElementById('usuario').value;
    const maxRegistrosInput = document.getElementById('maxRegistros').value;
    const maxRegistros = maxRegistrosInput ? parseInt(maxRegistrosInput) : null;

    // Get selected companies
    const checkboxes = document.querySelectorAll('#companiasChecklist input[type="checkbox"]:checked');

    if (checkboxes.length === 0) {
        alert('Debe seleccionar al menos una compañía');
        return;
    }

    const companias = Array.from(checkboxes).map(cb => ({
        id: parseInt(cb.value),
        nombre: cb.getAttribute('data-nombre')
    }));

    // Mostrar plan de ejecución
    const plan = `
        <h6>Plan de Ejecución:</h6>
        <ul>
            ${companias.map(c => `<li>${c.nombre} (ID: ${c.id})</li>`).join('')}
        </ul>
        <p><strong>Año:</strong> ${añoCalculo}</p>
        <p><strong>Total:</strong> ${companias.length} compañía(s)</p>
        ${maxRegistros ? `<p class="text-warning"><strong>⚠️ Modo TEST:</strong> Límite de ${maxRegistros} registros</p>` : ''}
    `;

    const confirmacion = confirm(`Se procesarán ${companias.length} compañía(s) en secuencia:\n\n${companias.map(c => `  • ${c.nombre}`).join('\n')}\n\n¿Desea continuar?`);

    if (!confirmacion) {
        return;
    }

    // Disable button and show loading
    btnEjecutar.disabled = true;
    btnEjecutar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Ejecutando...';

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
            console.log(`[${i+1}/${companias.length}] Procesando ${compania.nombre}...`);

            btnEjecutar.innerHTML = `<i class="fas fa-spinner fa-spin"></i> [${i+1}/${companias.length}] ${compania.nombre}...`;

            const data = {
                idCompania: compania.id,
                añoCalculo: añoCalculo,
                usuario: usuario,
                maxRegistros: maxRegistros
            };

            try {
                const response = await fetch('/api/etl/ejecutar', {
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

                // Verificar que tenemos un lote válido
                if (!result.loteImportacion) {
                    throw new Error('No se recibió un lote de importación válido del servidor');
                }

                console.log(`  ✓ ETL iniciado con lote: ${result.loteImportacion}`);

                // ETL started - begin monitoring progress
                iniciarMonitoreoProgreso(result.loteImportacion);

                // Wait for completion by polling
                await esperarCompletado(result.loteImportacion);

                // Stop progress monitoring
                if (progressInterval) {
                    clearInterval(progressInterval);
                    progressInterval = null;
                }

                // Get final result
                const finalProgreso = await fetch(`/api/etl/progreso/${result.loteImportacion}`);
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
        btnEjecutar.innerHTML = '<i class="fas fa-play"></i> Ejecutar ETL';
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
                    <th>Lote Importación:</th>
                    <td><code>${result.loteImportacion}</code></td>
                </tr>
                <tr>
                    <th>Registros Importados:</th>
                    <td><strong>${result.registrosImportados}</strong></td>
                </tr>
                <tr>
                    <th>Duración:</th>
                    <td>${result.duracionSegundos} segundos</td>
                </tr>
                <tr>
                    <th>Estado:</th>
                    <td><span class="badge bg-success">${result.estado}</span></td>
                </tr>
            </table>
            <div class="mt-3">
                <a href="/calculo.html" class="btn btn-primary">
                    <i class="fas fa-calculator"></i> Ir a Cálculo
                </a>
            </div>
        `;
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-danger');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-danger', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-circle"></i> Error en la Extracción';

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

        const response = await fetch('/api/etl/historial');

        if (!response.ok) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Error al cargar historial</td></tr>';
            return;
        }

        const historial = await response.json();

        if (historial.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">No hay extracciones registradas</td></tr>';
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
                    <td><small><code>${h.loteImportacion.substring(0, 8)}...</code></small></td>
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
                <h6><i class="fas fa-spinner fa-spin"></i> Progreso de Extracción</h6>
                <div class="progress mt-2" style="height: 25px;">
                    <div id="progressBar" class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width: 0%">
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

function iniciarMonitoreoProgreso(loteImportacion) {
    pollCount = 0;
    // Poll every 5 seconds (reducido de 10)
    progressInterval = setInterval(async () => {
        pollCount++;
        try {
            console.log(`[Poll #${pollCount}] Consultando progreso para lote: ${loteImportacion}`);
            const response = await fetch(`/api/etl/progreso/${loteImportacion}?nocache=${Date.now()}`);

            console.log(`[Poll #${pollCount}] Response status: ${response.status}`);

            if (response.ok) {
                const progreso = await response.json();
                console.log(`[Poll #${pollCount}] Progreso:`, progreso);
                actualizarBarraProgreso(progreso);

                // Stop polling if completed or error
                if (progreso.estado === 'Completado' || progreso.estado.startsWith('Error')) {
                    console.log(`[Poll #${pollCount}] ETL finalizado, deteniendo polling`);
                    clearInterval(progressInterval);
                    progressInterval = null;
                }
            } else {
                console.error(`[Poll #${pollCount}] Error HTTP: ${response.status}`);
            }
        } catch (error) {
            console.error(`[Poll #${pollCount}] Error obteniendo progreso:`, error);
        }
    }, 5000); // 5 seconds
}

function actualizarBarraProgreso(progreso) {
    const progressBar = document.getElementById('progressBar');
    const progressText = document.getElementById('progressText');
    const progressDetails = document.getElementById('progressDetails');

    // Si no tenemos el total aún, ocultar la barra y mostrar mensaje de espera
    if (progreso.totalRegistros === 0 && progreso.estado === 'En Proceso') {
        progressBar.style.width = '0%';
        progressText.textContent = 'Extrayendo datos...';
        progressDetails.textContent = `Estado: ${progreso.estado} | Consultas: ${pollCount}`;
        return;
    }

    if (progreso.estado === 'Completado') {
        progressBar.style.width = '100%';
        progressBar.classList.remove('progress-bar-animated');
        progressBar.classList.add('bg-success');
        progressText.textContent = `Completado: ${progreso.registrosInsertados} de ${progreso.totalRegistros} registros`;
    } else if (progreso.estado.startsWith('Error')) {
        progressBar.classList.remove('progress-bar-animated');
        progressBar.classList.add('bg-danger');
        progressText.textContent = 'Error';
    } else {
        // Calculate percentage
        const porcentaje = progreso.totalRegistros > 0
            ? Math.round((progreso.registrosInsertados / progreso.totalRegistros) * 100)
            : 0;

        progressBar.style.width = `${porcentaje}%`;
        progressText.textContent = `${progreso.registrosInsertados} de ${progreso.totalRegistros} registros (${porcentaje}%)`;
    }

    progressDetails.textContent = `Estado: ${progreso.estado} | Consultas: ${pollCount}`;
}

async function esperarCompletado(loteImportacion) {
    return new Promise((resolve, reject) => {
        let checkCount = 0;
        const maxChecks = 120; // 120 * 5 seg = 10 minutos máximo

        const checkInterval = setInterval(async () => {
            checkCount++;

            // Timeout después de 10 minutos
            if (checkCount > maxChecks) {
                console.error(`[esperarCompletado] TIMEOUT después de ${checkCount} intentos`);
                clearInterval(checkInterval);
                reject(new Error('Timeout: El ETL tomó más de 10 minutos. Verifica el log del servidor.'));
                return;
            }

            try {
                console.log(`[esperarCompletado #${checkCount}] Verificando completado para lote: ${loteImportacion}`);
                const response = await fetch(`/api/etl/progreso/${loteImportacion}?nocache=${Date.now()}`);
                if (response.ok) {
                    const progreso = await response.json();
                    console.log(`[esperarCompletado #${checkCount}] Estado recibido:`, progreso.estado, 'Objeto completo:', progreso);

                    if (progreso.estado === 'Completado' || progreso.estado.startsWith('Error')) {
                        console.log(`[esperarCompletado #${checkCount}] ¡ETL COMPLETADO! Resolviendo promesa...`);
                        clearInterval(checkInterval);
                        resolve(progreso);
                    } else {
                        console.log(`[esperarCompletado #${checkCount}] Aún en proceso, esperando...`);
                    }
                } else {
                    console.error(`[esperarCompletado #${checkCount}] Error HTTP: ${response.status}`);
                    // No rechazar inmediatamente, continuar intentando
                }
            } catch (error) {
                console.error(`[esperarCompletado #${checkCount}] Error:`, error);
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
                <h5><i class="fas fa-check-circle"></i> ETL ejecutado exitosamente</h5>
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
                    <th>Lote Importación:</th>
                    <td><code>${progreso.loteImportacion}</code></td>
                </tr>
                <tr>
                    <th>Registros Importados:</th>
                    <td><strong>${progreso.registrosInsertados}</strong></td>
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
                <a href="/calculo.html" class="btn btn-primary">
                    <i class="fas fa-calculator"></i> Ir a Cálculo
                </a>
            </div>
        `;
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-danger');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-danger', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-circle"></i> Error en la Extracción';

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

function mostrarResultadosMultiples(resultados, todasExitosas) {
    const resultadoDiv = document.getElementById('resultadoDiv');
    const resultadoCard = document.getElementById('resultadoCard');
    const resultadoContent = document.getElementById('resultadoContent');

    if (todasExitosas) {
        resultadoCard.classList.remove('border-danger');
        resultadoCard.classList.add('border-success');
        resultadoCard.querySelector('.card-header').classList.remove('bg-danger');
        resultadoCard.querySelector('.card-header').classList.add('bg-success', 'text-white');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-check-circle"></i> ETL Múltiple - Todas exitosas';
    } else {
        resultadoCard.classList.remove('border-success');
        resultadoCard.classList.add('border-warning');
        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-warning', 'text-dark');
        resultadoCard.querySelector('.card-header h5').innerHTML = '<i class="fas fa-exclamation-triangle"></i> ETL Múltiple - Con errores';
    }

    const exitosas = resultados.filter(r => r.exitoso).length;
    const fallidas = resultados.length - exitosas;
    const totalRegistros = resultados.filter(r => r.exitoso).reduce((sum, r) => sum + (r.resultado?.registrosInsertados || 0), 0);

    let html = `
        <div class="alert ${todasExitosas ? 'alert-success' : 'alert-warning'}">
            <h5><i class="fas ${todasExitosas ? 'fa-check-circle' : 'fa-exclamation-triangle'}"></i> Proceso completado</h5>
            <p><strong>${exitosas}</strong> de <strong>${resultados.length}</strong> compañías procesadas exitosamente</p>
            ${fallidas > 0 ? `<p class="text-danger"><strong>${fallidas}</strong> compañías con errores</p>` : ''}
            <p><strong>Total registros importados:</strong> ${totalRegistros}</p>
        </div>
        <h6>Detalle por compañía:</h6>
        <table class="table table-sm table-striped">
            <thead class="table-dark">
                <tr>
                    <th>Compañía</th>
                    <th>Estado</th>
                    <th>Registros</th>
                    <th>Duración</th>
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
                    <td>${progreso.registrosInsertados || 0}</td>
                    <td>${duracionSegundos}s</td>
                </tr>
            `;
        } else {
            html += `
                <tr class="table-danger">
                    <td><strong>${resultado.compania}</strong></td>
                    <td><span class="badge bg-danger">Error</span></td>
                    <td colspan="2"><small class="text-danger">${resultado.error}</small></td>
                </tr>
            `;
        }
    }

    html += `
            </tbody>
        </table>
        <div class="mt-3">
            <a href="/calculo.html" class="btn btn-primary">
                <i class="fas fa-calculator"></i> Ir a Cálculo
            </a>
        </div>
    `;

    resultadoContent.innerHTML = html;
    resultadoDiv.style.display = 'block';
    resultadoDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}
