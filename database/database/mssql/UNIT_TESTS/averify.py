# c:\Python27 (legacy header)
# Updated: compare saved crcstate to MD5(cleaned.txt). If changed -> send email, then update crcstate.

import sys
import hashlib
import configparser
import subprocess


def md5_file(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_settings(config_path: str) -> configparser.ConfigParser:
    # strict=False prevents DuplicateOptionError if the same key exists twice
    settings = configparser.ConfigParser(strict=False)
    settings.read(config_path, encoding="utf-8")
    return settings


def save_crcstate(config_path: str, new_crc: str) -> None:
    settings = load_settings(config_path)
    if not settings.has_section("mail"):
        settings.add_section("mail")
    settings.set("mail", "crcstate", new_crc)

    # NOTE: This rewrites config.ini (comments/formatting may be normalized by configparser).
    with open(config_path, "w", encoding="utf-8") as f:
        settings.write(f)


def main() -> int:
    config_path = "config.ini"
    result_path = "result.txt"
    cleaned_path = "cleaned.txt"

    # --- build cleaned.txt exactly like your current logic ---
    main_text = open(result_path, "r", encoding="utf-8", errors="ignore").read()

    with open("error.txt", "w", encoding="utf-8", errors="ignore") as f:
        f.write(main_text)

    out = open(cleaned_path, "w", encoding="utf-8", errors="ignore")
    for line in open("error.txt", "r", encoding="utf-8", errors="ignore"):
        if (
            "PASSED" not in line
            and "Warning: Null value" not in line
            and "(0 rows affected)" not in line
            and "(1 rows affected)" not in line
            and "----" not in line
            and line != "\n"
        ):
            out.write(line.lstrip())
    out.close()

    # --- compare md5(cleaned.txt) with saved crcstate ---
    cur_crc = md5_file(cleaned_path)

    settings = load_settings(config_path)
    saved_crc = ""
    if settings.has_section("mail"):
        saved_crc = settings.get("mail", "crcstate", fallback="").strip()

    if saved_crc and saved_crc == cur_crc:
        print("averify.py: crc unchanged -> no email.")
        return 0

    print(f"averify.py: crc changed (old={saved_crc}, new={cur_crc}) -> sending email...")

    # Use existing email sender; update crcstate ONLY on success
    r = subprocess.run([sys.executable, "smtppart.py"])
    if r.returncode != 0:
        print("averify.py: email send failed -> crcstate NOT updated.", file=sys.stderr)
        return r.returncode

    save_crcstate(config_path, cur_crc)
    print("averify.py: crcstate updated in config.ini")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())