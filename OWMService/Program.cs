using System;
using System.Diagnostics;
using System.ServiceProcess;

namespace OWMService
{
    internal static class Program
    {
        static void Main(string[] args)
        {
            if (Environment.UserInteractive || Debugger.IsAttached)
            {
                var service = new RWS();

                service.StartDebug(args);

                Console.WriteLine("OWMService is running in debug mode.");
                Console.WriteLine("Press Enter to stop...");
                Console.ReadLine();

                service.StopDebug();
            }
            else
            {
                ServiceBase.Run(new ServiceBase[]
                {
                    new RWS()
                });
            }
        }
    }
}