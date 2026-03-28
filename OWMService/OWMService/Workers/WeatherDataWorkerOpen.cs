namespace OWMService.Workers
{
    using OWMService.Config;
    using OWMService.Logging;
    using System;
    using System.Collections.Generic;
    using System.Data;
    using System.Data.SqlClient;
    using System.Diagnostics;
    using System.IO;
    using System.Net;
    using System.Net.Http;
    using System.Text.RegularExpressions;
    using System.Threading.Tasks;
    using Newtonsoft.Json.Linq;

    public class WeatherDataWorkerOpen : IWeatherDataWorker
    {
        private readonly IEventLogger m_logger;
        private static readonly HttpClient m_httpClient = new HttpClient();
        private static readonly Regex m_escapeSequenceRegex = new Regex(@"\\""");
        private const int MinDelayBetweenStationsMs = 12000;

        static WeatherDataWorkerOpen()
        {
            // Configure once at static initialization instead of per-request
            ServicePointManager.Expect100Continue = true;
            ServicePointManager.DefaultConnectionLimit = 9999;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        }

        public WeatherDataWorkerOpen(IEventLogger logger)
        {
            m_logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public bool Process(Settings settings)
        {
            string conStr = settings.GetConnectionString();
            if (string.IsNullOrEmpty(conStr))
            {
                return false;
            }

            try
            {
                using (SqlConnection cnn = new SqlConnection(conStr))
                {
                    cnn.Open();

                    List<StationData> stations = GetListOwsMeteo(cnn);
                    m_logger.LogInfo($"Get {stations.Count} OWS stations.");

                    ProcessEnvData(stations, settings, cnn);
                    m_logger.LogInfo($"Read all {stations.Count} OWS stations.");

                    ProcessFishState(cnn);
                    m_logger.LogInfo($"Updated all {stations.Count} OWS/Fish related data.");

                    m_logger.LogInfo("Full loop completed. Waiting 10 hours before next loop.");
                    System.Threading.Thread.Sleep(TimeSpan.FromHours(1));

                    return true;
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OWMService Failed to connect. {ex.Message} at: {conStr}");
                return false;
            }
        }

        private void ProcessEnvData(List<StationData> stations, Settings settings, SqlConnection cnn)
        {
            try
            {
                int i = 0;

                foreach (var item in stations)
                {
                    Stopwatch sw = Stopwatch.StartNew();

                    try
                    {
                        ProcessOWSPoint(item.Mli, item.Latitude, item.Longitude, settings, cnn);
                        i++;
                    }
                    catch (Exception ex)
                    {
                        m_logger.LogError($"OWMService station processing failed. {ex.Message} MLI: {item.Mli} at: {i}");
                    }
                    finally
                    {
                        sw.Stop();
                        int remainingDelay = MinDelayBetweenStationsMs - (int)sw.ElapsedMilliseconds;
                        if (remainingDelay > 0)
                        {
                            System.Threading.Thread.Sleep(remainingDelay);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OWMService Failed in ProcessEnvData. {ex.Message}");
            }
        }

        /// <summary>
        /// Retrieves weather stations from the database
        /// </summary>
        private List<StationData> GetListOwsMeteo(SqlConnection cnn)
        {
            var result = new List<StationData>();

            using (SqlCommand cmd = new SqlCommand(
                "select mli, lat, lon, state from dbo.vwWeatherForecastToDay", cnn))
            using (SqlDataReader dr = cmd.ExecuteReader())
            {
                while (dr.Read())
                {
                    string mli = dr.GetString(0);
                    float lat = (float)dr.GetDouble(1);
                    float lon = (float)dr.GetDouble(2);
                    string state = dr.GetString(3);

                    result.Add(new StationData { Mli = mli, Latitude = lat, Longitude = lon, State = state });
                }
            }

            return result;
        }

        private bool ProcessOWSPoint(string mli, float lat, float lon, Settings settings, SqlConnection cnn)
        {
            string jsonData = ReadJSONOWSData(lat, lon, settings);

            if (string.IsNullOrEmpty(jsonData))
            {
                return false;
            }

            return SaveJSONOWSData(jsonData, mli, cnn);
        }

        private void ProcessFishState(SqlConnection cnn)
        {
            using (SqlCommand cmd = new SqlCommand())
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Connection = cnn;
                cmd.CommandTimeout = 300; // 5 minutes timeout

                try
                {
                    cmd.CommandText = "spPushSpeciesFromLakeToStation";
                    cmd.ExecuteNonQuery();

                    cmd.CommandText = "spTotalUpdateProbability";
                    cmd.ExecuteNonQuery();  // 2 mins
                }
                catch (Exception ex)
                {
                    m_logger.LogError($"ProcessFishState: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Fetches weather data from Open-Meteo API
        /// https://api.open-meteo.com/v1/forecast?latitude=43.45&longitude=-80.49&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,wind_speed_10m,wind_direction_10m,weather_code,rain&daily=temperature_2m_max,temperature_2m_min&timezone=auto 
        /// </summary>
        private string ReadJSONOWSData(float lat, float lon, Settings settings)
        {
            System.Threading.Thread.Sleep(1000);
            try
            {
                string url = $"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
                    + "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,"
                    + "wind_speed_10m,wind_direction_10m,weather_code,rain&daily=temperature_2m_max,temperature_2m_min&timezone=auto";

                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
                request.Method = "GET";
                request.Timeout = 30000;
                request.ReadWriteTimeout = 30000;

                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                {
                    System.Threading.Thread.Sleep(100);

                    if (response.StatusCode != HttpStatusCode.OK)
                    {
                        m_logger.LogError($"ReadJSONOWSData: HTTP {response.StatusCode}");
                        return "";
                    }

                    using (Stream responseStream = response.GetResponseStream())
                    using (StreamReader reader = new StreamReader(responseStream))
                    {
                        string result = reader.ReadToEnd();
                        return result;
                    }
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"ReadJSONOWSData: {ex.Message}");
            }

            return "";
        }

        /// <summary>
        /// saved into ows_meteo trigger on it parses Open-Meteo API JSON response and inserts weather data into weather_Forecast table
        /// </summary>
        private bool SaveJSONOWSData(string jsonData, string mli, SqlConnection cnn)
        {
            if (string.IsNullOrEmpty(jsonData) || string.IsNullOrEmpty(mli) || cnn == null)
            {
                return false;
            }

            using (SqlCommand cmd = new SqlCommand())
            {
                cmd.CommandType = CommandType.Text;
                cmd.Connection = cnn;
                cmd.CommandText = "UPDATE ows_meteo SET type = 2, ows = @js, stamp=GETDATE() WHERE mli = @mli";
                cmd.Parameters.Add("@js", SqlDbType.NVarChar);
                cmd.Parameters.Add("@mli", SqlDbType.VarChar);

                try
                {
                    cmd.Parameters[0].Value = jsonData;
                    cmd.Parameters[1].Value = mli;

                    cmd.ExecuteNonQuery();
                }
                catch (Exception ex)
                {
                    m_logger.LogError($"SaveJSONOWSData: {ex.Message}");
                    return false;
                }
            }

            m_logger.LogInfo($"Processed {mli} station.");
            return true;
        }
    }
}