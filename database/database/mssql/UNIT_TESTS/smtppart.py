import smtplib
import base64
import configparser
from smtplib import SMTPException

settings = configparser.ConfigParser(strict=False)
settings.read("config.ini", encoding="utf-8")

filename = "result.txt"
with open(filename, "rb") as f:
    encodedcontent = base64.b64encode(f.read()).decode("ascii")

sender = settings.get("mail", "sender")
receivers = [r.strip() for r in settings.get("mail", "receiver").split(",") if r.strip()]

smtp_server = settings.get("mail", "smtp")
smtp_port = settings.getint("mail", "smtpport")
smtp_user = settings.get("mail", "username", fallback=None)
smtp_pass = settings.get("mail", "password", fallback=None)
use_tls = settings.getboolean("mail", "use_tls", fallback=True)

marker = "AUNIQUEMARKER"
body = settings.get("mail", "crcstate", fallback="") + "\nDo not reply!\n"

message = (
    f"From: {sender}\n"
    f"To: {', '.join(receivers)}\n"
    f"Subject: Broken TSQL unit test\n"
    f"MIME-Version: 1.0\n"
    f"Content-Type: multipart/mixed; boundary={marker}\n"
    f"\n--{marker}\n"
    f"Content-Type: text/plain; charset=UTF-8\n"
    f"Content-Transfer-Encoding: 7bit\n\n"
    f"{body}\n"
    f"\n--{marker}\n"
    f'Content-Type: application/octet-stream; name="{filename}"\n'
    f"Content-Transfer-Encoding: base64\n"
    f'Content-Disposition: attachment; filename="{filename}"\n\n'
    f"{encodedcontent}\n"
    f"--{marker}--\n"
)

try:
    with smtplib.SMTP(smtp_server, smtp_port, timeout=30) as smtp:
        smtp.ehlo()
        if use_tls:
            smtp.starttls()
            smtp.ehlo()

        if smtp_user and smtp_pass:
            smtp.login(smtp_user, smtp_pass)

        smtp.sendmail(sender, receivers, message.encode("utf-8"))
        print("Successfully sent email")
except SMTPException as e:
    print("Error: unable to send email", str(e))
    raise
except Exception as e:
    print("Error: unable to send email", repr(e))
    raise