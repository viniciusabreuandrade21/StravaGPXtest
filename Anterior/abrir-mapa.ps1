param([switch]$NoBrowser, [int]$Port = 8765)
$ErrorActionPreference = 'Stop'
$page = Join-Path $PSScriptRoot 'percurso.html'
if (-not (Test-Path -LiteralPath $page)) { throw 'percurso.html nao encontrado nesta pasta.' }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } catch {
    $listener.Stop()
    # A porta zero permite que o Windows reserve uma porta livre atomicamente.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try { $listener.Start() } catch {
        $listener.Stop()
        throw 'Nao foi possivel iniciar o mapa local. Verifique se algum programa de seguranca bloqueou o PowerShell.'
    }
    Write-Host "A porta $Port esta indisponivel. Usando outra porta livre."
}
$Port = $listener.LocalEndpoint.Port
$url = "http://127.0.0.1:$Port/percurso.html"
Write-Host "Mapa disponivel em $url"
Write-Host 'Mantenha esta janela aberta enquanto usa o mapa. Feche para encerrar.'
try {
    if (-not $NoBrowser) { Start-Process $url }
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 3000
            $client.SendTimeout = 3000
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            $request = $reader.ReadLine()
            $headerCount = 0
            do { $line = $reader.ReadLine(); $headerCount++ } while ($line -and $headerCount -lt 100)
            if ($request -match '^GET /(?:percurso\.html)?(?:\?[^ ]*)? HTTP/1\.[01]$') {
                $status = '200 OK'
                $body = [IO.File]::ReadAllBytes($page)
                $contentType = 'text/html; charset=utf-8'
            } else {
                $status = '404 Not Found'
                $body = [Text.Encoding]::UTF8.GetBytes('Pagina nao encontrada.')
                $contentType = 'text/plain; charset=utf-8'
            }
            $headers = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nReferrer-Policy: strict-origin-when-cross-origin`r`nConnection: close`r`n`r`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($headers)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Write($body, 0, $body.Length)
            $stream.Flush()
        } catch { Write-Warning 'Uma conexao foi interrompida. O mapa continua disponivel.' }
        finally { $client.Dispose() }
    }
} finally { $listener.Stop() }
