using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Diagnostics;
using System.ServiceProcess;
using System.Timers;

namespace OWMService
{
    public partial class RWS : ServiceBase
    {
        private const string EventSourceName = "OWMService";
        private const string EventLogName = "Application";

        private System.Timers.Timer m_timer;
        private EventLog eventLogRN;

        private double m_servicePollInterval;
        private string m_serverName = Environment.MachineName;
        private string m_dbName = "fishfind";
        private string m_userName = "superadmin";
        private string m_userPassword = "superpassword";
        private string m_wunderground = "weather APi Key";  // https://preview.wunderground.com/member/api-keys

        private bool m_bFlagProcessing = true;
        private const string NullGuid = "00000000-0000-0000-0000-000000000000";

        public RWS()
        {
            InitializeComponent();

            InitializeEventLog();
        }

        private bool ReadSettings()
        {
            const string subKey = @"SOFTWARE\FishFind\OWMService";

            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
                using var key = baseKey.OpenSubKey(subKey);

                if (key == null)
                {
                    Log("Cannot open registry key: HKLM\\" + subKey, EventLogEntryType.Error);
                    return false;
                }

                m_serverName = key.GetValue("Server") as string;
                if (string.IsNullOrWhiteSpace(m_serverName))
                {
                    Log("Cannot read MSSQL Server Name", EventLogEntryType.Error);
                    m_servicePollInterval = 100;
                    return false;
                }

                m_dbName = key.GetValue("dbName") as string;
                if (string.IsNullOrWhiteSpace(m_dbName))
                {
                    Log("Cannot read MSSQL Server Db Name", EventLogEntryType.Error);
                    return false;
                }

                m_userName = key.GetValue("userName") as string;
                m_userPassword = key.GetValue("userPassword") as string;
                m_wunderground = key.GetValue("wunderground") as string;

                object intervalValue = key.GetValue("Interval");
                if (intervalValue != null)
                {
                    m_servicePollInterval = Convert.ToInt32(intervalValue);
                }

                return true;
            }
            catch (Exception ex)
            {
                Log("ReadSettings failed: " + ex.Message, EventLogEntryType.Error);
                return false;
            }
        }
        private void InitializeEventLog()
        {
            try
            {
                if (!EventLog.SourceExists(EventSourceName))
                {
                    EventLog.CreateEventSource(EventSourceName, EventLogName);
                }

                eventLogRN = new EventLog();
                eventLogRN.Source = EventSourceName;
                eventLogRN.Log = EventLogName;
            }
            catch (Exception ex)
            {
                Console.WriteLine("Failed to initialize Windows Event Log: " + ex.Message);
            }
        }

        protected override void OnStart(string[] args)
        {
            Log("OWMService started.");

            if (!ReadSettings())
            {
                return;
            }

            m_timer = new System.Timers.Timer();
            m_timer.Interval = 10000;
            m_timer.Elapsed += TimerElapsed;
            m_timer.AutoReset = true;
            m_timer.Start();
        }

        protected override void OnStop()
        {
            Console.WriteLine("OWMService stopped.");

            Log("OWMService stopped.");
            m_bFlagProcessing = true;

            if (m_timer != null)
            {
                m_timer.Stop();
                m_timer.Dispose();
                m_timer = null;
            }
        }
        protected override void OnContinue()
        {
            m_bFlagProcessing = false;
            eventLogRN.WriteEntry("OWMService OnContinue.");
        }

        protected override void OnShutdown()
        {
            m_bFlagProcessing = true;
            m_timer.Stop();
            eventLogRN.WriteEntry("OWMService OnShutdown.");
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
                Log("OWMService running at " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
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

                    m_timer.Interval = 1000 * 60 * 2;
                    return true;
                }
            }
            catch (Exception ex)
            {
                eventLogRN.WriteEntry("OWMService Failed to connect. " + ex.Message + " at: " + conStr, EventLogEntryType.Error);
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
                        eventLogRN.WriteEntry(
                            "OWMService station processing failed. " + ex.Message + " MLI: " + item.Item1 + " at: " + i,
                            EventLogEntryType.Error);
                    }
                }
            }
            catch (Exception ex)
            {
                eventLogRN.WriteEntry("OWMService Failed in ProcessEnvData. " + ex.Message, EventLogEntryType.Error);
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
        private void Log(string message, EventLogEntryType entryType = EventLogEntryType.Information)
        {
            Console.WriteLine(message);

            try
            {
                if (eventLogRN != null)
                {
                    eventLogRN.WriteEntry(message, entryType);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Failed to write to Windows Event Log: " + ex.Message);
            }
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