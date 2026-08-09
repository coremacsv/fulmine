# =====================================================================
#
#   FULMINE  -  ottimizzazione prestazioni per Windows
#   Versione 1.0  -  by lozy
#
#   Ottimizza piano energetico, pianificazione GPU, effetti visivi,
#   app in background, priorita' dei processi, servizi e rete con un
#   doppio clic, in tre modalita' (Prestazioni / Qualita' / Bilanciata),
#   piu' un Ripristino che torna esattamente a come era prima.
#
#   REGOLA FERREA: prima di cambiare qualsiasi cosa, salva il valore
#   ORIGINALE in un backup che non viene mai sovrascritto. Ogni
#   modifica e' quindi reversibile con un clic (modalita' Ripristina).
#
#   NON tocca MAI l'antivirus o il firewall: dopo un'infezione vera,
#   "piu' veloce" non vale "meno sicuro". Nessuna eccezione.
#
# =====================================================================

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$VERSIONE = '1.0'

function Ok($m)      { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Nota($m)    { Write-Host "  [ .. ] $m" -ForegroundColor Gray }
function Fatto($m)   { Write-Host "  [ >> ] $m" -ForegroundColor Cyan }
function Avviso($m)  { Write-Host "  [ !! ] $m" -ForegroundColor Yellow }
function Riavvio($m) { Write-Host "  [ R+ ] $m" -ForegroundColor Magenta; [void]$script:serveRiavvio.Add($m) }
$serveRiavvio = New-Object System.Collections.ArrayList

function DischiFissi {
    $d = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -and $_.DriveType -eq 'Fixed' }
    if (-not $d) { $d = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Free } }
    return $d
}

# =====================================================================
#  BACKUP  -  cattura lo stato ORIGINALE una volta sola. Non si sovra-
#  scrive mai: e' il punto a cui Ripristina torna sempre, anche dopo
#  piu' esecuzioni di Fulmine in modalita' diverse.
# =====================================================================
$cartellaStato = Join-Path $env:LOCALAPPDATA 'Fulmine'
$fileBackup = Join-Path $cartellaStato 'backup-originale.json'

function LeggiValore($percorso, $nome, $default) {
    $v = Get-ItemProperty -Path $percorso -Name $nome -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $default }
    return $v.$nome
}

function CatturaStatoAttuale {
    $b = [ordered]@{}
    $b.creato = (Get-Date).ToString('o')

    $b.pianoEnergetico = (powercfg /getactivescheme) -replace '.*: ([0-9a-f-]{36}).*', '$1'

    $b.hags = LeggiValore 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $null

    $b.visualFx = LeggiValore 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $null

    $b.backgroundApps = LeggiValore 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' $null

    $b.gameDvr = LeggiValore 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $null
    $b.gameBarAutoGameMode = LeggiValore 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' $null
    $b.gameBarShowStartup = LeggiValore 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' $null

    $sm = Get-Service -Name SysMain -ErrorAction SilentlyContinue
    if ($sm) { $b.sysMainStart = (Get-CimInstance Win32_Service -Filter "Name='SysMain'").StartMode }

    $b.win32PrioritySeparation = LeggiValore 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' $null

    $b.fseGlobal = LeggiValore 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' $null
    $b.fseHonorUser = LeggiValore 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' $null

    $nic = @()
    foreach ($a in (Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue)) {
        $nic += @{ instanza = $a.InstanceName; abilitato = $a.Enable }
    }
    $b.nic = $nic

    return $b
}

function Backup {
    if (-not (Test-Path -LiteralPath $cartellaStato)) { New-Item -ItemType Directory -Path $cartellaStato -Force | Out-Null }
    if (Test-Path -LiteralPath $fileBackup) {
        $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
        Nota "Backup originale gia' presente (creato il $([datetime]$b.creato | ForEach-Object { $_.ToString('dd/MM/yyyy HH:mm') })): non lo tocco."
        return
    }
    $stato = CatturaStatoAttuale
    $stato | ConvertTo-Json -Depth 6 | Out-File -FilePath $fileBackup -Encoding utf8
    Ok "Stato originale salvato: potrai sempre tornare qui con Ripristina (opzione 4)."
}

# =====================================================================
#  RILEVAMENTO  -  hardware e stato di partenza
# =====================================================================
function RilevaSchedaVideo {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual' } | Select-Object -First 1
    if (-not $gpu) { return $null }
    $vendor = 'sconosciuta'
    if ($gpu.Name -match 'NVIDIA|GeForce|RTX|GTX') { $vendor = 'NVIDIA' }
    elseif ($gpu.Name -match 'AMD|Radeon') { $vendor = 'AMD' }
    elseif ($gpu.Name -match 'Intel') { $vendor = 'Intel' }
    return @{ Nome = $gpu.Name; Vendor = $vendor; Driver = $gpu.DriverVersion; Data = $gpu.DriverDate }
}

function StampaSuggerimentoGPU($gpu) {
    if (-not $gpu) { Nota "Nessuna scheda video dedicata rilevata."; return }
    Nota "Scheda video: $($gpu.Nome)"
    switch ($gpu.Vendor) {
        'NVIDIA' {
            Nota "  Pannello proprietario (Fulmine non puo' toccarlo, e' un formato privato NVIDIA):"
            Nota "  tasto destro sul Desktop > Pannello di controllo NVIDIA > Gestione impostazioni 3D"
            Nota "  > scheda Impostazioni globali > 'Modalita' di gestione alimentazione' > 'Preferisci prestazioni massime'"
        }
        'AMD' {
            Nota "  Pannello proprietario (Fulmine non puo' toccarlo, e' un formato privato AMD):"
            Nota "  apri AMD Software > Prestazioni > Tuning > imposta il profilo su 'Prestazioni'"
        }
        'Intel' {
            Nota "  apri 'Intel Graphics Command Center' > Prestazioni, se installato."
        }
        default { Nota "  marca non riconosciuta: cerca il pannello di controllo della tua scheda video." }
    }
}

# =====================================================================
#  AZIONI  -  ognuna stampa cosa ha trovato e cosa ha cambiato
# =====================================================================

function ImpostaPianoEnergetico($modalita) {
    $elenco = powercfg /list
    if ($modalita -eq 'prestazioni') {
        $ultimate = $elenco | Select-String '([0-9a-f-]{36}).*Prestazioni elevate personalizzate|Ultimate Performance' | Select-Object -First 1
        if (-not $ultimate) {
            $creato = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
            $ultimate = powercfg /list | Select-String '([0-9a-f-]{36}).*Prestazioni elevate personalizzate|Ultimate Performance' | Select-Object -First 1
        }
        if ($ultimate) {
            $guid = [regex]::Match($ultimate.Line, '([0-9a-f-]{36})').Value
            powercfg /setactive $guid
            Fatto "Piano energetico -> Prestazioni elevate personalizzate (il piu' aggressivo che Windows offre)"
        } else {
            powercfg /setactive SCHEME_MIN
            Fatto "Piano energetico -> Prestazioni elevate"
        }
    } elseif ($modalita -eq 'qualita') {
        powercfg /setactive SCHEME_MIN
        Fatto "Piano energetico -> Prestazioni elevate"
    } else {
        powercfg /setactive SCHEME_BALANCED
        Fatto "Piano energetico -> Bilanciato (predefinito Windows)"
    }
}

function ImpostaHAGS($attiva) {
    $percorso = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    $valore = if ($attiva) { 2 } else { 0 }
    $attuale = LeggiValore $percorso 'HwSchMode' 0
    if ($attuale -eq $valore) { Ok "Pianificazione GPU accelerata da hardware: gia' come richiesto"; return }
    Set-ItemProperty -Path $percorso -Name 'HwSchMode' -Value $valore -Type DWord -Force
    Fatto "Pianificazione GPU accelerata da hardware -> $(if($attiva){'attivata'}else{'disattivata'})"
    Riavvio "La pianificazione GPU richiede un riavvio per avere effetto."
}

function ImpostaEffettiVisivi($modalita) {
    # 2 = migliori prestazioni (disattiva animazioni/trasparenze/ombre)
    # 1 = miglior aspetto (le tiene tutte)
    # 0 = lascia scegliere a Windows (default)
    $valore = switch ($modalita) { 'prestazioni' {2} 'qualita' {1} default {0} }
    $percorso = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if (-not (Test-Path $percorso)) { New-Item -Path $percorso -Force | Out-Null }
    Set-ItemProperty -Path $percorso -Name 'VisualFXSetting' -Value $valore -Type DWord -Force
    $etichetta = switch ($valore) { 2 {'Migliori prestazioni'} 1 {'Miglior aspetto'} default {'Lascia scegliere a Windows'} }
    Fatto "Effetti visivi -> $etichetta"
}

function ImpostaAppInBackground($blocca) {
    $percorso = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
    if (-not (Test-Path $percorso)) { New-Item -Path $percorso -Force | Out-Null }
    Set-ItemProperty -Path $percorso -Name 'GlobalUserDisabled' -Value ([int]$blocca) -Type DWord -Force
    Fatto "App in background (dal Microsoft Store) -> $(if($blocca){'bloccate'}else{'consentite'})"
}

function ImpostaGameBar($modalita) {
    $p1 = 'HKCU:\System\GameConfigStore'
    $p2 = 'HKCU:\Software\Microsoft\GameBar'
    foreach ($p in @($p1,$p2)) { if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null } }
    if ($modalita -eq 'prestazioni') {
        Set-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $p2 -Name 'AllowAutoGameMode' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $p2 -Name 'ShowStartupPanel' -Value 0 -Type DWord -Force
        Fatto "Game Bar -> registrazione in background DISATTIVATA (libera risorse), Game Mode attivo"
    } elseif ($modalita -eq 'qualita') {
        Set-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $p2 -Name 'AllowAutoGameMode' -Value 1 -Type DWord -Force
        Fatto "Game Bar -> registrazione ATTIVA (utile per catturare clip in alta qualita')"
    } else {
        Set-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -Value 1 -Type DWord -Force
        Fatto "Game Bar -> valori predefiniti di Windows"
    }
}

function ImpostaSysMain($disattiva, $ceSSD) {
    if (-not $ceSSD) { Nota "SysMain lasciato attivo: utile quando il disco di sistema e' un HDD."; return }
    $nome = if ($disattiva) { 'Manual' } else { 'Automatic' }
    $attuale = (Get-CimInstance Win32_Service -Filter "Name='SysMain'").StartMode
    if ($attuale -eq $nome) { Ok "Servizio SysMain: gia' come richiesto"; return }
    Set-Service -Name SysMain -StartupType $nome -ErrorAction SilentlyContinue
    if ($disattiva) { Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue }
    Fatto "Servizio SysMain (precaricamento app) -> $(if($disattiva){'disattivato (disco di sistema SSD, non serve)'}else{'riattivato'})"
}

function ImpostaPrioritaProcessi($modalita) {
    # 0x26 (38): quanto breve e fisso, priorita' al programma in primo piano.
    # 0x02 (2): predefinito Windows (variabile, leggero favore al primo piano).
    $valore = if ($modalita -eq 'prestazioni') { 38 } else { 2 }
    $percorso = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    $attuale = LeggiValore $percorso 'Win32PrioritySeparation' 2
    if ($attuale -eq $valore) { Ok "Priorita' dei processi: gia' come richiesto"; return }
    Set-ItemProperty -Path $percorso -Name 'Win32PrioritySeparation' -Value $valore -Type DWord -Force
    Fatto "Priorita' processi -> $(if($modalita -eq 'prestazioni'){'programma in primo piano favorito al massimo'}else{'predefinita Windows'})"
}

function ImpostaFullscreenOptimizations($abilitaGlobalmente) {
    $percorso = 'HKCU:\System\GameConfigStore'
    if (-not (Test-Path $percorso)) { New-Item -Path $percorso -Force | Out-Null }
    if ($abilitaGlobalmente) {
        Set-ItemProperty -Path $percorso -Name 'GameDVR_FSEBehaviorMode' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $percorso -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1 -Type DWord -Force
        Fatto "Ottimizzazioni schermo intero -> attive per impostazione predefinita (meglio per alt-tab/overlay)"
    } else {
        Set-ItemProperty -Path $percorso -Name 'GameDVR_FSEBehaviorMode' -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $percorso -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1 -Type DWord -Force
        Fatto "Ottimizzazioni schermo intero -> disattivate per impostazione predefinita (schermo intero esclusivo, di solito piu' FPS)"
        Nota "  Resta comunque possibile forzarle su un singolo gioco: tasto destro sull'exe > Proprieta' > Compatibilita'"
    }
}

function ImpostaRisparmioEnergiaSchedeRete($disattiva) {
    $n = 0
    foreach ($a in (Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue)) {
        try {
            $a.Enable = -not $disattiva
            Set-CimInstance -InputObject $a -ErrorAction SilentlyContinue
            $n++
        } catch { }
    }
    if ($n -gt 0) { Fatto "Risparmio energia sulle schede di rete -> $(if($disattiva){'disattivato'}else{'predefinito'}) su $n adattatori (riduce i micro-lag di rete)" }
    else { Nota "Nessuna scheda di rete compatibile trovata per questa impostazione." }
}

function PuliziaRapida {
    $liberatiMB = 0
    foreach ($c in @($env:TEMP, "$env:SystemRoot\Temp")) {
        if (Test-Path -LiteralPath $c) {
            $prima = (Get-ChildItem $c -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            Get-ChildItem $c -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            $dopo = (Get-ChildItem $c -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($prima) { $liberatiMB += [math]::Round(($prima - $dopo)/1MB) }
        }
    }
    Fatto "File temporanei ripuliti: circa $liberatiMB MB liberati"
}

function TrimDischiSSD($dischi) {
    foreach ($d in $dischi) {
        $fisico = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $d.DriveLetter -ErrorAction SilentlyContinue).DiskNumber }
        if ($fisico -and $fisico.MediaType -eq 'SSD') {
            Optimize-Volume -DriveLetter $d.DriveLetter -ReTrim -ErrorAction SilentlyContinue
            Fatto "TRIM eseguito su $($d.DriveLetter): (SSD)"
        }
    }
}

# =====================================================================
#  MENU
# =====================================================================
function Centrato($testo, $L) {
    $sx = [int](($L - $testo.Length) / 2); if ($sx -lt 0) { $sx = 0 }
    $dx = $L - $sx - $testo.Length; if ($dx -lt 0) { $dx = 0 }
    return "   |" + (" " * $sx) + $testo + (" " * $dx) + "|"
}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
Clear-Host
Write-Host ""
$arte = @(
    '███████╗██╗   ██╗██╗     ███╗   ███╗██╗███╗   ██╗███████╗',
    '██╔════╝██║   ██║██║     ████╗ ████║██║████╗  ██║██╔════╝',
    '█████╗  ██║   ██║██║     ██╔████╔██║██║██╔██╗ ██║█████╗  ',
    '██╔══╝  ██║   ██║██║     ██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ',
    '██║     ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║███████╗',
    '╚═╝      ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝'
)
$colori = @('Yellow','Yellow','DarkYellow','DarkYellow','Red','DarkRed')
for ($i=0; $i -lt $arte.Count; $i++) { Write-Host ("  " + $arte[$i]) -ForegroundColor $colori[$i] }
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "[ " -NoNewline -ForegroundColor DarkGray
Write-Host "ottimizzazione prestazioni per Windows" -NoNewline -ForegroundColor White
Write-Host " ]" -NoNewline -ForegroundColor DarkGray
Write-Host "  v$VERSIONE" -ForegroundColor DarkYellow
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
Write-Host ("  " + (" " * 46) + "~ by lozy ~") -ForegroundColor DarkGray
Write-Host ""

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "  ATTENZIONE: non stai eseguendo come amministratore." -ForegroundColor Yellow
    Write-Host "  La maggior parte delle ottimizzazioni non potra' essere applicata." -ForegroundColor Yellow
    Write-Host "  Chiudi e avvia FULMINE.bat." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Rilevamento in corso..." -ForegroundColor Gray
$gpu = RilevaSchedaVideo
$dischi = DischiFissi
$ceSSD = $false
foreach ($d in $dischi) {
    $fisico = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $d.DriveLetter -ErrorAction SilentlyContinue).DiskNumber }
    if ($fisico -and $fisico.MediaType -eq 'SSD' -and $d.DriveLetter -eq $env:SystemDrive[0]) { $ceSSD = $true }
}
$ram = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1 -ExpandProperty Speed
Write-Host ""
StampaSuggerimentoGPU $gpu
Nota "Disco di sistema: $(if($ceSSD){'SSD'}else{'HDD o non rilevato'})"
if ($ram -and $ram -le 2666) {
    Avviso "RAM a $ram MHz: se il tuo kit e' tarato per una velocita' superiore, il profilo"
    Avviso "XMP/DOCP non e' attivo. Si attiva dal BIOS (tasto Canc all'avvio), non da qui:"
    Avviso "e' un'impostazione della scheda madre, Windows non puo' cambiarla."
}
Write-Host ""

Write-Host "  Cosa vuoi fare?" -ForegroundColor White
Write-Host ""
Write-Host "    [1]  PRESTAZIONI (FPS)" -ForegroundColor Red
Write-Host "         Massimo FPS: piano energetico al massimo, GPU scheduling," -ForegroundColor DarkGray
Write-Host "         niente overlay/registrazione, app in background bloccate," -ForegroundColor DarkGray
Write-Host "         priorita' al gioco, effetti visivi minimi." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [2]  QUALITA' VISIVA" -ForegroundColor Cyan
Write-Host "         Priorita' alla resa: effetti visivi al massimo, overlay" -ForegroundColor DarkGray
Write-Host "         attivo per registrare, prestazioni comunque alte." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [3]  BILANCIATA" -ForegroundColor Green
Write-Host "         Valori predefiniti di Windows, via di mezzo sensata." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [4]  RIPRISTINA" -ForegroundColor White
Write-Host "         Torna esattamente a come era PRIMA di usare Fulmine." -ForegroundColor DarkGray
Write-Host ""
Write-Host "    [0]  Esci" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Ogni modifica e' reversibile: il primo avvio salva lo stato" -ForegroundColor Gray
Write-Host "  originale, che Ripristina puo' sempre riportare indietro." -ForegroundColor Gray
Write-Host "  L'antivirus e il firewall non vengono mai toccati." -ForegroundColor Gray
Write-Host ""
$scelta = Read-Host "  Scrivi 1, 2, 3, 4 o 0 e premi INVIO"
if ($scelta -eq '0') { exit }
if ($scelta -notin @('1','2','3','4')) { Write-Host "  Scelta non valida." -ForegroundColor Red; Read-Host; exit }

if (-not $admin -and $scelta -ne '4') {
    Write-Host ""
    Write-Host "  Senza permessi di amministratore posso applicare solo le" -ForegroundColor Yellow
    Write-Host "  impostazioni utente (effetti visivi, Game Bar). Continuo comunque." -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray

if ($scelta -eq '4') {
    Write-Host "  RIPRISTINO IN CORSO" -ForegroundColor White
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
    Write-Host ""
    if (-not (Test-Path -LiteralPath $fileBackup)) {
        Write-Host "  Nessun backup trovato: Fulmine non ha ancora modificato nulla su" -ForegroundColor Yellow
        Write-Host "  questo PC, quindi non c'e' niente da ripristinare." -ForegroundColor Yellow
    } else {
        $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
        Nota "Backup del $([datetime]$b.creato | ForEach-Object { $_.ToString('dd/MM/yyyy HH:mm') })"
        if ($b.pianoEnergetico) { powercfg /setactive $b.pianoEnergetico; Fatto "Piano energetico ripristinato" }
        if ($null -ne $b.hags) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value $b.hags -Type DWord -Force
            Fatto "Pianificazione GPU ripristinata"; Riavvio "La pianificazione GPU richiede un riavvio."
        }
        if ($null -ne $b.visualFx) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value $b.visualFx -Type DWord -Force
            Fatto "Effetti visivi ripristinati"
        }
        if ($null -ne $b.backgroundApps) {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value $b.backgroundApps -Type DWord -Force
            Fatto "App in background ripristinate"
        }
        if ($null -ne $b.gameDvr) {
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value $b.gameDvr -Type DWord -Force
            Fatto "Game Bar ripristinata"
        }
        if ($b.sysMainStart) {
            Set-Service -Name SysMain -StartupType $b.sysMainStart -ErrorAction SilentlyContinue
            if ($b.sysMainStart -eq 'Automatic') { Start-Service -Name SysMain -ErrorAction SilentlyContinue }
            Fatto "Servizio SysMain ripristinato"
        }
        if ($null -ne $b.win32PrioritySeparation) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value $b.win32PrioritySeparation -Type DWord -Force
            Fatto "Priorita' processi ripristinata"
        }
        if ($null -ne $b.fseGlobal) {
            Set-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value $b.fseGlobal -Type DWord -Force
            Fatto "Ottimizzazioni schermo intero ripristinate"
        }
        foreach ($n in $b.nic) {
            try {
                $obj = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
                       Where-Object { $_.InstanceName -eq $n.instanza }
                if ($obj) { $obj.Enable = $n.abilitato; Set-CimInstance -InputObject $obj -ErrorAction SilentlyContinue }
            } catch { }
        }
        if ($b.nic -and $b.nic.Count -gt 0) { Fatto "Risparmio energia delle schede di rete ripristinato" }
        Write-Host ""
        Write-Host "  Tutto riportato allo stato precedente a Fulmine." -ForegroundColor Green
    }
} else {
    $modalita = switch ($scelta) { '1' {'prestazioni'} '2' {'qualita'} '3' {'bilanciata'} }
    $nomeModalita = switch ($scelta) { '1' {'PRESTAZIONI (FPS)'} '2' {'QUALITA'' VISIVA'} '3' {'BILANCIATA'} }
    Write-Host "  MODALITA': $nomeModalita" -ForegroundColor White
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
    Write-Host ""

    Backup

    ImpostaPianoEnergetico $modalita
    ImpostaHAGS ($modalita -ne 'bilanciata')
    ImpostaEffettiVisivi $modalita
    ImpostaAppInBackground ($modalita -eq 'prestazioni')
    ImpostaGameBar $modalita
    ImpostaSysMain ($modalita -eq 'prestazioni') $ceSSD
    ImpostaPrioritaProcessi $modalita
    ImpostaFullscreenOptimizations ($modalita -ne 'prestazioni')
    ImpostaRisparmioEnergiaSchedeRete ($modalita -eq 'prestazioni')

    if ($modalita -eq 'prestazioni') {
        Write-Host ""
        PuliziaRapida
        TrimDischiSSD $dischi
    }

    Write-Host ""
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
    Write-Host "  FATTO" -ForegroundColor Green
    if ($serveRiavvio.Count -gt 0) {
        Write-Host ""
        Write-Host "  Per completare, riavvia il PC:" -ForegroundColor Magenta
        foreach ($r in $serveRiavvio) { Write-Host "    - $r" -ForegroundColor Magenta }
    }
    Write-Host ""
    Write-Host "  Per tornare indietro in qualsiasi momento: FULMINE.bat > opzione 4." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Fulmine v$VERSIONE" -NoNewline -ForegroundColor DarkYellow
Write-Host "  ~  " -NoNewline -ForegroundColor DarkGray
Write-Host "by " -NoNewline -ForegroundColor DarkGray
Write-Host "lozy" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Premi INVIO per chiudere..." -ForegroundColor DarkGray
Read-Host
