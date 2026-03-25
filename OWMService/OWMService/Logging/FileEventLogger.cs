namespace OWMService.Logging
{
    using System;
    using System.Diagnostics;
    using System.IO;
    using System.Text;

    /// <summary>
    /// Logger that writes all messages to a file and errors to Windows Event Log.
    /// </summary>
    public class FileEventLogger : IEventLogger, IDisposable
    {
        private readonly string m_logFilePath;
        private readonly EventLog m_eventLog;
        private readonly object m_lockObj = new object();
        private bool m_disposed;

        public FileEventLogger(string source, string logName, string logFilePath = null)
        {
            // Set default log file path if not provided
            if (string.IsNullOrEmpty(logFilePath))
            {
                string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string logDirectory = Path.Combine(appDataPath, "OWMService", "Logs");
                
                if (!Directory.Exists(logDirectory))
                {
                    Directory.CreateDirectory(logDirectory);
                }

                m_logFilePath = Path.Combine(logDirectory, "OWMService.log");
            }
            else
            {
                m_logFilePath = logFilePath;
                string directory = Path.GetDirectoryName(m_logFilePath);
                if (!Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }
            }

            // Initialize Windows Event Log for errors only
            try
            {
                if (!EventLog.SourceExists(source))
                {
                    EventLog.CreateEventSource(source, logName);
                }

                m_eventLog = new EventLog
                {
                    Source = source,
                    Log = logName
                };
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to initialize Windows Event Log: {ex.Message}");
                m_eventLog = null;
            }
        }

        public void LogInfo(string message)
        {
            WriteToFile(message, "INFO");
        }

        public void LogError(string message)
        {
            WriteToFile(message, "ERROR");
            WriteToEventLog(message, EventLogEntryType.Error);
        }

        public void LogWarning(string message)
        {
            WriteToFile(message, "WARN");
        }

        public void LogDebug(string message)
        {
            WriteToFile(message, "DEBUG");
        }

        private void WriteToFile(string message, string level)
        {
            lock (m_lockObj)
            {
                try
                {
                    string logEntry = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [{level}] {message}{Environment.NewLine}";
                    
                    File.AppendAllText(m_logFilePath, logEntry, Encoding.UTF8);
                }
                catch (Exception ex)
                {
                    // Fallback to console if file writing fails
                    Console.WriteLine($"[{level}] {message}");
                    Console.WriteLine($"Failed to write to log file: {ex.Message}");
                }
            }
        }

        private void WriteToEventLog(string message, EventLogEntryType entryType)
        {
            if (m_eventLog == null)
            {
                return;
            }

            try
            {
                m_eventLog.WriteEntry(message, entryType);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to write to Windows Event Log: {ex.Message}");
            }
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