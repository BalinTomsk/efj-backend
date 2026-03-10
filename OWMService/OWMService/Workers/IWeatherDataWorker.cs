namespace OWMService.Workers
{
    using OWMService.Config;

    public interface IWeatherDataWorker
    {
        bool Process(Settings settings);
    }
}