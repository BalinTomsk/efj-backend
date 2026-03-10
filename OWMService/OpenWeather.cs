using System;
using System.Data;
using System.Diagnostics;
using System.ServiceProcess;
using System.Text;
using System.Data.SqlClient;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;

namespace OWMService
{
    public partial class RWS : ServiceBase
    {
        private static readonly HttpClient HttpClient = new HttpClient();
        private const int WeatherApiDelayMs = 1024;

        public async Task<string> ReadJSONOWSDataAsync(float lat, float lon)
        {
            try
            {
                string url = $"https://api.weather.com/v3/wx/forecast/daily/5day?geocode={lat},{lon}&format=json&units=e&language=en-US&apiKey={m_settings.Wunderground}";

                HttpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:48.0) Gecko/20100101 Firefox/48.0");

                using (HttpResponseMessage response = await HttpClient.GetAsync(url))
                {
                    if (!response.IsSuccessStatusCode)
                    {
                        m_logger.LogError($"Weather API returned status code: {response.StatusCode}");
                        return string.Empty;
                    }

                    string result = await response.Content.ReadAsStringAsync();
                    return result;
                }
            }
            catch (HttpRequestException ex)
            {
                m_logger.LogError($"ReadJSONOWSDataAsync - HTTP Error: {ex.Message}");
            }
            catch (Exception ex)
            {
                m_logger.LogError($"ReadJSONOWSDataAsync - Unexpected Error: {ex.Message}");
            }
            return string.Empty;
        }

        /// <summary>
        /// Post processing fish probability data
        /// </summary>
        /// <param name="cnn"></param>
        void ProcessFishState(SqlConnection cnn)
        {
            if (cnn == null)
            {
                m_logger.LogError("ProcessFishState: Connection is null");
                return;
            }

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
                catch (SqlException ex)
                {
                    m_logger.LogError($"ProcessFishState - SQL Error: {ex.Message}");
                }
                catch (Exception ex)
                {
                    m_logger.LogError($"ProcessFishState - Unexpected Error: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Save JSON file with weather info from wunderground to database for postprocessing
        /// </summary>
        /// <param name="jsonData"></param>
        /// <param name="mli"></param>
        /// <param name="cnn"></param>
        /// <returns></returns>
        bool SaveJSONOWSData(string jsonData, string mli, SqlConnection cnn)
        {
            if (string.IsNullOrEmpty(jsonData) || string.IsNullOrEmpty(mli) || cnn == null)
            {
                m_logger.LogError("SaveJSONOWSData: Invalid parameters provided");
                return false;
            }

            using (SqlCommand cmd = new SqlCommand("UPDATE ows_meteo SET ows = @js WHERE mli = @mli", cnn))
            {
                cmd.CommandType = CommandType.Text;
                cmd.Parameters.Add("@js", SqlDbType.NVarChar).Value = jsonData;
                cmd.Parameters.Add("@mli", SqlDbType.VarChar).Value = mli;

                try
                {
                    cmd.ExecuteNonQuery();
                    return true;
                }
                catch (SqlException ex)
                {
                    m_logger.LogError($"SaveJSONOWSData - SQL Error: {ex.Message}");
                    return false;
                }
                catch (Exception ex)
                {
                    m_logger.LogError($"SaveJSONOWSData - Unexpected Error: {ex.Message}");
                    return false;
                }
            }
        }

        /// <summary>
        /// Get weather data from wunderground
        /// Save JSON file to database for postprocessing
        /// </summary>
        /// <param name="mli"></param>
        /// <param name="lat"></param>
        /// <param name="lon"></param>
        /// <param name="cnn"></param>
        /// <returns></returns>
        public async Task<bool> ProcessOWSPointAsync(string mli, float lat, float lon, SqlConnection cnn)
        {
            if (cnn == null)
            {
                m_logger.LogError("ProcessOWSPointAsync: Connection is null");
                return false;
            }

            string jsonData = await ReadJSONOWSDataAsync(lat, lon);

            if (string.IsNullOrEmpty(jsonData))
            {
                m_logger.LogError("ProcessOWSPointAsync: No weather data received");
                return false;
            }

            await Task.Delay(WeatherApiDelayMs);

            return SaveJSONOWSData(jsonData, mli, cnn);
        }
    }
}