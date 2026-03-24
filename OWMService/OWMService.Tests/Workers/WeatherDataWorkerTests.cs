namespace OWMService.Tests.Workers
{
    using Moq;
    using OWMService.Config;
    using OWMService.Logging;
    using OWMService.Workers;
    using System;
    using System.Collections.Generic;
    using System.Data;
    using System.Data.SqlClient;
    using System.Threading.Tasks;
    using Xunit;

    public class WeatherDataWorkerTests
    {
        private readonly Mock<IEventLogger> m_mockLogger;
        private readonly WeatherDataWorker m_worker;

        public WeatherDataWorkerTests()
        {
            m_mockLogger = new Mock<IEventLogger>();
            m_worker = new WeatherDataWorker(m_mockLogger.Object);
        }

        #region Constructor Tests

        [Fact]
        public void Constructor_WithValidLogger_ShouldInitialize()
        {
            // Arrange & Act
            var worker = new WeatherDataWorker(m_mockLogger.Object);

            // Assert
            Assert.NotNull(worker);
        }

        [Fact]
        public void Constructor_WithNullLogger_ShouldThrowArgumentNullException()
        {
            // Act & Assert
            Assert.Throws<ArgumentNullException>(() => new WeatherDataWorker(null));
        }

        #endregion

        #region Process Tests

        [Fact]
        public void Process_WithEmptySettings_ShouldReturnFalse()
        {
            // Arrange
            var settings = new Settings
            {
                Server = "",
                DbName = "",
                UserName = "",
                UserPassword = ""
            };

            // Act
            var result = m_worker.Process(settings);

            // Assert
            Assert.False(result);
        }

        [Fact]
        public void Process_WithNullSettings_ShouldReturnFalse()
        {
            // Arrange
            var settings = new Settings
            {
                Server = null,
                DbName = null,
                UserName = null,
                UserPassword = null
            };

            // Act
            var result = m_worker.Process(settings);

            // Assert
            Assert.False(result);
        }

        #endregion

        #region ProcessAsync Tests

        [Fact]
        public async Task ProcessAsync_WithEmptyConnectionString_ShouldReturnFalse()
        {
            // Arrange
            var settings = new Settings
            {
                Server = "",
                DbName = "",
                UserName = "",
                UserPassword = ""
            };

            // Act
            var result = await m_worker.ProcessAsync(settings);

            // Assert
            Assert.False(result);
            m_mockLogger.Verify(l => l.LogInfo(It.IsAny<string>()), Times.Never);
        }

        [Fact]
        public async Task ProcessAsync_WithNullConnectionString_ShouldReturnFalse()
        {
            // Arrange
            var settings = new Settings
            {
                Server = null,
                DbName = null,
                UserName = null,
                UserPassword = null
            };

            // Act
            var result = await m_worker.ProcessAsync(settings);

            // Assert
            Assert.False(result);
        }

        [Fact]
        public async Task ProcessAsync_WithInvalidConnection_ShouldReturnFalseAndLogError()
        {
            // Arrange
            var settings = new Settings
            {
                Server = "invalid_server_12345",
                DbName = "testdb",
                UserName = "testuser",
                UserPassword = "wrongpass"
            };

            // Act
            var result = await m_worker.ProcessAsync(settings);

            // Assert
            Assert.False(result);
            m_mockLogger.Verify(
                l => l.LogError(It.IsAny<string>()),
                Times.Once,
                "Should log error on connection failure");
        }

        #endregion

        #region IWeatherDataWorker Interface Tests

        [Fact]
        public void WeatherDataWorker_ShouldImplementIWeatherDataWorker()
        {
            // Assert
            Assert.IsAssignableFrom<IWeatherDataWorker>(m_worker);
        }

        #endregion

        #region Integration-Ready Tests

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("   ")]
        public async Task ProcessAsync_WithVariousInvalidSettings_ShouldReturnFalse(string invalidValue)
        {
            // Arrange
            var settings = new Settings
            {
                Server = invalidValue,
                DbName = "testdb",
                UserName = "user",
                UserPassword = "pass"
            };

            // Act
            var result = await m_worker.ProcessAsync(settings);

            // Assert
            Assert.False(result);
        }

        [Fact]
        public void Process_ShouldCallProcessAsyncAndReturnResult()
        {
            // Arrange
            var settings = new Settings
            {
                Server = "",
                DbName = "",
                UserName = "",
                UserPassword = ""
            };

            // Act
            var result = m_worker.Process(settings);

            // Assert
            Assert.False(result);
        }

        [Fact]
        public async Task ProcessAsync_WithInvalidConnectionString_ShouldLogErrorMessage()
        {
            // Arrange
            var settings = new Settings
            {
                Server = "nonexistent_server_xyz_invalid",
                DbName = "testdb",
                UserName = "invaliduser",
                UserPassword = "invalidpass"
            };

            // Act
            var result = await m_worker.ProcessAsync(settings);

            // Assert
            Assert.False(result);
            m_mockLogger.Verify(
                l => l.LogError(It.Is<string>(msg => msg.Contains("OWMService Failed to connect"))),
                Times.Once,
                "Should log connection failure message");
        }

        #endregion
    }
}