$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
[xml]$gpx = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Adeus_pernas.gpx') -Raw
$distance = 0.0
$points = [Collections.Generic.List[object]]::new()
foreach ($segment in $gpx.gpx.trk.trkseg) {
    $previous = $null
    foreach ($p in $segment.trkpt) {
        $lat = [double]::Parse($p.lat, $culture)
        $lon = [double]::Parse($p.lon, $culture)
        if ($null -ne $previous) {
            $rad = [Math]::PI / 180
            $a = [Math]::Pow([Math]::Sin(($lat-$previous[0])*$rad/2),2) + [Math]::Cos($lat*$rad)*[Math]::Cos($previous[0]*$rad)*[Math]::Pow([Math]::Sin(($lon-$previous[1])*$rad/2),2)
            $distance += 6371 * 2 * [Math]::Asin([Math]::Sqrt([Math]::Min(1.0,$a)))
        }
        $ele = if ($null -ne $p.ele) { [double]::Parse($p.ele, $culture) } else { $null }
        $timestamp = [DateTimeOffset]::Parse($p.time, $culture).ToUnixTimeSeconds()
        $points.Add(@($lat,$lon,$ele,[Math]::Round($distance,6),$timestamp))
        $previous = @($lat,$lon)
    }
}
$json = ConvertTo-Json -InputObject $points.ToArray() -Depth 4 -Compress
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pagina.template.html') -Raw -Encoding UTF8
$html = $template.Replace('__ROUTE_DATA__',$json)
$windPath = Join-Path $PSScriptRoot 'vento.json'
$wind = if (Test-Path -LiteralPath $windPath) { Get-Content -LiteralPath $windPath -Raw -Encoding UTF8 } else { '{"locations":[]}' }
$html = $html.Replace('__WIND_DATA__',$wind)
$html = $html.Replace('__WIND_CODE__',(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vento.js') -Raw -Encoding UTF8))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'percurso.html'),$html,[Text.UTF8Encoding]::new($false))
Write-Output ('Pontos: {0}; Distancia: {1:N3} km' -f $points.Count,$distance)

