# Generates script11_regulations_ontario2026.sql — Ontario 2026 zone-wide regulations.
# Source: https://www.ontario.ca/document/ontario-fishing-regulations-summary  (per-FMZ pages)
# One row per species-group per zone. Splits/complex seasons + licence-specific nuances are
# carried verbatim in regulations_text. reg_year/regulations_part use table defaults (2026 / '').
$ErrorActionPreference = 'Stop'
$base = 'https://www.ontario.ca/document/ontario-fishing-regulations-summary/fisheries-management-zone-'
$out  = Join-Path $PSScriptRoot '..\script11_regulations_ontario2026.sql'

function Esc($s){ if($null -eq $s){return $null}; return ($s -replace "'","''") }
function Fx($sp){ if($sp){ "(SELECT fish_id FROM dbo.fish WHERE fish_name=N'$(Esc $sp)')" } else { 'NULL' } }
function Nm($x){ if($null -eq $x){'NULL'}else{"$x"} }
function Dt($x){ if($x){"'$x'"}else{'NULL'} }
function Tx($x){ if($x){"N'$(Esc $x)'"}else{'NULL'} }

$rows = New-Object System.Collections.Generic.List[string]
function AddReg {
  param($sp=$null,$chain=$null,$res=0,$ds=$null,$sF=$null,$de=$null,$eF=$null,
        $s=$null,$c=$null,$minL=$null,$smin=$null,$smax=$null,$sover=$null,$method=$null,$code=8,$text)
  $script:rows.Add("('ON', @z, NULL, $(Fx $sp), $(Fx $chain), $res, $(Dt $ds), $(Tx $sF), $(Dt $de), $(Tx $eF), $(Nm $s), $(Nm $c), $(Nm $minL), $(Nm $smin), $(Nm $smax), $(Nm $sover), $(Nm $method), $code, @link, $(Tx $text))")
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine(@"
---------------------------------------------------------------------------------
-- Ontario 2026 zone-wide fishing regulations  (state = 'ON', generated)
-- Source: https://www.ontario.ca/document/ontario-fishing-regulations-summary
-- Zone-wide rules: zone_id = FMZ #, Lake_id = NULL. Named-water EXCEPTIONS not included.
-- Combined species: fish_id = primary, chain = partner. Verbatim rule in regulations_text.
-- regulations_code: 1 = closed all year, 8 = open. reg_year/regulations_part use defaults.
-- Idempotent: each zone first deletes its own ON / zone / 2026 zone-wide rows.
---------------------------------------------------------------------------------
"@)

$cols = "(state, zone_id, Lake_id, fish_id, chain, resident_type, regulations_date_start, regulations_start, regulations_date_end, regulations_end, regulations_sport, regulations_consr, min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags, regulations_code, regulations_link, regulations_text)"

function StartZone($z){ $script:rows = New-Object System.Collections.Generic.List[string]; $script:rows }
function EmitZone($z){
  [void]$sb.AppendLine("------------------------------ FMZ $z ------------------------------")
  [void]$sb.AppendLine("DECLARE @z int = $z; DECLARE @link nvarchar(255) = N'$base$z';")
  [void]$sb.AppendLine("DELETE FROM dbo.regulations WHERE state='ON' AND zone_id=@z AND Lake_id IS NULL AND reg_year=2026;")
  [void]$sb.AppendLine("INSERT INTO dbo.regulations")
  [void]$sb.AppendLine("    $cols")
  [void]$sb.AppendLine("VALUES")
  [void]$sb.AppendLine(($script:rows -join ",`r`n"))
  [void]$sb.AppendLine(";")
  [void]$sb.AppendLine("GO")
  [void]$sb.AppendLine("")
}
$AGG = 'Aggregate limit for all trout and salmon (including splake): S-5 and C-2 total daily catch and possession for all species combined.'

# ============================== FMZ 1 ==============================
StartZone 1 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -de '2026-09-30' -s 5 -c 2 -smax 40 -sover 1 -text 'Brook trout. January 1 to September 30. S-5 and C-2; not more than 1 greater than 40 cm.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -text 'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'
AddReg -sp 'Trout, Lake'     -s 3 -c 1 -text 'Lake trout. Open all year. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. Open all year. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 1

# ============================== FMZ 2 ==============================
StartZone 2 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -eF 'Labour Day' -s 5 -c 2 -smax 30 -sover 1 -text 'Brook trout. January 1 to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -text 'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -smax 56 -sover 1 -text 'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30. C-1; any size.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 4 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2; must be less than 35 cm from January 1 to June 30 and December 1 to December 31; no size limit July 1 to November 30.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 91 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -smin 70 -smax 90 -sover 1 -text 'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 2

# ============================== FMZ 3 ==============================
StartZone 3 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -de '2026-09-15' -s 5 -c 2 -text 'Brook trout. January 1 to September 15. S-5 and C-2.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -text 'Lake sturgeon. Season: January 1 to April 15 and July 1 to December 31. S-0 and C-0.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. January 1 to September 30. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 3

# ============================== FMZ 4 ==============================
StartZone 4 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -eF 'Labour Day' -s 5 -c 2 -smax 30 -sover 1 -text 'Brook trout. January 1 to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'
AddReg -sp 'Crappie, Black'  -s 15 -c 10 -text 'Crappie. Open all year. S-15 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -smax 56 -sover 1 -text 'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm. C-1; no size limit.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 4 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. Must be less than 35 cm Jan 1-Jun 30 and Dec 1-Dec 31, S-2 and C-1; no size limit Jul 1-Nov 30, S-4 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 102 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -smin 70 -smax 90 -sover 1 -text 'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
EmitZone 4

# ============================== FMZ 5 ==============================
StartZone 5 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -s 5 -c 2 -text 'Brook trout. Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Crappie, Black'  -s 10 -c 5 -text 'Crappie. Open all year. S-10 and C-5.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake' -res 1 -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -smax 56 -sover 1 -text 'Lake trout (Ontario/Canadian residents). January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30, and C-1; no size limit.'
AddReg -sp 'Trout, Lake' -res 2 -ds '2026-01-01' -de '2026-09-30' -s 1 -c 1 -text 'Lake trout (non-Canadian residents). January 1 to September 30. Daily catch and retain: S-1 and C-1, no size limit. Possession: S-2, not more than 1 greater than 56 cm from September 1 to September 30, and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 4 -c 2 -smin 35 -text 'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2; must be less than 35 cm from January 1 to June 30.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 102 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -smax 75 -sover 0 -text 'Northern pike. Open all year. S-4 and C-2; none greater than 75 cm.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -res 1 -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined (Ontario/Canadian residents). January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Walleye' -chain 'Sauger' -res 2 -s 2 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined (non-Canadian residents). Daily catch and retain: S-2 and C-2; not more than 1 greater than 46 cm. Possession: S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 5

# ============================== FMZ 6 ==============================
StartZone 6 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brook'    -sF 'fourth Saturday in April' -eF 'Labour Day' -s 5 -c 2 -smax 30 -sover 1 -text 'Brook trout. Fourth Saturday in April to Labour Day. S-5 and C-2; not more than 1 greater than 30 cm.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 15 -c 10 -text 'Crappie. Open all year. S-15 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -smax 56 -sover 1 -text 'Lake trout. January 1 to September 30. S-2; not more than 1 greater than 56 cm from September 1 to September 30, no size limit the rest of the season, and C-1; no size limit.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 4 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-4 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 91 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -smax 70 -sover 1 -text 'Northern pike. Open all year. S-4 and C-2; not more than 1 greater than or equal to 70 cm.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 1 -c 0 -text 'Rainbow trout. Open all year. S-1 and C-0.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 6

# ============================== FMZ 7 ==============================
StartZone 7 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -eF 'Labour Day' -s 5 -c 2 -text 'Brook trout. January 1 to Labour Day. S-5; not more than 2 greater than 30 cm, of which not more than 1 greater than 40 cm, and C-2; not more than 1 greater than 30 cm, none greater than 40 cm.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -text 'Lake trout. January 1 to September 30. S-2 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 25 -c 12 -text 'Lake whitefish. Open all year. S-25 and C-12.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -s 0 -c 0 -code 1 -text 'Muskellunge. Closed all year.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 1 -c 0 -text 'Rainbow trout. Open all year. S-1 and C-0.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 7

# ============================== FMZ 8 ==============================
StartZone 8 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -de '2026-09-15' -s 5 -c 2 -text 'Brook trout. January 1 to September 15. S-5 and C-2.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -text 'Lake sturgeon. Season: January 1 to April 30 and July 1 to December 31. S-0 and C-0.'
AddReg -sp 'Trout, Lake'     -ds '2026-02-15' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. February 15 to March 15 and third Saturday in May to September 30. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 25 -c 12 -text 'Lake whitefish. Open all year. S-25 and C-12.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 8

# ============================== FMZ 9 ==============================
StartZone 9 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brook'    -sF 'fourth Saturday in April' -eF 'Labour Day' -s 1 -c 0 -minL 56 -text 'Brook trout. Fourth Saturday in April to Labour Day. S-1; must be greater than 56 cm, and C-0.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. January 1 to September 30. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Open all year. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 137 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -smin 70 -smax 90 -sover 1 -text 'Northern pike. Open all year. S-4 and C-2; none between 70-90 cm, not more than 1 greater than 90 cm.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 1 -c 0 -text 'Rainbow trout. Open all year. S-1 and C-0.'
AddReg -sp 'Splake'          -ds '2026-01-01' -de '2026-09-30' -s 3 -c 1 -text 'Splake. January 1 to September 30. S-3 and C-1.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 2 -c 1 -text 'Walleye and sauger combined. January 1 to April 14 and third Saturday in May to December 31. S-2 and C-1.'
AddReg -sp 'Perch, Yellow'   -s 25 -c 12 -text 'Yellow perch. Open all year. S-25 and C-12.'
EmitZone 9

# ============================== FMZ 10 ==============================
StartZone 10 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -ds '2026-01-01' -de '2026-09-30' -s 1 -c 0 -text 'Atlantic salmon. January 1 to September 30. S-1 and C-0.'
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -de '2026-09-30' -s 5 -c 2 -text 'Brook trout. January 1 to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -eF 'Labour Day' -s 2 -c 1 -smax 40 -sover 1 -text 'Lake trout. January 1 to Labour Day. S-2; not more than 1 greater than 40 cm, and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'third Saturday in June' -de '2026-11-30' -s 6 -c 3 -text 'Largemouth and smallmouth bass combined. Third Saturday in June to November 30. S-6 and C-3.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 122 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 122 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -smax 86 -sover 1 -text 'Northern pike. Open all year. S-6; not more than 1 greater than 61 cm, none greater than 86 cm, and C-2; none greater than 61 cm.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 2 -c 1 -text 'Rainbow trout. Open all year. S-2 and C-1.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-4 and C-2; none greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 10

# ============================== FMZ 11 ==============================
StartZone 11 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 0 -c 0 -code 1 -text 'Atlantic salmon. Closed all year.'
AddReg -sp 'Trout, Brook'    -ds '2026-02-15' -de '2026-09-30' -s 5 -c 2 -smax 31 -sover 1 -text 'Brook trout. February 15 to September 30. S-5; not more than 1 greater than 31 cm, and C-2; none greater than 31 cm.'
AddReg -sp 'Trout, Brown'    -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-02-15' -eF 'Labour Day' -s 2 -c 1 -smax 40 -sover 1 -text 'Lake trout. February 15 to third Sunday in March and third Saturday in May to Labour Day. S-2; not more than 1 greater than 40 cm, and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 122 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 122 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -smax 86 -sover 1 -text 'Northern pike. January 1 to third Sunday in March and third Saturday in May to December 31. S-6; not more than 2 greater than 61 cm, of which not more than 1 greater than 86 cm, and C-2; not more than 1 greater than 61 cm, none greater than 86 cm.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smin 43 -smax 60 -sover 1 -text 'Walleye and sauger combined. January 1 to third Sunday in March and third Saturday in May to December 31. S-4 and C-2; none between 43-60 cm, not more than 1 greater than 60 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 11

# ============================== FMZ 12 ==============================
StartZone 12 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 1 -c 0 -text 'Atlantic salmon. Friday before fourth Saturday in April to September 30. S-1 and C-0.'
AddReg -sp 'Trout, Brook'    -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brook trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brown and rainbow trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brown and rainbow trout. Friday before fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 2 -c 1 -minL 45 -text 'Lake trout and splake. Friday before fourth Saturday in April to September 30. S-2 and C-1; must be greater than 45 cm.'
AddReg -sp 'Splake'          -sF 'Friday before fourth Saturday in April' -de '2026-09-30' -s 2 -c 1 -minL 45 -text 'Lake trout and splake. Friday before fourth Saturday in April to September 30. S-2 and C-1; must be greater than 45 cm.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'Friday before fourth Saturday in June' -de '2026-11-30' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Friday before fourth Saturday in June to November 30. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'Friday before third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 137 -text 'Muskellunge. Friday before third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. January 1 to March 31 and Friday before third Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 999 -c 999 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. No limit.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 5 -c 2 -smax 40 -text 'Walleye and sauger combined. January 1 to March 31 and Friday before third Saturday in May to December 31. S-5 and C-2; must be less than 40 cm from March 1 to June 15.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 12

# ============================== FMZ 13 ==============================
StartZone 13 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -text 'Lake trout. January 1 to September 30 and December 1 to December 31. S-2 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'fourth Saturday in June' -de '2026-11-30' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 102 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 102 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 4 -c 2 -text 'Northern pike. Open all year. S-4 and C-2.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 2 -c 1 -text 'Rainbow trout. Open all year. S-2 and C-1.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 6 -c 2 -text 'Walleye and sauger combined. Open all year. S-6 and C-2.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 13

# ============================== FMZ 14 ==============================
StartZone 14 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Herring, Lake'   -s 25 -c 12 -text 'Lake herring (cisco). Open all year. S-25 and C-12.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -text 'Lake trout. January 1 to September 30 and December 1 to December 31. S-2 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'fourth Saturday in June' -de '2026-11-30' -s 3 -c 1 -text 'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-3 and C-1.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 137 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -ds '2026-01-01' -de '2026-03-01' -s 2 -c 1 -smax 86 -sover 1 -text 'Northern pike. January 1 to March 1 and May 1 to December 31. S-2; in one day, possession limit of 4, not more than 1 greater than 86 cm, and C-1; in one day, possession limit of 2, not more than 1 greater than 86 cm.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 2 -c 1 -text 'Rainbow trout. Open all year. S-2 and C-1.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -ds '2026-01-01' -de '2026-03-01' -s 2 -c 1 -smin 41 -smax 56 -sover 1 -text 'Walleye and sauger combined. January 1 to March 1 and May 1 to December 31. S-2; in one day, possession limit of 4, none between 41-56 cm, not more than 1 greater than 56 cm, and C-1; in one day, possession limit of 2, none between 41-56 cm, not more than 1 greater than 56 cm.'
AddReg -sp 'Perch, Yellow'   -s 25 -c 12 -text 'Yellow perch. Open all year. S-25; in one day, possession limit of 50, and C-12; in one day, possession limit of 25.'
EmitZone 14

# ============================== FMZ 15 ==============================
StartZone 15 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 0 -c 0 -code 1 -text 'Atlantic salmon. Closed all year.'
AddReg -sp 'Trout, Brook'    -ds '2026-01-01' -de '2026-09-30' -s 5 -c 2 -text 'Brook trout. January 1 to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -text 'Lake trout. January 1 to September 30. S-2 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'fourth Saturday in June' -de '2026-11-30' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'first Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 91 -text 'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. January 1 to March 31 and third Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to March 15 and third Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 15

# ============================== FMZ 16 ==============================
StartZone 16 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -sF 'fourth Saturday in April' -de '2026-09-30' -s 0 -c 0 -text 'Atlantic salmon. Fourth Saturday in April to September 30. S-0 and C-0.'
AddReg -sp 'Trout, Brook'    -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brook trout. Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -sF 'fourth Saturday in April' -de '2026-09-30' -s 2 -c 1 -text 'Rainbow trout. Fourth Saturday in April to September 30. S-2 and C-1.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 2 -c 1 -text 'Lake trout. January 1 to September 30. S-2 and C-1.'
AddReg -sp 'Salmon, Chinook' -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 4 -c 2 -smax 46 -sover 1 -text 'Walleye and sauger combined. January 1 to March 15 and second Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 46 cm.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. January 1 to March 31 and second Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'fourth Saturday in June' -de '2026-11-30' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'first Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 91 -text 'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
AddReg -sp 'Sunfish, Bluegill' -s 50 -c 25 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-50 and C-25.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
EmitZone 16

# ============================== FMZ 17 ==============================
StartZone 17 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -sF 'fourth Saturday in April' -de '2026-09-30' -s 0 -c 0 -text 'Atlantic salmon. Fourth Saturday in April to September 30. S-0 and C-0.'
AddReg -sp 'Trout, Brook'    -sF 'fourth Saturday in April' -de '2026-09-30' -s 2 -c 1 -text 'Brook trout. Fourth Saturday in April to September 30. S-2 and C-1.'
AddReg -sp 'Trout, Brown'    -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Brown trout. Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -sF 'fourth Saturday in April' -de '2026-09-30' -s 2 -c 1 -text 'Rainbow trout. Fourth Saturday in April to September 30. S-2 and C-1.'
AddReg -sp 'Salmon, Chinook' -sF 'fourth Saturday in April' -de '2026-09-30' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Fourth Saturday in April to September 30. S-5 and C-2.'
AddReg -sp 'Trout, Lake'     -sF 'fourth Saturday in April' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. Fourth Saturday in April to September 30. S-3 and C-1.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6 and C-2.'
AddReg -sp 'Walleye' -chain 'Sauger' -sF 'second Saturday in May' -de '2026-11-15' -s 4 -c 1 -smin 35 -smax 50 -text 'Walleye and sauger combined. Second Saturday in May to November 15. S-4 and C-1; must be between 35-50 cm.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'third Saturday in June' -de '2026-12-15' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Third Saturday in June to December 15. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'first Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 112 -text 'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 112 cm, and C-0.'
AddReg -sp 'Whitefish, Lake' -sF 'fourth Saturday in April' -de '2026-11-15' -s 12 -c 6 -text 'Lake whitefish. Fourth Saturday in April to November 15. S-12 and C-6.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sunfish, Bluegill' -s 300 -c 15 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-300; only 30 may be greater than 18 cm, and C-15.'
AddReg -sp 'Catfish, Channel' -sF 'fourth Saturday in April' -de '2026-11-15' -s 12 -c 6 -text 'Channel catfish. Fourth Saturday in April to November 15. S-12 and C-6.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
EmitZone 17

# ============================== FMZ 18 ==============================
StartZone 18 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 0 -c 0 -code 1 -text 'Atlantic salmon. Closed all year.'
AddReg -sp 'Trout, Brook'    -s 5 -c 2 -text 'Brook trout. Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -sF 'fourth Saturday in May' -de '2026-09-08' -s 2 -c 1 -text 'Lake trout. Fourth Saturday in May to September 8. S-2 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'third Saturday in June' -de '2026-12-15' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Third Saturday in June to December 15. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'first Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 91 -text 'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 91 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. January 1 to March 31 and second Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Splake'          -s 5 -c 2 -text 'Splake. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 300 -c 15 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-300; only 30 may be greater than 18 cm, and C-15.'
AddReg -sp 'Walleye' -chain 'Sauger' -ds '2026-01-01' -de '2026-03-01' -s 4 -c 2 -smin 40 -smax 50 -text 'Walleye and sauger combined. January 1 to March 1 and second Saturday in May to December 31. S-4 and C-2; must be between 40-50 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 18

# ============================== FMZ 19 ==============================
StartZone 19 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -text 'Atlantic salmon. Open all year. S-1 and C-0.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. January 1 to September 30 and December 1 to December 31. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Smallmouth' -chain 'Bass, Largemouth' -sF 'fourth Saturday in June' -de '2026-11-30' -s 6 -c 2 -text 'Largemouth and smallmouth bass combined. Fourth Saturday in June to November 30. S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'first Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 112 -text 'Muskellunge. First Saturday in June to December 15. S-1; must be greater than 112 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. Open all year. S-6 and C-2.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 5 -c 2 -text 'Rainbow trout. Open all year. S-5 and C-2.'
AddReg -sp 'Sunfish, Bluegill' -s 100 -c 50 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-100 and C-50.'
AddReg -sp 'Walleye' -chain 'Sauger' -s 6 -c 2 -text 'Walleye and sauger combined. Open all year. S-6 and C-2.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50; in one day, possession limit of 100, and C-25; in one day, possession limit of 50.'
EmitZone 19

# ============================== FMZ 20 ==============================
StartZone 20 | Out-Null
AddReg -sp $null -s 5 -c 2 -text $AGG
AddReg -sp 'Salmon, Atlantic' -s 1 -c 0 -minL 63 -text 'Atlantic salmon. Open all year. S-1 and C-0; must be greater than 63 cm.'
AddReg -sp 'Trout, Brown'    -s 5 -c 2 -text 'Brown trout. Open all year. S-5 and C-2.'
AddReg -sp 'Catfish, Channel' -s 12 -c 6 -text 'Channel catfish. Open all year. S-12 and C-6.'
AddReg -sp 'Crappie, Black'  -s 30 -c 10 -text 'Crappie. Open all year. S-30 and C-10.'
AddReg -sp 'Sturgeon, Lake'  -s 0 -c 0 -code 1 -text 'Lake sturgeon. Closed all year.'
AddReg -sp 'Trout, Lake'     -ds '2026-01-01' -de '2026-09-30' -s 3 -c 1 -text 'Lake trout. January 1 to September 30 and December 1 to December 31. S-3 and C-1.'
AddReg -sp 'Whitefish, Lake' -s 12 -c 6 -text 'Lake whitefish. Open all year. S-12 and C-6.'
AddReg -sp 'Bass, Largemouth' -ds '2026-01-01' -de '2026-05-10' -s 0 -c 0 -method 1 -text 'Largemouth bass. Early season January 1 to May 10: catch-and-release only, S-0 and C-0. Regular season third Saturday in June to December 31: S-6 and C-2.'
AddReg -sp 'Bass, Smallmouth' -ds '2026-01-01' -de '2026-05-10' -s 0 -c 0 -method 1 -text 'Smallmouth bass. Early season January 1 to May 10: catch-and-release only, S-0 and C-0. Regular season first Saturday in July to December 31: S-6 and C-2.'
AddReg -sp 'Muskellunge'     -sF 'third Saturday in June' -de '2026-12-15' -s 1 -c 0 -minL 137 -text 'Muskellunge. Third Saturday in June to December 15. S-1; must be greater than 137 cm, and C-0.'
AddReg -sp 'Pike, Northern'  -s 6 -c 2 -text 'Northern pike. January 1 to March 31 and first Saturday in May to December 31. S-6 and C-2.'
AddReg -sp 'Salmon, Chinook' -s 5 -c 2 -text 'Pacific salmon (Chinook, Coho and other Pacific salmon). Open all year. S-5 and C-2.'
AddReg -sp 'Trout, Rainbow'  -s 2 -c 1 -text 'Rainbow trout. Open all year. S-2 and C-1.'
AddReg -sp 'Sunfish, Bluegill' -s 100 -c 50 -text 'Sunfish (bluegill, pumpkinseed and other sunfish). Open all year. S-100 and C-50.'
AddReg -sp 'Walleye' -chain 'Sauger' -ds '2026-01-01' -de '2026-03-01' -s 4 -c 2 -smax 63 -sover 1 -text 'Walleye and sauger combined. January 1 to March 1 and first Saturday in May to December 31. S-4 and C-2; not more than 1 greater than 63 cm.'
AddReg -sp 'Perch, Yellow'   -s 50 -c 25 -text 'Yellow perch. Open all year. S-50 and C-25.'
EmitZone 20

[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath (Split-Path $out) | ForEach-Object { Join-Path $_ (Split-Path $out -Leaf) }), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $out"
Write-Host ("Total VALUES rows: " + ([regex]::Matches($sb.ToString(), "^\('ON'", 'Multiline')).Count)
