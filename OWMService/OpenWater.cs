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
        static HashSet<string> canadaStates = new HashSet<string>() { "AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE", "QC", "SK", "YT" }; 
        
        public string ProcessWaterData(string mli, float lat, float lon, string state, SqlConnection cnn)
        {
            try
            {
                bool isCanada = canadaStates.Contains(state);
                string web = System.Diagnostics.Debugger.IsAttached ? "localhost:32543" : "fishfind.info";
                // download data  WebClient  DownloadData
                string url = String.Format(@"http://{3}/WebService/PushStation{2}.aspx?mli={0}&state={1}", mli, state, !isCanada, web);

                using (WebClient cln = new WebClient())
                {
                    cln.Headers.Add("User-Agent: Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:48.0) Gecko/20100101 Firefox/48.0");
                    cln.Encoding = UTF8Encoding.UTF8;

                    string result = cln.DownloadString(url);

                    return result;
                }
            }
            catch (Exception ex)
            {
                eventLogRN.WriteEntry("readJSONOWSData: " + ex.Message, EventLogEntryType.Error);
            }
            return "";
        }
    }
}