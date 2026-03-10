using System;
using System.Diagnostics;

namespace OWMService.Logging
{
    public class NullEventLogger : IEventLogger
    {
        public void LogInfo(string message)
        {
            Console.WriteLine("[INFO] " + message);
        }

        public void LogError(string message)
        {
            Console.WriteLine("[ERROR] " + message);
        }

        public void LogWarning(string message)
        {
            Console.WriteLine("[WARN] " + message);
        }

        public void LogDebug(string message)
        {
            Console.WriteLine("[DEBUG] " + message);
        }

        public void Write(string message, EventLogEntryType entryType = EventLogEntryType.Information)
        {
            // Keep backward compatibility - map to the new methods.
            switch (entryType)
            {
                case EventLogEntryType.Error:
                    LogError(message);
                    break;
                case EventLogEntryType.Warning:
                    LogWarning(message);
                    break;
                case EventLogEntryType.Information:
                default:
                    LogInfo(message);
                    break;
            }
        }
    }
}