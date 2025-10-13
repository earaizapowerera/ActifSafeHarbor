// Companias CRUD JavaScript

let modalCompania;
let isEditMode = false;
let currentId = null;

document.addEventListener('DOMContentLoaded', function() {
    modalCompania = new bootstrap.Modal(document.getElementById('modalCompania'));

    // Load companies on page load
    cargarCompanias();

    // Button event listeners
    document.getElementById('btnNuevo').addEventListener('click', abrirModalNuevo);
    document.getElementById('btnGuardar').addEventListener('click', guardarCompania);
});

async function cargarCompanias() {
    try {
        const response = await fetch('/api/companias');
        if (!response.ok) throw new Error('Error al cargar compañías');

        const companias = await response.json();
        const tbody = document.getElementById('tbodyCompanias');

        if (companias.length === 0) {
            tbody.innerHTML = '<tr><td colspan="6" class="text-center">No hay compañías registradas</td></tr>';
            return;
        }

        tbody.innerHTML = companias.map(c => `
            <tr>
                <td>${c.idConfiguracion}</td>
                <td>${c.idCompania}</td>
                <td>${c.nombreCompania}</td>
                <td>${c.nombreCorto}</td>
                <td>
                    <span class="badge ${c.activo ? 'bg-success' : 'bg-secondary'}">
                        ${c.activo ? 'Activo' : 'Inactivo'}
                    </span>
                </td>
                <td>
                    <button class="btn btn-sm btn-primary" onclick="editarCompania(${c.idConfiguracion})">
                        <i class="fas fa-edit"></i> Editar
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="eliminarCompania(${c.idConfiguracion})">
                        <i class="fas fa-trash"></i> Eliminar
                    </button>
                </td>
            </tr>
        `).join('');

    } catch (error) {
        console.error('Error:', error);
        alert('Error al cargar las compañías: ' + error.message);
    }
}

function abrirModalNuevo() {
    isEditMode = false;
    currentId = null;

    document.getElementById('modalTitleText').textContent = 'Nueva Compañía';
    document.getElementById('formCompania').reset();
    document.getElementById('idConfiguracion').value = '';
    document.getElementById('activo').checked = true;

    modalCompania.show();
}

async function editarCompania(id) {
    try {
        const response = await fetch(`/api/companias/${id}`);
        if (!response.ok) throw new Error('Error al cargar compañía');

        const compania = await response.json();

        isEditMode = true;
        currentId = id;

        document.getElementById('modalTitleText').textContent = 'Editar Compañía';
        document.getElementById('idConfiguracion').value = compania.idConfiguracion;
        document.getElementById('idCompania').value = compania.idCompania;
        document.getElementById('nombreCompania').value = compania.nombreCompania;
        document.getElementById('nombreCorto').value = compania.nombreCorto;
        document.getElementById('connectionString').value = compania.connectionString;
        document.getElementById('queryETL').value = compania.queryETL || '';
        document.getElementById('activo').checked = compania.activo;

        modalCompania.show();

    } catch (error) {
        console.error('Error:', error);
        alert('Error al cargar la compañía: ' + error.message);
    }
}

async function guardarCompania() {
    const form = document.getElementById('formCompania');
    if (!form.checkValidity()) {
        form.reportValidity();
        return;
    }

    const data = {
        idCompania: parseInt(document.getElementById('idCompania').value),
        nombreCompania: document.getElementById('nombreCompania').value,
        nombreCorto: document.getElementById('nombreCorto').value,
        connectionString: document.getElementById('connectionString').value,
        queryETL: document.getElementById('queryETL').value || null,
        activo: document.getElementById('activo').checked
    };

    try {
        const url = isEditMode ? `/api/companias/${currentId}` : '/api/companias';
        const method = isEditMode ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method: method,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        if (!response.ok) {
            const error = await response.text();
            throw new Error(error);
        }

        const result = await response.json();
        alert(result.message);

        modalCompania.hide();
        cargarCompanias();

    } catch (error) {
        console.error('Error:', error);
        alert('Error al guardar: ' + error.message);
    }
}

async function eliminarCompania(id) {
    if (!confirm('¿Está seguro de eliminar esta compañía?')) {
        return;
    }

    try {
        const response = await fetch(`/api/companias/${id}`, {
            method: 'DELETE'
        });

        if (!response.ok) {
            const error = await response.text();
            throw new Error(error);
        }

        const result = await response.json();
        alert(result.message);
        cargarCompanias();

    } catch (error) {
        console.error('Error:', error);
        alert('Error al eliminar: ' + error.message);
    }
}
