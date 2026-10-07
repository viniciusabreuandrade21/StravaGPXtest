param([string]$GpxPath,[string]$OutputPath)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
[xml]$gpx = Get-Content -LiteralPath $GpxPath -Raw -Encoding UTF8
$nodes = @($gpx.gpx.trk.trkseg.trkpt)
$locations = [ordered]@{}
foreach ($p in $nodes) {
    $lat = [Math]::Round([double]::Parse($p.lat,$culture),1)
    $lon = [Math]::Round([double]::Parse($p.lon,$culture),1)
    $key = $lat.ToString('F1',$culture)+','+$lon.ToString('F1',$culture)
    $locations[$key] = @($lat,$lon)
}
$start = [DateTimeOffset]::Parse($nodes[0].time).UtcDateTime.ToString('yyyy-MM-dd')
$end = [DateTimeOffset]::Parse($nodes[-1].time).UtcDateTime.AddHours(1).ToString('yyyy-MM-dd')
$lats = ($locations.Values | ForEach-Object { $_[0].ToString('F1',$culture) }) -join ','
$lons = ($locations.Values | ForEach-Object { $_[1].ToString('F1',$culture) }) -join ','
$endpoint = if (([DateTime]::UtcNow - [DateTime]::Parse($start)).TotalDays -le 5) { 'https://api.open-meteo.com/v1/forecast' } else { 'https://historical-forecast-api.open-meteo.com/v1/forecast' }
$url = $endpoint+'?latitude='+$lats+'&longitude='+$lons+'&start_date='+$start+'&end_date='+$end+'&hourly=wind_speed_10m,wind_direction_10m&wind_speed_unit=kmh&timezone=GMT&timeformat=unixtime'
$response = Invoke-RestMethod -Uri $url -TimeoutSec 12
$results = @($response)
if ($results.Count -ne $locations.Count) { throw 'Quantidade inesperada de locais na resposta.' }
$saved = [Collections.Generic.List[object]]::new()
$index = 0
foreach ($key in $locations.Keys) {
    $result = $results[$index++]
    if (-not $result.hourly.time -or $result.hourly_units.wind_speed_10m -ne 'km/h') { throw 'Dados de vento invalidos.' }
    $saved.Add([ordered]@{key=$key; requested=$locations[$key]; latitude=$result.latitude; longitude=$result.longitude; hourly=$result.hourly})
}
$output = [ordered]@{source='Open-Meteo'; dataset='Best Match - modelos meteorologicos arquivados'; fetchedAt=[DateTime]::UtcNow.ToString('o'); url=$url; startDate=$start; endDate=$end; locations=$saved.ToArray()}
$json = ConvertTo-Json -InputObject $output -Depth 8 -Compress
[IO.File]::WriteAllText($OutputPath,$json,[Text.UTF8Encoding]::new($false))
Write-Output ('Vento salvo: {0} locais, {1} horarios por local.' -f $saved.Count,$results[0].hourly.time.Count)
