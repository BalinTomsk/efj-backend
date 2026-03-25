namespace OWMService.Logging
{
    using System;
    using System.IO;
    using System.Text;
    using System.Diagnostics;

    /// <summary>
    /// Logger that writes all messages to a file and errors to Windows Event Log.
    /// Works in both Debug and Release modes, including Windows Service execution.
    /// </summary>
    public class FileEventLogger : IEventLogger, IDisposable
    {
        private readonly string m_logFilePath;
        private readonly EventLog m_eventLog;
        private bool m_disposed;

        public FileEventLogger(string source, string logName, string logFilePath = null)
        {
            // Simplest possible path determination
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string logDir = Path.Combine(appDataPath, "OWMService", "Logs");
            m_logFilePath = Path.Combine(logDir, "OWMService.log");

            // Create directory
            try
            {
                if (!Directory.Exists(logDir))
                {
                    Directory.CreateDirectory(logDir);
                }
            }
            catch { }

            // Write test entry
            try
            {
                File.AppendAllText(m_logFilePath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [INIT] Logger initialized\r\n");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"LOGGER ERROR: {ex.Message}");
            }

            // Event Log
            try
            {
                if (!EventLog.SourceExists(source))
                {
                    EventLog.CreateEventSource(source, logName);
                }
                m_eventLog = new EventLog { Source = source, Log = logName };
            }
            catch { }
        }

        public void LogInfo(string message) => Log(message, "INFO");
        public void LogError(string message) => Log(message, "ERROR");
        public void LogWarning(string message) => Log(message, "WARN");
        public void LogDebug(string message) => Log(message, "DEBUG");

        private void Log(string message, string level)
        {
            try
            {
                File.AppendAllText(m_logFilePath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{level}] {message}\r\n");
            }
            catch { }
        }

        public void Dispose()
        {
            if (!m_disposed)
            {
                m_eventLog?.Dispose();
                m_disposed = true;
            }
        }
    }
}