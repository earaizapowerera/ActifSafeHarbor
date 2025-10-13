using OpenQA.Selenium;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Support.UI;
using Xunit;

namespace ActifRMF.Tests;

public class CompaniasCRUDTests : IDisposable
{
    private readonly IWebDriver _driver;
    private readonly WebDriverWait _wait;
    private readonly string _baseUrl = "http://localhost:5071";

    public CompaniasCRUDTests()
    {
        var options = new ChromeOptions();
        options.AddArgument("--headless"); // Ejecutar sin ventana
        options.AddArgument("--no-sandbox");
        options.AddArgument("--disable-dev-shm-usage");
        options.AddArgument("--disable-gpu");

        _driver = new ChromeDriver(options);
        _wait = new WebDriverWait(_driver, TimeSpan.FromSeconds(10));
    }

    [Fact]
    public void Test01_PaginaPrincipalCarga()
    {
        // Arrange & Act
        _driver.Navigate().GoToUrl(_baseUrl);

        // Assert
        Assert.Contains("ActifRMF", _driver.Title);

        // Verificar que hay 3 tarjetas principales
        var cards = _driver.FindElements(By.CssSelector(".card"));
        Assert.True(cards.Count >= 3, "Debe haber al menos 3 tarjetas en la página principal");
    }

    [Fact]
    public void Test02_PaginaCompaniasCarga()
    {
        // Arrange & Act
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");

        // Assert
        Assert.Contains("Compañías", _driver.Title);

        // Verificar que existe el botón de nueva compañía
        var btnNuevo = _wait.Until(d => d.FindElement(By.Id("btnNuevo")));
        Assert.NotNull(btnNuevo);
        Assert.Contains("Nueva Compañía", btnNuevo.Text);
    }

    [Fact]
    public void Test03_ListarCompaniasExistentes()
    {
        // Arrange & Act
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");

        // Esperar a que cargue la tabla
        Thread.Sleep(2000); // Dar tiempo para que cargue la data

        var tbody = _driver.FindElement(By.Id("tbodyCompanias"));
        var rows = tbody.FindElements(By.TagName("tr"));

        // Assert - Debería haber al menos 3 compañías (CIMA, GILL, LEARCORP)
        Assert.True(rows.Count >= 3, $"Debe haber al menos 3 compañías, se encontraron {rows.Count}");

        // Verificar que cada fila tiene botones de editar y eliminar
        foreach (var row in rows)
        {
            var buttons = row.FindElements(By.TagName("button"));
            Assert.True(buttons.Count >= 2, "Cada fila debe tener botones de editar y eliminar");
        }
    }

    [Fact]
    public void Test04_AbrirModalNuevaCompania()
    {
        // Arrange
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");

        // Act
        var btnNuevo = _wait.Until(d => d.FindElement(By.Id("btnNuevo")));
        btnNuevo.Click();

        // Esperar a que el modal sea visible
        Thread.Sleep(1000);

        // Assert
        var modal = _driver.FindElement(By.Id("modalCompania"));
        Assert.True(modal.Displayed, "El modal debe estar visible");

        var modalTitle = _driver.FindElement(By.Id("modalTitleText"));
        Assert.Equal("Nueva Compañía", modalTitle.Text);

        // Verificar que los campos están vacíos
        var idCompania = _driver.FindElement(By.Id("idCompania"));
        Assert.Equal("", idCompania.GetAttribute("value"));
    }

    [Fact]
    public void Test05_CrearNuevaCompania()
    {
        // Arrange
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");

        // Abrir modal
        var btnNuevo = _wait.Until(d => d.FindElement(By.Id("btnNuevo")));
        btnNuevo.Click();
        Thread.Sleep(1000);

        // Act - Llenar formulario
        var idCompania = _driver.FindElement(By.Id("idCompania"));
        var nombreCompania = _driver.FindElement(By.Id("nombreCompania"));
        var nombreCorto = _driver.FindElement(By.Id("nombreCorto"));
        var connectionString = _driver.FindElement(By.Id("connectionString"));
        var queryETL = _driver.FindElement(By.Id("queryETL"));
        var activo = _driver.FindElement(By.Id("activo"));

        int randomId = new Random().Next(100, 999);
        idCompania.SendKeys(randomId.ToString());
        nombreCompania.SendKeys($"Test Company {randomId}");
        nombreCorto.SendKeys($"TEST{randomId}");
        connectionString.SendKeys("Server=test;Database=test;User Id=test;Password=test;");
        queryETL.SendKeys("SELECT * FROM activo WHERE ID_COMPANIA = @ID_COMPANIA");

        // Guardar
        var btnGuardar = _driver.FindElement(By.Id("btnGuardar"));
        btnGuardar.Click();

        // Esperar a que se cierre el modal y se recargue la lista
        Thread.Sleep(3000);

        // Assert - Verificar que aparece en la lista
        var tbody = _driver.FindElement(By.Id("tbodyCompanias"));
        var pageSource = tbody.Text;

        Assert.Contains($"Test Company {randomId}", pageSource);
    }

    [Fact]
    public void Test06_EditarCompania()
    {
        // Arrange
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");
        Thread.Sleep(2000);

        // Act - Hacer clic en el primer botón de editar
        var tbody = _driver.FindElement(By.Id("tbodyCompanias"));
        var firstEditButton = tbody.FindElement(By.CssSelector("button.btn-primary"));
        firstEditButton.Click();

        Thread.Sleep(1000);

        // Assert - Verificar que el modal se abrió en modo edición
        var modalTitle = _driver.FindElement(By.Id("modalTitleText"));
        Assert.Equal("Editar Compañía", modalTitle.Text);

        // Verificar que los campos tienen datos
        var nombreCompania = _driver.FindElement(By.Id("nombreCompania"));
        Assert.NotEqual("", nombreCompania.GetAttribute("value"));

        // Modificar el nombre corto
        var nombreCorto = _driver.FindElement(By.Id("nombreCorto"));
        string originalValue = nombreCorto.GetAttribute("value");
        nombreCorto.Clear();
        nombreCorto.SendKeys(originalValue + "_EDITADO");

        // Guardar
        var btnGuardar = _driver.FindElement(By.Id("btnGuardar"));
        btnGuardar.Click();

        Thread.Sleep(3000);

        // Verificar que se guardó
        var pageSource = _driver.FindElement(By.Id("tbodyCompanias")).Text;
        Assert.Contains("_EDITADO", pageSource);
    }

    [Fact]
    public void Test07_ValidacionCamposRequeridos()
    {
        // Arrange
        _driver.Navigate().GoToUrl($"{_baseUrl}/companias.html");

        // Abrir modal
        var btnNuevo = _wait.Until(d => d.FindElement(By.Id("btnNuevo")));
        btnNuevo.Click();
        Thread.Sleep(1000);

        // Act - Intentar guardar sin llenar campos
        var btnGuardar = _driver.FindElement(By.Id("btnGuardar"));
        btnGuardar.Click();

        Thread.Sleep(500);

        // Assert - El modal debe seguir abierto porque los campos son requeridos
        var modal = _driver.FindElement(By.Id("modalCompania"));
        Assert.True(modal.Displayed, "El modal debe seguir visible cuando hay campos requeridos vacíos");
    }

    [Fact]
    public void Test08_PaginaExtraccionCarga()
    {
        // Arrange & Act
        _driver.Navigate().GoToUrl($"{_baseUrl}/extraccion.html");

        // Assert
        Assert.Contains("Extracción", _driver.Title);

        // Verificar que existe el formulario de extracción
        var formExtraccion = _wait.Until(d => d.FindElement(By.Id("formExtraccion")));
        Assert.NotNull(formExtraccion);

        // Verificar campos del formulario
        var companiaSelect = _driver.FindElement(By.Id("companiaSelect"));
        var anioCalculo = _driver.FindElement(By.Id("anioCalculo"));
        var usuario = _driver.FindElement(By.Id("usuario"));
        var btnEjecutar = _driver.FindElement(By.Id("btnEjecutar"));

        Assert.NotNull(companiaSelect);
        Assert.NotNull(anioCalculo);
        Assert.NotNull(usuario);
        Assert.NotNull(btnEjecutar);
    }

    [Fact]
    public void Test09_CompaniasDropdownCarga()
    {
        // Arrange & Act
        _driver.Navigate().GoToUrl($"{_baseUrl}/extraccion.html");
        Thread.Sleep(2000); // Dar tiempo para cargar el dropdown

        // Assert
        var companiaSelect = _driver.FindElement(By.Id("companiaSelect"));
        var options = companiaSelect.FindElements(By.TagName("option"));

        // Debe haber al menos 4 opciones (1 placeholder + 3 compañías mínimo)
        Assert.True(options.Count >= 4, $"Debe haber al menos 4 opciones en el dropdown, se encontraron {options.Count}");

        // La primera opción debe ser el placeholder
        Assert.Contains("Seleccione", options[0].Text);
    }

    [Fact]
    public void Test10_NavigacionMenu()
    {
        // Test navegación desde página principal
        _driver.Navigate().GoToUrl(_baseUrl);

        // Ir a Compañías
        var linkCompanias = _wait.Until(d => d.FindElement(By.CssSelector("a[href='/companias.html']")));
        linkCompanias.Click();
        Thread.Sleep(1000);
        Assert.Contains("companias.html", _driver.Url);

        // Ir a Extracción
        var linkExtraccion = _wait.Until(d => d.FindElement(By.CssSelector("a[href='/extraccion.html']")));
        linkExtraccion.Click();
        Thread.Sleep(1000);
        Assert.Contains("extraccion.html", _driver.Url);

        // Volver a inicio
        var brandLink = _driver.FindElement(By.CssSelector("a.navbar-brand"));
        brandLink.Click();
        Thread.Sleep(1000);
        Assert.Equal($"{_baseUrl}/", _driver.Url);
    }

    public void Dispose()
    {
        _driver?.Quit();
        _driver?.Dispose();
    }
}
