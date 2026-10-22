param([switch]$NoBrowser, [int]$Port = 8766, [switch]$ValidateOnly, [switch]$ExportSite)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$gpxFolder = Join-Path $root 'GPX'
$culture = [Globalization.CultureInfo]::InvariantCulture
$script:rides = @{}
$script:cache = @{}
$script:windAttempted = @{}
$script:missingWind = [Collections.Generic.List[string]]::new()
function Read-Ride($file) {
    $fingerprint = $file.FullName + '|' + $file.Length + '|' + $file.LastWriteTimeUtc.Ticks
    if ($script:cache.ContainsKey($fingerprint)) { return $script:cache[$fingerprint] }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($file.FullName, $settings)
    $doc = [Xml.XmlDocument]::new()
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    $points = [Collections.Generic.List[object]]::new()
    $distance = 0.0
    $segments = $doc.SelectNodes('//*[local-name()="trkseg" or local-name()="rte"]')
    foreach ($segment in $segments) {
        $prev = $null
        foreach ($p in $segment.SelectNodes('*[local-name()="trkpt" or local-name()="rtept"]')) {
            $lat = [double]::Parse($p.GetAttribute('lat'),$culture)
            $lon = [double]::Parse($p.GetAttribute('lon'),$culture)
            if ([double]::IsNaN($lat) -or [double]::IsNaN($lon) -or [Math]::Abs($lat) -gt 90 -or [Math]::Abs($lon) -gt 180) { throw 'Coordenadas invalidas.' }
            if ($null -ne $prev) {
                $rad = [Math]::PI/180
                $a = [Math]::Pow([Math]::Sin(($lat-$prev[0])*$rad/2),2)+[Math]::Cos($lat*$rad)*[Math]::Cos($prev[0]*$rad)*[Math]::Pow([Math]::Sin(($lon-$prev[1])*$rad/2),2)
                $distance += 6371*2*[Math]::Asin([Math]::Sqrt([Math]::Min(1.0,$a)))
            }
            $ele = $null; $time = $null
            $e = $p.SelectSingleNode('*[local-name()="ele"]')
            $t = $p.SelectSingleNode('*[local-name()="time"]')
            if ($e) { $v = 0.0; if ([double]::TryParse($e.InnerText,[Globalization.NumberStyles]::Float,$culture,[ref]$v) -and -not [double]::IsInfinity($v) -and -not [double]::IsNaN($v)) { $ele=$v } }
            if ($t) { $v = [DateTimeOffset]::MinValue; if ([DateTimeOffset]::TryParse($t.InnerText,$culture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$v)) { $time=$v.ToUnixTimeSeconds() } }
            $points.Add(@($lat,$lon,$ele,[Math]::Round($distance,6),$time,($null -eq $prev)))
            $prev = @($lat,$lon)
        }
    }
    if ($points.Count -lt 2) { throw 'O GPX precisa conter pelo menos dois pontos de percurso.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($file.Name)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    $titleNode = $doc.SelectSingleNode('//*[local-name()="trk" or local-name()="rte"]/*[local-name()="name"]')
    $title = $file.BaseName
    if ($titleNode -and $titleNode.InnerText.Trim()) { $title = $titleNode.InnerText.Trim() }
    $start = $points[0][4]; $end = $points[$points.Count-1][4]
    $date = 'Data não informada'; $duration = 'Não informado'; $sort = 0
    if ($null -ne $start) { $date = [DateTimeOffset]::FromUnixTimeSeconds($start).ToOffset([TimeSpan]::FromHours(-3)).ToString('dd/MM/yyyy'); $sort=$start }
    if ($null -ne $start -and $null -ne $end -and $end -ge $start) { $span=[TimeSpan]::FromSeconds($end-$start); $duration=('{0}h {1:00}min {2:00}s' -f [int][Math]::Floor($span.TotalHours),$span.Minutes,$span.Seconds) }
    $ride = @{id=$id; name=$title; file=$file.Name; date=$date; duration=$duration; distance=[Math]::Round($distance,3); sort=$sort; points=$points.ToArray(); path=$file.FullName}
    $script:cache[$fingerprint] = $ride
    return $ride
}
function Get-Catalog {
    $script:rides = @{}
    $items = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $gpxFolder -File | Where-Object Extension -IEQ '.gpx') {
        try {
            $r = Read-Ride $file
            $script:rides[$r.id] = $r
            $items.Add(@{id=$r.id;name=$r.name;file=$r.file;date=$r.date;duration=$r.duration;distance=$r.distance;sort=$r.sort})
        } catch { $items.Add(@{name=$file.BaseName;file=$file.Name;error=$_.Exception.Message;sort=0}) }
    }
    return ConvertTo-Json -InputObject @($items.ToArray() | Sort-Object { $_.sort } -Descending) -Depth 5 -Compress
}
function Get-Map($ride) {
    $html = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'mapa.template.html'))
    $wind = '{"locations":[]}'
    # A cache is tied to the exact GPX bytes, never to another ride's date/name.
    $hash = (Get-FileHash -LiteralPath $ride.path -Algorithm SHA256).Hash
    $windPath = Join-Path $PSScriptRoot "vento\$hash.json"
    $hasWind = $false
    if (Test-Path -LiteralPath $windPath) {
        try {
            $cached = [IO.File]::ReadAllText($windPath)
            $data = ConvertFrom-Json -InputObject $cached
            if (@($data.locations).Count -gt 0 -and $data.locations[0].hourly.time.Count -gt 0) {
                $wind = $cached
                $hasWind = $true
            }
        } catch { Write-Warning "Cache de vento invalido: $($ride.file). Sera consultado novamente." }
    }
    if (-not $hasWind -and -not $script:windAttempted.ContainsKey($hash) -and -not $ValidateOnly) {
        $script:windAttempted[$hash]=$true
        Write-Host "Consultando vento: $($ride.file)..."
        try {
            [IO.Directory]::CreateDirectory((Split-Path $windPath -Parent)) | Out-Null
            & (Join-Path $PSScriptRoot 'consultar-vento.ps1') -GpxPath $ride.path -OutputPath $windPath | Out-Host
            $wind = [IO.File]::ReadAllText($windPath)
            $hasWind = $true
        } catch {
            Write-Warning "Vento indisponivel em $($ride.file): $($_.Exception.Message). Gere novamente para tentar outra vez."
        }
    }
    if (-not $hasWind -and $ExportSite) { $script:missingWind.Add($ride.file) }
    $values = @{TITLE=$ride.name; DATE=$ride.date; DURATION=$ride.duration; FILE=$ride.file}
    foreach ($key in $values.Keys) { $html=$html.Replace("__$($key)__",[Net.WebUtility]::HtmlEncode([string]$values[$key])) }
    $json = ConvertTo-Json -InputObject $ride.points -Depth 5 -Compress
    $html=$html.Replace('__ROUTE_DATA__',$json.Replace('<','\u003c')).Replace('__WIND_DATA__',$wind.Replace('<','\u003c'))
    return $html.Replace('__WIND_CODE__',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'vento.js')))
}
if ($ExportSite) {
    $output = Join-Path $root 'docs'
    $maps = Join-Path $output 'mapa'
    [IO.Directory]::CreateDirectory($maps) | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    $catalog = Get-Catalog
    $items = ConvertFrom-Json -InputObject $catalog
    $invalid = @($items | Where-Object { $_.error })
    if ($invalid.Count) {
        $details = ($invalid | ForEach-Object { "$($_.file): $($_.error)" }) -join [Environment]::NewLine
        throw ("Corrija os GPX invalidos antes de publicar:" + [Environment]::NewLine + $details)
    }
    foreach ($ride in $script:rides.Values) {
        $map = (Get-Map $ride).Replace('href="/"','href="../index.html"')
        if ($map -match '__[A-Z_]+__') { throw 'Marcador nao substituido.' }
        [IO.File]::WriteAllText((Join-Path $maps ($ride.id+'.html')),$map,$utf8)
    }
    # Retira somente paginas geradas de percursos removidos da biblioteca.
    foreach ($file in Get-ChildItem -LiteralPath $maps -File) {
        if ($file.Name -match '^([a-f0-9]{64})\.html$' -and -not $script:rides.ContainsKey($Matches[1])) {
            Remove-Item -LiteralPath $file.FullName
        }
    }
    [IO.File]::WriteAllText((Join-Path $output 'pedais.json'),$catalog,$utf8)
    $index = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html'))
    $index = $index.Replace("fetch('/api/pedais')","fetch('./pedais.json')").Replace("link.href='/mapa/'+ride.id","link.href='./mapa/'+ride.id+'.html'")
    $index = $index.Replace('Coloque seus arquivos <b>.gpx</b> na pasta <b>GPX</b> e clique em <b>Atualizar lista</b>. Cada pedal tem seu próprio mapa, animação e perfil de altitude.','Explore meus pedais: abra um percurso para ver o mapa, a animação, a altitude e os dados de vento disponíveis.')
    $index = $index.Replace('Os arquivos ficam no seu computador. O mapa de ruas precisa de internet.','Percursos compartilhados publicamente. Mapas: OpenStreetMap. Vento: Open-Meteo.').Replace('Ainda não há pedais. Coloque um arquivo na pasta GPX para começar.','Ainda não há pedais publicados.').Replace('Não foi possível acessar a biblioteca. Abra “Abrir meus pedais.cmd” e tente novamente.','Não foi possível carregar os pedais. Verifique sua conexão e atualize a página.')
    [IO.File]::WriteAllText((Join-Path $output 'index.html'),$index,$utf8)
    [IO.File]::WriteAllText((Join-Path $output '.nojekyll'),'',$utf8)
    Write-Output "Site exportado: $($script:rides.Count) pedais em docs."
    if ($script:missingWind.Count) {
        Write-Warning ("Mapas gerados sem vento: " + ($script:missingWind -join ', ') + '. Confira a internet e gere novamente antes de publicar.')
    } else { Write-Host 'Vento incluido em todos os pedais. Agora faca Commit e Push para atualizar o site.' }
    return
}
if ($ValidateOnly) { Get-Catalog; foreach ($ride in $script:rides.Values) { $map=Get-Map $ride; if ($map -match '__[A-Z_]+__') { throw 'Marcador nao substituido.' }; Write-Output "OK: $($ride.file), $($ride.points.Count) pontos" }; exit }
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
try { $listener.Start() } catch { $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0); $listener.Start() }
$url="http://127.0.0.1:$($listener.LocalEndpoint.Port)/"
Write-Host "Meus pedais: $url"
Write-Host 'Feche esta janela para encerrar. Coloque novos arquivos na pasta GPX e clique em Atualizar lista.'
try {
    if (-not $NoBrowser) { Start-Process $url }
    while ($true) {
        $client=$listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout=3000; $client.SendTimeout=3000
            $stream=$client.GetStream(); $reader=[IO.StreamReader]::new($stream)
            $request=$reader.ReadLine(); $count=0
            do { $line=$reader.ReadLine(); $count++ } while ($line -and $count -lt 100)
            $status='200 OK'; $type='text/html; charset=utf-8'
            if ($request -match '^GET /(?:\?[^ ]*)? HTTP/1\.[01]$') { $body=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html')) }
            elseif ($request -match '^GET /api/pedais(?:\?[^ ]*)? HTTP/1\.[01]$') { $body=Get-Catalog; $type='application/json; charset=utf-8' }
            elseif ($request -match '^GET /mapa/([a-f0-9]{64}) HTTP/1\.[01]$') {
                $id=$Matches[1]; $null=Get-Catalog
                if ($script:rides.ContainsKey($id)) { $body=Get-Map $script:rides[$id] } else { $status='404 Not Found'; $body='Pedal nao encontrado. Volte a lista e atualize.' }
            } else { $status='404 Not Found'; $body='Pagina nao encontrada.' }
            $bytes=[Text.Encoding]::UTF8.GetBytes($body)
            $headers=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n")
            $stream.Write($headers,0,$headers.Length); $stream.Write($bytes,0,$bytes.Length); $stream.Flush()
        } catch { Write-Warning $_.Exception.Message } finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
