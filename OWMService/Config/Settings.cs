using System;

namespace OWMService.Config
{
    public class Settings
    {
        public string Server { get; set; }
        public string DbName { get; set; }
        public string UserName { get; set; }
        public string UserPassword { get; set; }
        public string Wunderground { get; set; }
        public int Interval { get; set; }
    }
}