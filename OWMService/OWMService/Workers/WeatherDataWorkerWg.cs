namespace OWMService.Workers
{
    using OWMService.Config;
    using OWMService.Logging;

    public class WeatherDataWorkerWg : WeatherDataWorkerBase
    {
        public WeatherDataWorkerWg(IEventLogger logger) : base(logger)
        {
        }

        protected override string GetStationQuery()
        {
            return "select TOP 1000 mli, lat, lon, state from dbo.vwWeatherForecastToDay WHERE sid % 2 = 1 ORDER BY stamp ASC";
        }

        /// <summary>
        ///   Weather Underground  https://www.wunderground.com/
        ///   https://www.wunderground.com/member/api-keys
        /// </summary>
        protected override string GetApiUrl(float lat, float lon, Settings settings)
        {
            return $"https://api.weather.com/v3/wx/forecast/daily/5day?geocode={lat},{lon}&format=json&units=e&language=en-US&apiKey={settings.Wunderground}";
        }

        protected override int GetSourceType()
        {
            return 1;
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