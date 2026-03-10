namespace OWMService.Workers
{
    using OWMService.Config;
    using OWMService.Logging;
    using System;
    using System.Collections.Generic;
    using System.Data;
    using System.Data.SqlClient;
    using System.Net;
    using System.Net.Http;
    using System.Text.RegularExpressions;
    using System.Threading.Tasks;
 
    public class WeatherDataWorker : IWeatherDataWorker
    {
        private readonly IEventLogger m_logger;
        private static readonly HttpClient m_httpClient = new HttpClient();
        private static readonly Regex m_escapeSequenceRegex = new Regex(@"\\""");

        static WeatherDataWorker()
        {
            // Configure once at static initialization instead of per-request
            ServicePointManager.Expect100Continue = true;
            ServicePointManager.DefaultConnectionLimit = 9999;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        }

        public WeatherDataWorker(IEventLogger logger)
        {
            m_logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public bool Process(Settings settings)
        {
            return ProcessAsync(settings).GetAwaiter().GetResult();
        }

        public async Task<bool> ProcessAsync(Settings settings)
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

                    await ProcessEnvDataAsync(stations, settings, cnn);
                    m_logger.LogInfo("Read all OWS stations.");

                    ProcessFishState(cnn);
                    m_logger.LogInfo("Updated all OWS/Fish related data.");

                    return true;
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OWMService Failed to connect. {ex.Message} at: {conStr}");
                return false;
            }
        }

        private async Task ProcessEnvDataAsync(List<StationData> stations, Settings settings, SqlConnection cnn)
        {
            try
            {
                int i = 0;

                foreach (var item in stations)
                {
                    try
                    {
                        await ProcessOWSPointAsync(item.Mli, item.Latitude, item.Longitude, settings, cnn);
                        i++;
                    }
                    catch (Exception ex)
                    {
                        m_logger.LogError($"OWMService station processing failed. {ex.Message} MLI: {item.Mli} at: {i}");
                    }
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"OWMService Failed in ProcessEnvData. {ex.Message}");
            }
        }

        private List<StationData> GetListOwsMeteo(SqlConnection cnn)
        {
            var result = new List<StationData>();

            using (SqlCommand cmd = new SqlCommand(
                "select top 100 mli, lat, lon, state from WaterStation w where exists (select * from lake_fish f where f.lake_Id = w.lakeId)", cnn))
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

        private async Task<bool> ProcessOWSPointAsync(string mli, float lat, float lon, Settings settings, SqlConnection cnn)
        {
            string jsonData = await ReadJSONOWSDataAsync(lat, lon, settings);

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

                try
                {
                    cmd.CommandText = "spPushSpeciesFromLakeToStation";
                    cmd.ExecuteNonQuery();

                    cmd.CommandText = "spTotalUpdateProbability";
                    cmd.ExecuteNonQuery();
                }
                catch (Exception ex)
                {
                    m_logger.LogError($"ProcessFishState: {ex.Message}");
                }
            }
        }

        private async Task<string> ReadJSONOWSDataAsync(float lat, float lon, Settings settings)
        {
            try
            {
                string url = $"https://api.weather.com/v3/wx/forecast/daily/5day?geocode={lat},{lon}&format=json&units=e&language=en-US&apiKey={settings.Wunderground}";

                using (HttpResponseMessage response = await m_httpClient.GetAsync(url))
                {
                    if (!response.IsSuccessStatusCode)
                    {
                        m_logger.LogError($"ReadJSONOWSData: HTTP {response.StatusCode}");
                        return "";
                    }

                    string result = await response.Content.ReadAsStringAsync();
                    
                    // Optimize escape sequence removal: use regex instead of multiple Replace calls
                    result = m_escapeSequenceRegex.Replace(result, "\"");

                    return result;
                }
            }
            catch (Exception ex)
            {
                m_logger.LogError($"ReadJSONOWSData: {ex.Message}");
            }

            return "";
        }

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
                cmd.CommandText = "UPDATE ows_meteo SET ows = @js WHERE mli = @mli";
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

            return true;
        }
    }

    public class StationData
    {
        public string Mli { get; set; }
        public float Latitude { get; set; }
        public float Longitude { get; set; }
        public string State { get; set; }
    }
}