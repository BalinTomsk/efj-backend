namespace OWMService.Workers
{
    using OWMService.Config;
    using OWMService.Logging;

    public class WeatherDataWorkerOpen : WeatherDataWorkerBase
    {
        public WeatherDataWorkerOpen(IEventLogger logger) : base(logger)
        {
        }

        protected override string GetStationQuery()
        {
            return "select TOP 1400 mli, lat, lon, state from dbo.vwWeatherForecastToDay WHERE sid % 2 = 0 ORDER BY CHECKSUM(NEWID(), sid)";
        }

        /// <summary>
        /// Open-Meteo API URL
        /// https://api.open-meteo.com/v1/forecast?latitude=43.45&longitude=-80.49&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,wind_speed_10m,wind_direction_10m,weather_code,rain&daily=temperature_2m_max,temperature_2m_min&timezone=auto 
        /// </summary>
        protected override string GetApiUrl(float lat, float lon, Settings settings)
        {
            return $"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
                + "&hourly=temperature_2m,relative_humidity_2m,precipitation_probability,pressure_msl,"
                + "wind_speed_10m,wind_direction_10m,weather_code,rain&daily=temperature_2m_max,temperature_2m_min&timezone=auto";
        }

        protected override int GetSourceType()
        {
            return 2;
        }
    }
}