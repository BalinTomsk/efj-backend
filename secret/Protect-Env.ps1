<#
.SYNOPSIS
    Encrypts selected values in plaintext.env and writes the deployable .env.

.DESCRIPTION
    plaintext.env is the human-edited source of truth and never leaves this workstation.
    This script copies it to .env, replacing the values named by -Encrypt with
    enc:v1:<base64url(nonce || ciphertext || tag)> payloads that the Java services unwrap at
    startup (see SecretCodec in docapi / waterservice / weather).

    Values not named by -Encrypt are copied verbatim, as are comments and blank lines, so the
    output stays readable and diffable and a partially-encrypted file remains valid.

    Cipher: AES-256-GCM, 12-byte random nonce, 128-bit tag, with the variable's own name bound in
    as additional authenticated data — so a ciphertext cannot be moved between variables.

.PARAMETER GenerateKey
    Creates a new random 32-byte master key at -KeyPath. Refuses to overwrite an existing key,
    which would strand every value already encrypted under it.

.PARAMETER Verify
    Decrypts the values in -OutputPath and confirms they match -PlaintextPath, then reports
    per-key status. Does not print any secret value.

.EXAMPLE
    ./Protect-Env.ps1 -GenerateKey
    ./Protect-Env.ps1
    ./Protect-Env.ps1 -Verify
#>
[CmdletBinding(DefaultParameterSetName = 'Encrypt')]
param(
    [string] $PlaintextPath = (Join-Path $PSScriptRoot 'plaintext.env'),
    [string] $OutputPath    = (Join-Path $PSScriptRoot '.env'),
    [string] $KeyPath       = (Join-Path $PSScriptRoot 'master.key'),

    # SQL Server host (inside the JDBC URL), login name and password; the paid weather API keys; and
    # the SMTP account plus the weekly-report addresses. SMTP_HOST/SMTP_PORT stay readable — they are
    # not credentials and are useful to eyeball when the Friday report fails to arrive.
    #
    # Anything not listed here is copied through in plaintext; see the warning emitted at the end of
    # an encrypt run, which flags secret-looking names that were left unencrypted.
    [string[]] $Encrypt = @(
        'DB_URL', 'DB_USERNAME', 'DB_PASSWORD',
        'VISUAL_CROSSING_API_KEY', 'GOOGLE_WEATHER_API_KEY',
        'SMTP_USERNAME', 'SMTP_PASSWORD', 'REPORT_EMAIL_FROM', 'REPORT_EMAIL_TO'
    ),

    [Parameter(ParameterSetName = 'GenerateKey')]
    [switch] $GenerateKey,

    [Parameter(ParameterSetName = 'Verify')]
    [switch] $Verify
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Prefix = 'enc:v1:'

function New-AesGcm {
    param([byte[]] $Key)

    # .NET 8 requires the tag size explicitly; earlier versions only accept the key.
    try {
        return [System.Security.Cryptography.AesGcm]::new($Key, 16)
    }
    catch [System.Management.Automation.MethodException] {
        return [System.Security.Cryptography.AesGcm]::new($Key)
    }
}

function Get-MasterKey {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Master key not found at $Path. Run: ./Protect-Env.ps1 -GenerateKey"
    }

    $material = (Get-Content -LiteralPath $Path -Raw) -replace '\s', ''

    if ($material.Length -eq 64 -and $material -match '^[0-9a-fA-F]+$') {
        $bytes = [byte[]]::new(32)
        for ($i = 0; $i -lt 32; $i++) {
            $bytes[$i] = [Convert]::ToByte($material.Substring($i * 2, 2), 16)
        }
        return $bytes
    }

    $bytes = [Convert]::FromBase64String($material)
    if ($bytes.Length -ne 32) {
        throw "Master key must be 32 bytes (64 hex chars or 44 base64 chars); got $($bytes.Length)."
    }
    return $bytes
}

function ConvertTo-Base64Url {
    param([byte[]] $Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param([string] $Text)
    $padded = $Text.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
    }
    return [Convert]::FromBase64String($padded)
}

function Protect-Value {
    param([byte[]] $Key, [string] $Name, [string] $Value)

    $nonce      = [byte[]]::new(12)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)

    $plaintext  = [Text.Encoding]::UTF8.GetBytes($Value)
    $ciphertext = [byte[]]::new($plaintext.Length)
    $tag        = [byte[]]::new(16)
    $aad        = [Text.Encoding]::UTF8.GetBytes($Name)

    $aes = New-AesGcm -Key $Key
    try   { $aes.Encrypt($nonce, $plaintext, $ciphertext, $tag, $aad) }
    finally { $aes.Dispose() }

    # Layout must match SecretCodec: nonce || ciphertext || tag.
    return $script:Prefix + (ConvertTo-Base64Url -Bytes ($nonce + $ciphertext + $tag))
}

function Unprotect-Value {
    param([byte[]] $Key, [string] $Name, [string] $Value)

    if (-not $Value.StartsWith($script:Prefix)) { return $Value }

    $payload = ConvertFrom-Base64Url -Text $Value.Substring($script:Prefix.Length)
    if ($payload.Length -lt 28) {
        throw "Value of $Name is marked $($script:Prefix) but is too short to be a valid payload."
    }

    # Explicit byte[] casts: PowerShell range-slicing yields Object[], which AesGcm rejects.
    # The ciphertext slice is built by length rather than a range so a zero-length value
    # (payload = nonce + tag only) does not produce a descending, and therefore reversed, range.
    $cipherLength = $payload.Length - 28
    $nonce        = [byte[]] $payload[0..11]
    $tag          = [byte[]] $payload[($payload.Length - 16)..($payload.Length - 1)]
    $ciphertext   = [byte[]]::new($cipherLength)
    if ($cipherLength -gt 0) {
        [Array]::Copy($payload, 12, $ciphertext, 0, $cipherLength)
    }
    $plaintext = [byte[]]::new($cipherLength)
    $aad       = [Text.Encoding]::UTF8.GetBytes($Name)

    $aes = New-AesGcm -Key $Key
    try   { $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext, $aad) }
    finally { $aes.Dispose() }

    return [Text.Encoding]::UTF8.GetString($plaintext)
}

function Read-EnvFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }

    $entries = [ordered] @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }

        $eq = $trimmed.IndexOf('=')
        if ($eq -le 0) { continue }

        $entries[$trimmed.Substring(0, $eq).Trim()] = $trimmed.Substring($eq + 1).Trim()
    }
    return $entries
}

# ---------------------------------------------------------------------------------------------

if ($GenerateKey) {
    if (Test-Path -LiteralPath $KeyPath) {
        throw "A key already exists at $KeyPath. Delete it only if nothing is encrypted under it — " +
              "every enc:v1: value in .env and on the droplet becomes unrecoverable."
    }

    $key = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($key)

    # Hex, wrapped for legibility; SecretCodec strips whitespace before decoding.
    $hex = ($key | ForEach-Object { $_.ToString('x2') }) -join ''
    $wrapped = ($hex -replace '(.{32})', "`$1`n").Trim()
    [IO.File]::WriteAllText($KeyPath, $wrapped + "`r`n")

    Write-Host "Master key written to $KeyPath (32 bytes)."
    Write-Host "Back this up somewhere safe and offline. Losing it means re-entering every secret."
    return
}

$key = Get-MasterKey -Path $KeyPath

if ($Verify) {
    $expected = Read-EnvFile -Path $PlaintextPath
    $actual   = Read-EnvFile -Path $OutputPath

    $failures = 0
    foreach ($name in $expected.Keys) {
        if (-not $actual.Contains($name)) {
            Write-Host ("  {0,-26} MISSING from {1}" -f $name, (Split-Path $OutputPath -Leaf)) -ForegroundColor Red
            $failures++
            continue
        }

        $isEncrypted = $actual[$name].StartsWith($script:Prefix)
        try {
            $roundTripped = Unprotect-Value -Key $key -Name $name -Value $actual[$name]
        }
        catch {
            Write-Host ("  {0,-26} FAILED to decrypt" -f $name) -ForegroundColor Red
            $failures++
            continue
        }

        if ($roundTripped -ceq $expected[$name]) {
            $state = if ($isEncrypted) { 'encrypted, round-trip OK' } else { 'plaintext (not encrypted)' }
            $colour = if ($isEncrypted) { 'Green' } else { 'Yellow' }
            Write-Host ("  {0,-26} {1}" -f $name, $state) -ForegroundColor $colour
        }
        else {
            Write-Host ("  {0,-26} MISMATCH against plaintext.env" -f $name) -ForegroundColor Red
            $failures++
        }
    }

    if ($failures -gt 0) { throw "$failures value(s) failed verification." }
    Write-Host "`nAll values verified." -ForegroundColor Green
    return
}

# Encrypt: rewrite plaintext.env into .env, transforming only the named keys.
$outputLines = [System.Collections.Generic.List[string]]::new()
$encrypted   = [System.Collections.Generic.List[string]]::new()
$skipped     = [System.Collections.Generic.List[string]]::new()

foreach ($line in [IO.File]::ReadAllLines($PlaintextPath)) {
    $trimmed = $line.Trim()
    $eq = $trimmed.IndexOf('=')

    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#') -or $eq -le 0) {
        $outputLines.Add($line)
        continue
    }

    $name  = $trimmed.Substring(0, $eq).Trim()
    $value = $trimmed.Substring($eq + 1).Trim()

    if ($Encrypt -notcontains $name) {
        $outputLines.Add($line)
        $skipped.Add($name)
        continue
    }

    if ($value.StartsWith($script:Prefix)) {
        throw "$name in $PlaintextPath is already encrypted. plaintext.env must hold plaintext only."
    }

    $outputLines.Add("$name=" + (Protect-Value -Key $key -Name $name -Value $value))
    $encrypted.Add($name)
}

# CRLF: .env is a Windows file and the deploy pipeline strips \r on the way to the droplet.
[IO.File]::WriteAllText($OutputPath, ($outputLines -join "`r`n") + "`r`n")

Write-Host "Wrote $OutputPath"
Write-Host ("  encrypted: " + ($encrypted -join ', '))
Write-Host ("  verbatim:  " + ($skipped -join ', '))

# Safety net for the obvious failure mode of an allow-list: a new credential is added to
# plaintext.env, nobody remembers to add it to -Encrypt, and it ships in the clear. Warn rather
# than encrypt automatically, so what gets encrypted stays an explicit decision.
$suspicious = $skipped | Where-Object { $_ -match 'PASSWORD|SECRET|TOKEN|CREDENTIAL|_KEY$|APIKEY' }
if ($suspicious) {
    Write-Host ""
    Write-Warning ("These look like credentials but were left in plaintext: " + ($suspicious -join ', '))
    Write-Warning "Add them to -Encrypt if they should be protected."
}

Write-Host "`nVerify with: ./Protect-Env.ps1 -Verify"
