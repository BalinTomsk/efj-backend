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

    public abstract class WeatherDataWorkerBase : IWeatherDataWorker
    {
        protected readonly IEventLogger m_logger;
        protected static readonly HttpClient m_httpClient = new HttpClient();
        protected static readonly Regex m_escapeSequenceRegex = new Regex(@"\\""");
        protected const int MinDelayBetweenStationsMs = 12000;

        static WeatherDataWorkerBase()
        {
            // Configure once at static initialization instead of per-request
            ServicePointManager.Expect100Continue = true;
            ServicePointManager.DefaultConnectionLimit = 9999;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        }

        protected WeatherDataWorkerBase(IEventLogger logger)
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

        protected void ProcessEnvData(List<StationData> stations, Settings settings, SqlConnection cnn)
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
                    catch (UnauthorizedAccessException ex)
                    {
                        m_logger.LogError($"OWMService API returned 401 Unauthorized. Stopping processing. {ex.Message}");
                        break;
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

        protected bool ProcessOWSPoint(string mli, float lat, float lon, Settings settings, SqlConnection cnn)
        {
            string url = GetApiUrl(lat, lon, settings);
            string jsonData = ReadJSONOWSData(url);

            if (string.IsNullOrEmpty(jsonData))
            {
                return false;
            }

            return SaveJSONOWSData(jsonData, mli, cnn);
        }

        protected void ProcessFishState(SqlConnection cnn)
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
        /// Returns the SQL query to retrieve weather stations.
        /// </summary>
        protected abstract string GetStationQuery();

        /// <summary>
        /// Returns the weather source type identifier used in ows_meteo.
        /// </summary>
        protected abstract int GetSourceType();

        /// <summary>
        /// Retrieves weather stations from the database using the query from GetStationQuery().
        /// </summary>
        protected List<StationData> GetListOwsMeteo(SqlConnection cnn)
        {
            var result = new List<StationData>();

            using (SqlCommand cmd = new SqlCommand(GetStationQuery(), cnn))
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

        /// <summary>
        /// Builds the weather API URL for the given coordinates.
        /// </summary>
        protected abstract string GetApiUrl(float lat, float lon, Settings settings);

        /// <summary>
        /// Fetches weather JSON data from the given URL.
        /// Throws UnauthorizedAccessException on HTTP 401 to stop processing.
        /// </summary>
        protected string ReadJSONOWSData(string url)
        {
            System.Threading.Thread.Sleep(1000);
            try
            {
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
                request.Method = "GET";
                request.Timeout = 30000;
                request.ReadWriteTimeout = 30000;

                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                {
                    if (response.StatusCode != HttpStatusCode.OK)
                    {
                        m_logger.LogError($"ReadJSONOWSData: HTTP {response.StatusCode}");
                        return "";
                    }

                    using (Stream responseStream = response.GetResponseStream())
                    using (StreamReader reader = new StreamReader(responseStream))
                    {
                        string result = reader.ReadToEnd();
                        result = m_escapeSequenceRegex.Replace(result, "\"");
                        return result;
                    }
                }
            }
            catch (WebException ex) when (ex.Response is HttpWebResponse resp
                && resp.StatusCode == HttpStatusCode.Unauthorized)
            {
                m_logger.LogError($"ReadJSONOWSData: 401 Unauthorized - API key is invalid or expired.");
                throw new UnauthorizedAccessException("API returned 401 Unauthorized.", ex);
            }
            catch (Exception ex)
            {
                m_logger.LogError($"ReadJSONOWSData: {ex.Message}");
            }

            return "";
        }

        /// <summary>
        /// Saves fetched weather JSON data to ows_meteo using the type from GetSourceType().
        /// </summary>
        protected bool SaveJSONOWSData(string jsonData, string mli, SqlConnection cnn)
        {
            if (string.IsNullOrEmpty(jsonData) || string.IsNullOrEmpty(mli) || cnn == null)
            {
                return false;
            }

            using (SqlCommand cmd = new SqlCommand())
            {
                cmd.CommandType = CommandType.Text;
                cmd.Connection = cnn;
                cmd.CommandText = "UPDATE ows_meteo SET type = @type, ows = @js, stamp=GETDATE() WHERE mli = @mli";
                cmd.Parameters.Add("@type", SqlDbType.Int).Value = GetSourceType();
                cmd.Parameters.Add("@js", SqlDbType.NVarChar).Value = jsonData;
                cmd.Parameters.Add("@mli", SqlDbType.VarChar).Value = mli;

                try
                {
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