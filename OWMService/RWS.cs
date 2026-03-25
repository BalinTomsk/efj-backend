using Microsoft.Win32;
using OWMService.Config;
using OWMService.Logging;
using OWMService.Workers;
using System;
using System.ServiceProcess;
using System.Timers;

namespace OWMService
{
    public partial class RWS : ServiceBase
    {
        private const string EventSourceName = "OWMService";
        private const string EventLogName = "Application";

        private System.Timers.Timer m_timer;
        private readonly IEventLogger m_logger;
        private readonly ISettingsProvider m_settingsProvider;
        private readonly IWeatherDataWorker m_weatherDataWorker;

        private double m_servicePollInterval;
        private Settings m_settings = new Settings();

        private bool m_bFlagProcessing = false;
        private const string NullGuid = "00000000-0000-0000-0000-000000000000";

        // Constructor - uses provided logger
        public RWS(IEventLogger logger)
            : this(logger, new RegistrySettingsProvider())
        {
        }

        // Overload for DI (logger + settings provider)
        public RWS(IEventLogger logger, ISettingsProvider settingsProvider)
            : this(logger, settingsProvider, new WeatherDataWorker(logger))
        {
        }

        // Full overload for DI (logger + settings provider + worker)
        public RWS(IEventLogger logger, ISettingsProvider settingsProvider, IWeatherDataWorker weatherDataWorker)
        {
            // Set service properties first
            ServiceName = "OWMService";
            CanStop = true;
            CanPauseAndContinue = true;
    
            // Initialize designer component (empty, but required)
            InitializeComponent();

            // Set dependencies
            m_logger = logger ?? LoggerFactory.CreateDefaultLogger(EventSourceName, EventLogName);
            m_settingsProvider = settingsProvider ?? new RegistrySettingsProvider();
            m_weatherDataWorker = weatherDataWorker ?? new WeatherDataWorker(m_logger);
            m_servicePollInterval = m_settings.Interval;
        }

        // Default ctor for SCM
        public RWS()
            : this(LoggerFactory.CreateDefaultLogger(EventSourceName, EventLogName))
        {
        }

        protected override void OnStart(string[] args)
        {
            try
            {
                m_logger.LogInfo("=== OWMService OnStart ===");

                if (!m_settingsProvider.TryReadSettings(out var settings, out var err))
                {
                    m_logger.LogError($"Failed to read settings: {err}");
                    return;
                }

                // Apply settings
                m_settings.Server = string.IsNullOrWhiteSpace(settings.Server) ? m_settings.Server : settings.Server;
                m_settings.DbName = string.IsNullOrWhiteSpace(settings.DbName) ? m_settings.DbName : settings.DbName;
                m_settings.UserName = string.IsNullOrWhiteSpace(settings.UserName) ? m_settings.UserName : settings.UserName;
                m_settings.UserPassword = string.IsNullOrWhiteSpace(settings.UserPassword) ? m_settings.UserPassword : settings.UserPassword;
                m_settings.Wunderground = string.IsNullOrWhiteSpace(settings.Wunderground) ? m_settings.Wunderground : settings.Wunderground;
                m_servicePollInterval = settings.Interval > 0 ? settings.Interval : m_servicePollInterval;
                m_settings.Interval = (int)m_servicePollInterval;

                m_logger.LogInfo($"Settings loaded - Server: {m_settings.Server}, Database: {m_settings.DbName}");

                m_timer = new System.Timers.Timer();
                m_timer.Interval = 10000;
                m_timer.Elapsed += TimerElapsed;
                m_timer.AutoReset = true;
                m_timer.Start();

                m_logger.LogInfo("OWMService started successfully");
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OnStart exception: {ex.Message}\n{ex.StackTrace}");
                throw;
            }
        }

        protected override void OnStop()
        {
            try
            {
                m_logger.LogInfo("=== OWMService OnStop ===");

                m_bFlagProcessing = true;

                if (m_timer != null)
                {
                    m_timer.Stop();
                    m_timer.Dispose();
                    m_timer = null;
                }

                m_logger.LogInfo("OWMService stopped");
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OnStop exception: {ex.Message}");
            }
        }

        protected override void OnContinue()
        {
            m_bFlagProcessing = false;
            m_logger.LogInfo("OWMService continued");
        }

        protected override void OnPause()
        {
            m_bFlagProcessing = true;
            m_logger.LogInfo("OWMService paused");
        }

        protected override void OnShutdown()
        {
            m_bFlagProcessing = true;
            if (m_timer != null)
            {
                m_timer.Stop();
            }
            m_logger.LogInfo("OWMService shutdown");
            base.OnShutdown();
        }

        private void TimerElapsed(object sender, ElapsedEventArgs e)
        {
            if (m_bFlagProcessing)
            {
                return;
            }

            m_bFlagProcessing = true;

            try
            {
                m_logger.LogInfo($"Processing weather data at {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                m_weatherDataWorker.Process(m_settings);
                m_logger.LogInfo("Processing completed");
            }
            catch (Exception ex)
            {
                m_logger.LogError($"Processing error: {ex.Message}\n{ex.StackTrace}");
            }
            finally
            {
                m_bFlagProcessing = false;
            }
        }

        public void StartDebug(string[] args)
        {
            m_logger.LogInfo("=== Debug Mode Started ===");
            m_bFlagProcessing = false;
            OnStart(args);

            try
            {
                m_logger.LogInfo("Running single weather data process");
                m_weatherDataWorker.Process(m_settings);
                m_logger.LogInfo("Debug process completed");
            }
            catch (Exception ex)
            {
                m_logger.LogError($"Debug error: {ex.Message}\n{ex.StackTrace}");
            }
        }

        public void StopDebug()
        {
            m_logger.LogInfo("=== Debug Mode Stopped ===");
            OnStop();
        }
    }
}