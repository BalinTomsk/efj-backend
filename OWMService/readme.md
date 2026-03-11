# OWMService

I. OWMService is a Windows Service that periodically retrieves weather data and updates the FishFind database.


1.  OWMService  service read list of water state station from:  select top 100 mli, lat, lon, state from [WaterStation] w where exists (select * from lake_fish f where f.lake_Id = w.lakeId)
2.  Read from wheater as json for this  WaterStation cloest weather:  "https://api.weather.com/v3/wx/forecast/daily/5day?geocode={lat},{lon}&format=json&units=e&language=en-US&apiKey={settings.Wunderground}";
3.  save this json into UPDATE [ows_meteo] SET ows = @js WHERE mli = @mli"
4.  trigger [ows_meteo] on TR_ows_meteo  run EXEC sp_ows_meteo @json, @mli, @WaterStation_id
5.  sp_ows_meteo parses passed json and update/merge data into [weather_Forecast] 
6.  execute spPushSpeciesFromLakeToStation -> push fishes from lakes to station place    insert dbo.fish_location (station_Id, fish_Id, probability, today ) 
7.  execute spTotalUpdateProbability    -> update fish probability


II. Water Data State
 1. 
 2. 

---

# Requirements

* Windows 10 / Windows 11 / Windows Server
* .NET Framework (version used by the project, typically **4.7.2 or 4.8**)
* Administrator privileges to install the service
* SQL Server access configured in the registry in \fishfind-backend\OWMService\Res\OWMService.reg 

---

# Build

Open the solution in **Visual Studio 2022**.

Build the project:

```
Build → Build Solution
```

The executable will be generated in:

```
bin\Release\OWMService.exe
```

or

```
bin\Debug\OWMService.exe
```

---

# Configuration

The service reads configuration from the Windows Registry:

```
HKEY_LOCAL_MACHINE\SOFTWARE\FishFind\OWMService
```

Expected values:

| Name         | Description                 |
| ------------ | --------------------------- |
| Server       | SQL Server hostname         |
| dbName       | Database name               |
| userName     | SQL login                   |
| userPassword | SQL password                |
| wunderground | Weather API key             |
| Interval     | Polling interval in minutes |

---

# Install / Register the Service

Open **Command Prompt as Administrator**.

Run:

```
sc create OWMService binPath= "C:\Path\To\OWMService.exe"
```

Example:

```
sc create OWMService binPath= "C:\Services\OWMService\OWMService.exe"
```

---

# Start the Service

```
sc start OWMService
```

or via **Services Manager**:

```
services.msc
```

Find **OWMService** and click **Start**.

---

# Stop the Service

```
sc stop OWMService
```

---

# Deregister / Remove the Service

Stop the service first:

```
sc stop OWMService
```

Then delete it:

```
sc delete OWMService
```

---

# Debugging (Console Mode)

When running inside Visual Studio, the service can run in **console mode** for debugging.

Start with **F5**.

The application will run as a console:

```
Press Enter to stop...
```

This allows:

* breakpoints
* console logging
* easier debugging of service startup logic

---

# Logs

The service writes events to the Windows Event Log:

```
Event Viewer
Windows Logs
Application
Source: OWMService
```

---

# Folder Layout

```
OWMService
│
├─ Program.cs
├─ RWS.cs
├─ RWS.Designer.cs
├─ ProjectInstaller.cs
├─ App.config
└─ README.md
```

---

# Troubleshooting

### Service fails to start

Check:

```
Event Viewer → Windows Logs → Application
```

Look for entries from **OWMService**.

---

### Database connection errors

Verify registry values:

```
HKEY_LOCAL_MACHINE\SOFTWARE\FishFind\OWMService
```

---

### Service not installing

Ensure the command prompt is started **as Administrator**.

---

# Uninstall Completely

```
sc stop OWMService
sc delete OWMService
```

Then remove the installation folder.

---

# Author

FishFind Backend Service

========================================================================
Windows .NET Service : Weather Notification Servce
Service once a day connect to CORE servce, retrive full list of observation points and update current weather data from wunderground
http://fishfind.info
Written on C# with using JSON format and MSSQL connection
Installation
To register the service:
Copy OWMService.exe to "c:\Program Files\FishFind\WeatherService".
Update the following system registry key by runing file: OWMService.reg
Run sql script on local MSSQl server: OWMService.sql
Reboot machine