using System;

namespace OWMService.Config
{
    public class Settings
    {
        // Defaults preserved from original RWS fields
        public string Server { get; set; } = Environment.MachineName;
        public string DbName { get; set; } = "fishfind";
        public string UserName { get; set; } = "superadmin";
        public string UserPassword { get; set; } = "superpassword";
        public string Wunderground { get; set; } = "weather APi Key"; // https://preview.wunderground.com/member/api-keys
        public int Interval { get; set; }

        public string GetConnectionString()
        {
            // Keep same formatting as original RWS.GetConnectionString
            return string.Format(
                @"Data Source={0};Initial Catalog={1};Integrated Security=False;User ID={2};Password={3}",
                Server,
                DbName,
                UserName,
                UserPassword);
        }
    }
}