// Shared JavaScript - Carga el navbar en todas las páginas
document.addEventListener('DOMContentLoaded', async function() {
    // Cargar el navbar
    const navbarPlaceholder = document.getElementById('navbar-placeholder');
    if (navbarPlaceholder) {
        try {
            const response = await fetch('/shared/navbar.html');
            const html = await response.text();
            navbarPlaceholder.innerHTML = html;

            // Marcar el item activo del menú según la página actual
            marcarItemActivo();
        } catch (error) {
            console.error('Error al cargar navbar:', error);
        }
    }
});

function marcarItemActivo() {
    // Obtener el nombre de la página actual
    const path = window.location.pathname;
    const pageName = path.substring(path.lastIndexOf('/') + 1).replace('.html', '') || 'index';

    // Marcar el item correspondiente como activo
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        const linkPage = link.getAttribute('data-page');
        if (linkPage === pageName) {
            link.classList.add('active');
        } else {
            link.classList.remove('active');
        }
    });
}
