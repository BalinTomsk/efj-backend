Environment Configuration

Ensure SQLCMD Is Available Globally



Locate SQLCMD.EXE (typically installed with SQL Server tools).



Add its directory to the system PATH:



Control Panel → System → Advanced system settings →

Environment Variables → Path → Edit → Add SQLCMD directory.



Verify:



sqlcmd -?

Running the Project



To create the database and execute all unit tests:



autorun.bat



The script will:



Create or reset the database



Execute all unit tests



Send email notification if any test fails



Notes



Python 2.7 is deprecated and no longer supported.



It is strongly recommended to use Python 3.



For reproducible environments, consider using:



python -m venv venv

venv\\Scripts\\activate

pip install -r requirements.txt



If you'd like, I can also prepare:



A production-ready README.md (GitHub formatted)



A DevOps-oriented version (CI/CD ready)



A Dockerized version



A modernized version replacing SQLCMD with a Python DB connector



production-ready README.md



Below is a production-ready README.md suitable for GitHub or enterprise repositories.

It follows best practices: clear structure, environment isolation, security notes, CI readiness, and operational clarity.



Project Name



Automation framework for database initialization and unit test execution with email notifications on failure.



🚀 Overview



This project provides:



Automated database creation/reset



Execution of all unit tests



Email notifications on test failure



Configurable environment via config.ini



Optional Windows batch execution (autorun.bat)



Designed for Windows environments using SQL Server and Python 3.



🏗 Architecture Overview

+-------------------+

| autorun.bat       |

+-------------------+

&#x20;         |

&#x20;         v

+-------------------+

| Python Test Runner|

+-------------------+

&#x20;         |

&#x20;         v

+-------------------+

| SQL Server (via   |

| SQLCMD or driver) |

+-------------------+

&#x20;         |

&#x20;         v

+-------------------+

| SMTP Notification |

+-------------------+

📋 Prerequisites

Requirement	Version	Notes

Python	3.10+	Recommended

pip	Latest	Installed with Python

SQL Server	Supported version	Local or remote

SQLCMD	Installed	Must be in PATH

Windows OS	10/11 or Server	Required for .bat execution

🔧 Installation

1️⃣ Clone the Repository

git clone https://github.com/your-org/your-repo.git

cd your-repo

2️⃣ Create Virtual Environment (Recommended)

python -m venv venv

venv\\Scripts\\activate

3️⃣ Install Dependencies



If requirements.txt exists:



pip install -r requirements.txt



Otherwise install manually:



pip install configparser

⚙️ Configuration



All runtime configuration is defined in:



config.ini

Example Structure

\[database]

server=localhost

database=TestDB

username=sa

password=YourStrongPassword



\[smtp]

host=smtp.example.com

port=587

username=notifications@example.com

password=secure\_password

recipient=dev-team@example.com



\[tests]

expected\_test\_count=42

crc\_code=123456

🔐 Security Best Practice



Do NOT commit real credentials.



Use environment variables for sensitive data.



Consider using:



Windows Credential Manager



Azure Key Vault



GitHub Secrets (for CI/CD)



🧪 Running Tests

Option 1 – Using Batch Script (Windows)

autorun.bat



This will:



Create or reset the database



Execute all unit tests



Send email notification if any test fails



Option 2 – Manual Execution

python run\_tests.py

📬 Email Notification Logic



If any unit test fails:



An email is sent to the recipient defined in config.ini



SMTP configuration must be valid



Ensure firewall allows outbound SMTP traffic



🗄 Database Execution



Ensure SQLCMD.EXE is accessible:



sqlcmd -?



If not available:



Add SQL Server tools directory to PATH:



Control Panel → System → Advanced → Environment Variables → Path

🛠 CI/CD Integration



This project can be integrated into:



Azure DevOps



GitHub Actions



Jenkins



GitLab CI



Example GitHub Actions Snippet

name: Run Tests



on: \[push]



jobs:

&#x20; test:

&#x20;   runs-on: windows-latest



&#x20;   steps:

&#x20;     - uses: actions/checkout@v3



&#x20;     - name: Setup Python

&#x20;       uses: actions/setup-python@v4

&#x20;       with:

&#x20;         python-version: '3.11'



&#x20;     - name: Install Dependencies

&#x20;       run: pip install -r requirements.txt



&#x20;     - name: Run Tests

&#x20;       run: python run\_tests.py

🧹 Troubleshooting

Python Not Recognized



Check:



python --version



If not found — reinstall Python and ensure "Add to PATH" is enabled.



SQLCMD Not Found



Check:



sqlcmd -?



If not found — install SQL Server Command Line Utilities.



Email Not Sending



Verify:



SMTP credentials



Port availability



Firewall rules



TLS/SSL requirements



📦 Recommended Improvements (Optional)



For production-grade systems consider:



Replacing SQLCMD with pyodbc or sqlalchemy



Using pytest



Adding structured logging (logging module)



Adding retry/backoff for SMTP



Adding Docker support



Implementing circuit breaker for external dependencies



📄 License



Specify your license here (MIT, Apache 2.0, etc.)



👤 Maintainers



Your Name



Team Name



Contact Email

