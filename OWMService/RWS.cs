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

        private bool m_bFlagProcessing = true;
        private const string NullGuid = "00000000-0000-0000-0000-000000000000";

        // Default ctor used by SCM - selects logger/provider based on defaults.
        public RWS()
            : this(LoggerFactory.CreateDefaultLogger(EventSourceName, EventLogName), new RegistrySettingsProvider())
        {
        }

        // Overload for DI (log provider); keeps registry provider.
        public RWS(IEventLogger logger)
            : this(logger, new RegistrySettingsProvider())
        {
        }

        // Overload for DI (logger + settings provider).
        public RWS(IEventLogger logger, ISettingsProvider settingsProvider)
            : this(logger, settingsProvider, new WeatherDataWorker(logger))
        {
        }

        // Full overload for DI (logger + settings provider + worker).
        public RWS(IEventLogger logger, ISettingsProvider settingsProvider, IWeatherDataWorker weatherDataWorker)
        {
            InitializeComponent();
            m_logger = logger ?? LoggerFactory.CreateDefaultLogger(EventSourceName, EventLogName);
            m_settingsProvider = settingsProvider ?? new RegistrySettingsProvider();
            m_weatherDataWorker = weatherDataWorker ?? new WeatherDataWorker(m_logger);
            // m_settings already has sensible defaults from Settings ctor/initializers
            m_servicePollInterval = m_settings.Interval;
        }

        protected override void OnStart(string[] args)
        {
            m_logger.LogInfo("OWMService starting.");

            if (!m_settingsProvider.TryReadSettings(out var settings, out var err))
            {
                m_logger.LogError(err ?? "Failed to read settings.");
                return;
            }

            // apply settings (preserve defaults when values are null/empty)
            m_settings.Server = string.IsNullOrWhiteSpace(settings.Server) ? m_settings.Server : settings.Server;
            m_settings.DbName = string.IsNullOrWhiteSpace(settings.DbName) ? m_settings.DbName : settings.DbName;
            m_settings.UserName = string.IsNullOrWhiteSpace(settings.UserName) ? m_settings.UserName : settings.UserName;
            m_settings.UserPassword = string.IsNullOrWhiteSpace(settings.UserPassword) ? m_settings.UserPassword : settings.UserPassword;
            m_settings.Wunderground = string.IsNullOrWhiteSpace(settings.Wunderground) ? m_settings.Wunderground : settings.Wunderground;
            m_servicePollInterval = settings.Interval > 0 ? settings.Interval : m_servicePollInterval;
            m_settings.Interval = (int)m_servicePollInterval;

            m_logger.LogInfo("OWMService started.");

            m_timer = new System.Timers.Timer();
            m_timer.Interval = 10000;
            m_timer.Elapsed += TimerElapsed;
            m_timer.AutoReset = true;
            m_timer.Start();
        }

        protected override void OnStop()
        {
            Console.WriteLine("OWMService stopped.");

            m_logger.LogInfo("OWMService stopped.");
            m_bFlagProcessing = true;

            if (m_timer != null)
            {
                m_timer.Stop();
                m_timer.Dispose();
                m_timer = null;
            }

            if (m_logger is IDisposable disposableLogger)
            {
                try
                {
                    disposableLogger.Dispose();
                }
                catch
                {
                    // swallow disposal exceptions to avoid failing stop
                }
            }
        }

        protected override void OnContinue()
        {
            m_bFlagProcessing = false;
            m_logger.LogInfo("OWMService OnContinue.");
        }

        protected override void OnShutdown()
        {
            m_bFlagProcessing = true;
            if (m_timer != null)
            {
                m_timer.Stop();
            }

            m_logger.LogInfo("OWMService OnShutdown.");
            base.OnShutdown();
        }

        private void TimerElapsed(object sender, ElapsedEventArgs e)
        {
            // Only process if NOT already processing
            if (m_bFlagProcessing)
            {
                return;
            }

            m_bFlagProcessing = true;

            try
            {
                m_logger.LogInfo("OWMService running at " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                m_weatherDataWorker.Process(m_settings);
            }
            catch (Exception ex)
            {
                m_logger.LogError($"Error in TimerElapsed: {ex.Message}");
            }
            finally
            {
                m_bFlagProcessing = false;
            }
        }

        public void StartDebug(string[] args)
        {
            m_bFlagProcessing = false;  // Allow processing in debug mode
            OnStart(args);
            m_weatherDataWorker.Process(m_settings);
        }

        public void StopDebug()
        {
            OnStop();
        }
    }
}