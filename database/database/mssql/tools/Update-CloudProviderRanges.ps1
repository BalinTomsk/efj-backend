<#
.SYNOPSIS
    Refreshes dbo.CloudProviderIpRange with the published IPv4 ranges of the major datacenter /
    cloud / hosting providers, so Global.asax.cs (via dbo.IsIpBlocked / dbo.IsCloudProviderIp) can
    refuse traffic that originates from hosting networks rather than residential / mobile ISPs.

.DESCRIPTION
    Real anglers browse from consumer ISPs; sustained traffic from AWS/GCP/Azure/Oracle/DigitalOcean/
    Alibaba and similar networks is overwhelmingly scrapers, bots and headless crawlers. Each provider
    publishes its address space; this script downloads those feeds, expands every CIDR to an inclusive
    numeric [ipStart, ipEnd] window, and replaces the rows for the refreshed providers in one transaction.

    Sources used (IPv4 only; IPv6 prefixes are skipped because the app range-matches IPv4):
        AWS           https://ip-ranges.amazonaws.com/ip-ranges.json
        GCP           https://www.gstatic.com/ipranges/cloud.json
        Oracle (OCI)  https://docs.oracle.com/en-us/iaas/tools/public_ip_ranges.json
        DigitalOcean  https://www.digitalocean.com/geo/google.csv
        Azure         ServiceTags_Public_*.json (link scraped from the MS download page; best-effort)
        ASN feeds     RIPEstat announced-prefixes for Alibaba, Linode, Vultr, Hetzner, OVH,
                      Scaleway, Tencent (providers without a clean first-party JSON feed)

    The lists are large (AWS ~8k, Azure can be ~60k prefixes). The table is data, not hand-edited.
    Run this on a schedule (e.g. weekly) against production out-of-band.

.PARAMETER ConnectionString
    Full ADO.NET connection string. If omitted, one is built from -Server / -Database (+ -Username /
    -Password, or integrated security when those are omitted).

.PARAMETER Providers
    Subset to refresh. Default: all. Only the providers actually fetched are replaced, so a partial
    run never wipes a provider it didn't refresh.

.PARAMETER DryRun
    Fetch and report counts only; do not write to the database.

.EXAMPLE
    # Local test DB, integrated security, all providers
    .\Update-CloudProviderRanges.ps1 -Server localhost -Database ffi

.EXAMPLE
    # Production, explicit connection string, just the first-party feeds
    .\Update-CloudProviderRanges.ps1 -ConnectionString $cs -Providers AWS,GCP,Azure,Oracle,DigitalOcean
#>
[CmdletBinding()]
param(
    [string]   $ConnectionString,
    [string]   $Server   = 'localhost',
    [string]   $Database = 'ffi',
    [string]   $Username,
    [string]   $Password,
    [string[]] $Providers = @('AWS','GCP','Azure','Oracle','DigitalOcean','Alibaba','Linode','Vultr','Hetzner','OVH','Scaleway','Tencent'),
    [switch]   $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ASN -> announced prefixes, for providers without a clean first-party feed.
$AsnProviders = @{
    'Alibaba'  = @(45102, 45103, 37963, 134963)
    'Linode'   = @(63949)
    'Vultr'    = @(20473)
    'Hetzner'  = @(24940, 213230)
    'OVH'      = @(16276)
    'Scaleway' = @(12876)
    'Tencent'  = @(132203, 45090)
}

# -------------------------------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------------------------------

function ConvertTo-IpRange {
    # 'a.b.c.d/p' -> @{ Start; End } as Int64 (uint32 values); $null for IPv6 / malformed input.
    param([string] $Cidr)

    if ([string]::IsNullOrWhiteSpace($Cidr)) { return $null }
    $parts = $Cidr.Trim().Split('/')
    if ($parts.Count -ne 2) { return $null }

    $octets = $parts[0].Split('.')
    if ($octets.Count -ne 4) { return $null }    # IPv6 or junk -> skip

    [int64] $base = 0
    foreach ($o in $octets) {
        $v = 0
        if (-not [int]::TryParse($o, [ref] $v) -or $v -lt 0 -or $v -gt 255) { return $null }
        $base = ($base * 256) + $v
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref] $prefix) -or $prefix -lt 0 -or $prefix -gt 32) { return $null }

    [int64] $size = [int64][math]::Pow(2, 32 - $prefix)
    return [pscustomobject]@{ Start = $base; End = ($base + $size - 1) }
}

function Get-Json {
    param([string] $Url)
    return Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec 60
}

function Get-AwsPrefixes      { (Get-Json 'https://ip-ranges.amazonaws.com/ip-ranges.json').prefixes  | ForEach-Object { $_.ip_prefix } }
function Get-GcpPrefixes      { (Get-Json 'https://www.gstatic.com/ipranges/cloud.json').prefixes      | ForEach-Object { $_.ipv4Prefix } | Where-Object { $_ } }
function Get-OraclePrefixes   { (Get-Json 'https://docs.oracle.com/en-us/iaas/tools/public_ip_ranges.json').regions | ForEach-Object { $_.cidrs } | ForEach-Object { $_.cidr } }

function Get-DigitalOceanPrefixes {
    $csv = Invoke-WebRequest -Uri 'https://www.digitalocean.com/geo/google.csv' -UseBasicParsing -TimeoutSec 60
    foreach ($line in ($csv.Content -split "`n")) {
        $first = ($line -split ',')[0].Trim()
        if ($first) { $first }
    }
}

function Get-AzurePrefixes {
    # The download page embeds a weekly-rotating direct link to ServiceTags_Public_<date>.json.
    $page = Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=56519' -UseBasicParsing -TimeoutSec 60
    $m = [regex]::Match($page.Content, 'https://download\.microsoft\.com/download/[^"'']*ServiceTags_Public_[0-9]+\.json')
    if (-not $m.Success) { throw 'Could not locate the ServiceTags_Public JSON link on the Azure download page.' }
    (Get-Json $m.Value).values | ForEach-Object { $_.properties.addressPrefixes } | Where-Object { $_ -and ($_ -notmatch ':') }
}

function Get-AsnPrefixes {
    param([int[]] $AsnList)
    foreach ($asn in $AsnList) {
        $data = Get-Json "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$asn"
        $data.data.prefixes | ForEach-Object { $_.prefix }
    }
}

function Get-ProviderPrefixes {
    param([string] $Provider)
    switch ($Provider) {
        'AWS'          { return Get-AwsPrefixes }
        'GCP'          { return Get-GcpPrefixes }
        'Oracle'       { return Get-OraclePrefixes }
        'DigitalOcean' { return Get-DigitalOceanPrefixes }
        'Azure'        { return Get-AzurePrefixes }
        default {
            if ($AsnProviders.ContainsKey($Provider)) { return Get-AsnPrefixes $AsnProviders[$Provider] }
            throw "Unknown provider '$Provider'."
        }
    }
}

# -------------------------------------------------------------------------------------------------
# 1) Fetch + expand every requested provider into one in-memory DataTable
# -------------------------------------------------------------------------------------------------

$table = New-Object System.Data.DataTable
[void]$table.Columns.Add('id',         [Guid])
[void]$table.Columns.Add('provider',   [string])
[void]$table.Columns.Add('cidr',       [string])
[void]$table.Columns.Add('ipStart',    [int64])
[void]$table.Columns.Add('ipEnd',      [int64])
[void]$table.Columns.Add('source',     [string])
[void]$table.Columns.Add('updatedUtc', [datetime])

$now = [datetime]::UtcNow
$refreshed = New-Object System.Collections.Generic.List[string]
$counts = [ordered]@{}

foreach ($provider in $Providers) {
    try {
        Write-Host "Fetching $provider ..." -NoNewline
        $prefixes = @(Get-ProviderPrefixes -Provider $provider)
        $added = 0
        foreach ($cidr in $prefixes) {
            $r = ConvertTo-IpRange -Cidr $cidr
            if ($null -eq $r) { continue }      # IPv6 / malformed
            $row = $table.NewRow()
            $row['id']         = [Guid]::NewGuid()
            $row['provider']   = $provider
            $row['cidr']       = $cidr.Trim()
            $row['ipStart']    = $r.Start
            $row['ipEnd']      = $r.End
            $row['source']     = 'Update-CloudProviderRanges.ps1'
            $row['updatedUtc'] = $now
            $table.Rows.Add($row)
            $added++
        }
        $counts[$provider] = $added
        $refreshed.Add($provider)
        Write-Host " $added IPv4 ranges"
    }
    catch {
        Write-Warning "  $provider failed: $($_.Exception.Message) -- leaving its existing rows untouched."
    }
}

Write-Host ''
Write-Host "Total IPv4 ranges collected: $($table.Rows.Count) across $($refreshed.Count) provider(s)."
$counts.GetEnumerator() | ForEach-Object { '  {0,-13} {1}' -f $_.Key, $_.Value } | Write-Host

if ($refreshed.Count -eq 0) { throw 'No provider feeds were fetched successfully; aborting (database left unchanged).' }

if ($DryRun) {
    Write-Host ''
    Write-Host 'DryRun specified -- database not modified.'
    return
}

# -------------------------------------------------------------------------------------------------
# 2) Replace the refreshed providers' rows in one transaction (DELETE refreshed -> bulk insert)
# -------------------------------------------------------------------------------------------------

if (-not $ConnectionString) {
    if ($Username) {
        $ConnectionString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;"
    } else {
        $ConnectionString = "Server=$Server;Database=$Database;Integrated Security=SSPI;TrustServerCertificate=True;"
    }
}

$conn = New-Object System.Data.SqlClient.SqlConnection $ConnectionString
$conn.Open()
$tx = $conn.BeginTransaction('RefreshCloudRanges')
try {
    # Delete only the providers we successfully refreshed.
    $names = ($refreshed | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ','
    $del = $conn.CreateCommand()
    $del.Transaction = $tx
    $del.CommandText = "DELETE FROM dbo.CloudProviderIpRange WHERE provider IN ($names)"
    $deleted = $del.ExecuteNonQuery()
    Write-Host ''
    Write-Host "Deleted $deleted stale row(s) for: $($refreshed -join ', ')"

    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($conn, [System.Data.SqlClient.SqlBulkCopyOptions]::Default, $tx)
    $bulk.DestinationTableName = 'dbo.CloudProviderIpRange'
    $bulk.BatchSize = 5000
    $bulk.BulkCopyTimeout = 120
    foreach ($c in $table.Columns) { [void]$bulk.ColumnMappings.Add($c.ColumnName, $c.ColumnName) }
    $bulk.WriteToServer($table)

    $tx.Commit()
    Write-Host "Inserted $($table.Rows.Count) row(s). Commit OK."
}
catch {
    $tx.Rollback()
    throw "Database update failed and was rolled back: $($_.Exception.Message)"
}
finally {
    $conn.Close()
}
