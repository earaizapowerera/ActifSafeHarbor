// INPC JavaScript

document.addEventListener('DOMContentLoaded', function() {
    cargarEstadisticas();
    cargarDatosRecientes();

    document.getElementById('btnActualizar').addEventListener('click', actualizarINPC);
});

async function cargarEstadisticas() {
    try {
        const response = await fetch('/api/inpc/estadisticas');
        if (!response.ok) throw new Error('Error al cargar estadísticas');

        const stats = await response.json();
        const contenido = document.getElementById('estadisticasContent');

        contenido.innerHTML = `
            <div class="row text-center">
                <div class="col-md-6 mb-3">
                    <div class="border rounded p-3">
                        <h2 class="text-primary">${stats.totalRegistros}</h2>
                        <p class="mb-0">Total Registros</p>
                    </div>
                </div>
                <div class="col-md-6 mb-3">
                    <div class="border rounded p-3">
                        <h2 class="text-success">${stats.años}</h2>
                        <p class="mb-0">Años Disponibles</p>
                    </div>
                </div>
            </div>
            <div class="mt-3">
                <p><strong>Rango:</strong> ${stats.añoMinimo} - ${stats.añoMaximo}</p>
                <p><strong>Última importación:</strong> ${new Date(stats.ultimaImportacion).toLocaleString('es-MX')}</p>
            </div>
        `;

    } catch (error) {
        console.error('Error:', error);
        document.getElementById('estadisticasContent').innerHTML = `
            <div class="alert alert-warning">
                No hay datos de INPC disponibles. Ejecute una actualización.
            </div>
        `;
    }
}

async function cargarDatosRecientes() {
    try {
        const response = await fetch('/api/inpc/recientes');
        if (!response.ok) throw new Error('Error al cargar datos recientes');

        const datos = await response.json();
        const tbody = document.getElementById('tbodyINPC');

        if (datos.length === 0) {
            tbody.innerHTML = '<tr><td colspan="4" class="text-center">No hay datos de INPC disponibles</td></tr>';
            return;
        }

        const meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                       'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

        tbody.innerHTML = datos.map(d => `
            <tr>
                <td>${d.anio}</td>
                <td>${meses[d.mes - 1]}</td>
                <td>${d.indice.toFixed(6)}</td>
                <td>${new Date(d.fechaImportacion).toLocaleDateString('es-MX')}</td>
            </tr>
        `).join('');

    } catch (error) {
        console.error('Error:', error);
        document.getElementById('tbodyINPC').innerHTML =
            '<tr><td colspan="4" class="text-center text-danger">Error al cargar datos</td></tr>';
    }
}

async function actualizarINPC() {
    const btnActualizar = document.getElementById('btnActualizar');
    const progressDiv = document.getElementById('progressDiv');
    const resultadoCard = document.getElementById('resultadoCard');
    const grupoSimulacion = document.getElementById('grupoSimulacion').value;

    const mensaje = grupoSimulacion
        ? `¿Está seguro de actualizar los datos de INPC para el grupo ${grupoSimulacion}? Esto reemplazará los datos existentes de ese grupo.`
        : '¿Está seguro de actualizar los datos de INPC? Esto reemplazará todos los datos existentes.';

    if (!confirm(mensaje)) {
        return;
    }

    // Deshabilitar botón y mostrar progreso
    btnActualizar.disabled = true;
    btnActualizar.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Actualizando...';
    progressDiv.style.display = 'block';
    resultadoCard.style.display = 'none';

    try {
        // Construir URL con parámetro de grupo de simulación si existe
        let url = '/api/inpc/actualizar';
        if (grupoSimulacion) {
            url += `?idGrupoSimulacion=${grupoSimulacion}`;
        }

        const response = await fetch(url, {
            method: 'POST'
        });

        const result = await response.json();

        progressDiv.style.display = 'none';

        if (!response.ok) {
            throw new Error(result.detail || result.message || 'Error desconocido');
        }

        // Mostrar resultado exitoso
        let grupoInfo = '';
        if (result.idGrupoSimulacion) {
            grupoInfo = `
                <tr>
                    <th>Grupo Simulación:</th>
                    <td><strong>${result.idGrupoSimulacion}</strong></td>
                </tr>`;
        }

        document.getElementById('resultadoContent').innerHTML = `
            <div class="alert alert-success">
                <h5><i class="fas fa-check-circle"></i> ${result.message}</h5>
            </div>
            <table class="table table-bordered">
                <tr>
                    <th>Registros Importados:</th>
                    <td><strong>${result.registrosImportados}</strong></td>
                </tr>
                ${grupoInfo}
                <tr>
                    <th>Duración:</th>
                    <td>${result.duracionSegundos} segundos</td>
                </tr>
                <tr>
                    <th>Lote:</th>
                    <td><code>${result.loteImportacion}</code></td>
                </tr>
            </table>
        `;

        resultadoCard.querySelector('.card-header').classList.remove('bg-danger');
        resultadoCard.querySelector('.card-header').classList.add('bg-success', 'text-white');
        resultadoCard.style.display = 'block';

        // Recargar estadísticas y datos recientes
        cargarEstadisticas();
        cargarDatosRecientes();

    } catch (error) {
        console.error('Error:', error);

        progressDiv.style.display = 'none';

        document.getElementById('resultadoContent').innerHTML = `
            <div class="alert alert-danger">
                <h5><i class="fas fa-exclamation-circle"></i> Error</h5>
                <p>${error.message}</p>
            </div>
        `;

        resultadoCard.querySelector('.card-header').classList.remove('bg-success');
        resultadoCard.querySelector('.card-header').classList.add('bg-danger', 'text-white');
        resultadoCard.style.display = 'block';

    } finally {
        // Re-habilitar botón
        btnActualizar.disabled = false;
        btnActualizar.innerHTML = '<i class="fas fa-sync"></i> Actualizar INPC Ahora';
    }
}
