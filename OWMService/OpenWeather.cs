using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Linq;
using System.ServiceProcess;
using System.Text;
using System.IO;
using System.Xml;
using System.Threading.Tasks;
using System.Timers;
using System.Data.SqlClient;
using System.Net.Mail;
using Microsoft.Win32;
using System.Net;
using System.Web;
using System.Net.Http;
using System.Runtime.InteropServices.WindowsRuntime;

namespace OWMService
{
    public partial class RWS : ServiceBase
    {
        public string readJSONOWSData(float lat, float lon)
        {
            try
            {
                // download data  WebClient  DownloadData
                 string url = String.Format(@"https://api.weather.com/v3/wx/forecast/daily/5day?geocode={0},{1}&format=json&units=e&language=en-US&apiKey={2}"
                                            , lat, lon, m_wunderground);
                //string file = System.IO.Path.GetFileName(url);

                ServicePointManager.Expect100Continue = true;
                ServicePointManager.DefaultConnectionLimit = 9999;
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | SecurityProtocolType.Ssl3 | SecurityProtocolType.Tls;

                using (WebClient cln = new WebClient())
                {
                    cln.Headers.Add("User-Agent: Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:48.0) Gecko/20100101 Firefox/48.0");
                    cln.Encoding = UTF8Encoding.UTF8;

                    byte[] data = cln.DownloadData(url);

                    string result = System.Text.UTF8Encoding.UTF8.GetString(data);
                    result = result.Replace('\"', '"');
                    string slash = string.Format("{0}{1}", '\\', '"');
                    string da = string.Format("{0}", '"');
                    result = result.Replace(slash, da);
                    return result;
                }
            }
            catch (Exception ex)
            {
                eventLogRN.WriteEntry("readJSONOWSData: " + ex.Message, EventLogEntryType.Error);
            }
            return "";
        }
        /// <summary>
        /// Post processing fish probability data
        /// </summary>
        /// <param name="cnn"></param>
        void ProcessFishState(SqlConnection cnn)
        {
            if ( null == cnn)
            {
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
                catch (Exception ex)
                {
                    eventLogRN.WriteEntry("SaveJSONOWSData: " + ex.Message, EventLogEntryType.Error);
                }
            }
            return;
        }
        /// <summary>
        /// save JSON file with weather info from wunderground to database for postprocessing
        /// </summary>
        /// <param name="jsonData"></param>
        /// <param name="mli"></param>
        /// <param name="cnn"></param>
        /// <returns></returns>
        bool SaveJSONOWSData(string jsonData, string mli, SqlConnection cnn)
        {
            if( String.IsNullOrEmpty(jsonData) || String.IsNullOrEmpty(mli) || null == cnn )
            {
                return false;
            }
            using (SqlCommand cmd = new SqlCommand())
            {
                cmd.CommandType = CommandType.Text;
                cmd.Connection = cnn;
                cmd.CommandText = "UPDATE ows_meteo SET ows = @js WHERE mli = @mli";
                cmd.Parameters.Add("@js",   SqlDbType.NVarChar);
                cmd.Parameters.Add("@mli",  SqlDbType.VarChar);
                try
                {
                    cmd.Parameters[0].Value = jsonData;
                    cmd.Parameters[1].Value = mli;

                    cmd.ExecuteNonQuery();
                }
                catch (Exception ex)
                {
                    eventLogRN.WriteEntry("SaveJSONOWSData: " + ex.Message, EventLogEntryType.Error);
                    return false;
                }
            }
            return true;
        }
        /// <summary>
        /// get weather data from wunderground
        /// save JSON file to database for prostprocessing
        /// </summary>
        /// <param name="mli"></param>
        /// <param name="lat"></param>
        /// <param name="lon"></param>
        /// <param name="cnn"></param>
        /// <returns></returns>
        public bool ProcessOWSPoint( string mli, float lat, float lon, SqlConnection cnn )
        {
            string jsonData = readJSONOWSData(lat, lon);        // get weather data from wunderground
            System.Threading.Thread.Sleep(1024 * 1);

            if( String.IsNullOrEmpty(jsonData))
            {
                return false;
            }
            return SaveJSONOWSData(  jsonData, mli, cnn);       // save JSON file to database for prostprocessing
        }
    }
}