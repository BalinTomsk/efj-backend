using Microsoft.Win32;
using OWMService.Config;
using OWMService.Logging;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
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

        private double m_servicePollInterval;
        private string m_serverName = Environment.MachineName;
        private string m_dbName = "fishfind";
        private string m_userName = "superadmin";
        private string m_userPassword = "superpassword";
        private string m_wunderground = "weather APi Key";  // https://preview.wunderground.com/member/api-keys

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

        // Full overload for DI (logger + settings provider).
        public RWS(IEventLogger logger, ISettingsProvider settingsProvider)
        {
            InitializeComponent();
            m_logger = logger ?? LoggerFactory.CreateDefaultLogger(EventSourceName, EventLogName);
            m_settingsProvider = settingsProvider ?? new RegistrySettingsProvider();
        }

        protected override void OnStart(string[] args)
        {
            m_logger.LogInfo("OWMService starting.");

            if (!m_settingsProvider.TryReadSettings(out var settings, out var err))
            {
                m_logger.LogError(err ?? "Failed to read settings.");
                return;
            }

            // apply settings
            m_serverName = settings.Server ?? m_serverName;
            m_dbName = settings.DbName ?? m_dbName;
            m_userName = settings.UserName ?? m_userName;
            m_userPassword = settings.UserPassword ?? m_userPassword;
            m_wunderground = settings.Wunderground ?? m_wunderground;
            m_servicePollInterval = settings.Interval > 0 ? settings.Interval : m_servicePollInterval;

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
            if (m_bFlagProcessing)
            {
                return;
            }

            m_bFlagProcessing = true;

            try
            {
                m_logger.LogInfo("OWMService running at " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                Process(false);
            }
            finally
            {
                m_bFlagProcessing = false;
            }
        }

        protected string GetConnectionString()
        {
            return string.Format(
                @"Data Source={0};Initial Catalog={1};Integrated Security=False;User ID={2};Password={3}",
                m_serverName,
                m_dbName,
                m_userName,
                m_userPassword);
        }

        private bool Process(bool isDebug)
        {
            string conStr = GetConnectionString();
            if (string.IsNullOrEmpty(conStr))
            {
                return false;
            }

            try
            {
                using (SqlConnection cnn = new SqlConnection(conStr))
                {
                    cnn.Open();

                    List<Tuple<string, float, float, string>> stations = GetListOwsMeteo(cnn);

                    ProcessEnvData(stations, isDebug, cnn);
                    ProcessFishState(cnn);

                    if (m_timer != null)
                    {
                        m_timer.Interval = 1000 * 60 * 2;
                    }

                    return true;
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError("OWMService Failed to connect. " + ex.Message + " at: " + conStr);
                return false;
            }
        }

        private void ProcessEnvData(List<Tuple<string, float, float, string>> stations, bool isDebug, SqlConnection cnn)
        {
            try
            {
                int i = 0;

                foreach (var item in stations)
                {
                    try
                    {
                        ProcessOWSPoint(item.Item1, item.Item2, item.Item3, cnn);
                        i++;
                    }
                    catch (Exception ex)
                    {
                        m_logger.LogError(
                            "OWMService station processing failed. " + ex.Message + " MLI: " + item.Item1 + " at: " + i);
                    }
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError("OWMService Failed in ProcessEnvData. " + ex.Message);
            }
        }

        private List<Tuple<string, float, float, string>> GetListOwsMeteo(SqlConnection cnn)
        {
            var result = new List<Tuple<string, float, float, string>>();

            using (SqlCommand cmd = new SqlCommand(
                "select mli, lat, lon, state from WaterStation w where exists (select * from lake_fish f where f.lake_Id = w.lakeId)", cnn))
            using (SqlDataReader dr = cmd.ExecuteReader())
            {
                while (dr.Read())
                {
                    string mli = dr.GetString(0);
                    float lat = (float)dr.GetDouble(1);
                    float lon = (float)dr.GetDouble(2);
                    string state = dr.GetString(3);

                    result.Add(Tuple.Create(mli, lat, lon, state));
                }
            }

            return result;
        }

        public void StartDebug(string[] args)
        {
            OnStart(args);
            Process(true);
        }

        public void StopDebug()
        {
            OnStop();
        }
    }
}