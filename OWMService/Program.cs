using OWMService.Config;
using OWMService.Logging;
using System;
using System.Configuration;
using System.Diagnostics;
using System.ServiceProcess;

namespace OWMService
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // Read configuration from App.config
            string eventLogSource = ConfigurationManager.AppSettings["EventLogSource"] ?? "OWMService";
            string eventLogName = ConfigurationManager.AppSettings["EventLogName"] ?? "Application";
            string logFilePath = ConfigurationManager.AppSettings["LogFilePath"];

            // Create logger instance
            IEventLogger logger = LoggerFactory.CreateDefaultLogger(
                eventLogSource, 
                eventLogName, 
                string.IsNullOrEmpty(logFilePath) ? null : logFilePath
            );

            try
            {
                logger.LogInfo("OWMService starting...");
                
                if (Environment.UserInteractive || Debugger.IsAttached)
                {
                    var service = new RWS(logger);

                    logger.LogInfo("Starting service in debug mode...");
                    service.StartDebug(args);

                    Console.WriteLine("OWMService is running in debug mode.");
                    Console.WriteLine("Press Enter to stop...");
                    Console.ReadLine();

                    service.StopDebug();
                    logger.LogInfo("Service stopped in debug mode.");
                }
                else
                {
                    ServiceBase.Run(new ServiceBase[]
                    {
                        new RWS(logger)
                    });
                }
            }
            catch (Exception ex)
            {
                logger.LogError($"Fatal error: {ex}");
                Console.WriteLine($"Fatal error: {ex.Message}");
            }
            finally
            {
                (logger as IDisposable)?.Dispose();
            }
        }
    }
}