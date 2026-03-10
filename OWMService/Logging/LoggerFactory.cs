using System;

namespace OWMService.Logging
{
    public static class LoggerFactory
    {
        public static IEventLogger CreateDefaultLogger(string source, string logName)
        {
#if DEBUG
            // In debug builds use console logger (good for local console/debug runs).
            return new ConsoleEventLogger();
#else
            // In release builds use Windows Event Log.
            return new EventLogLogger(source, logName);
#endif
        }
    }
}