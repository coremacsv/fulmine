# =====================================================================
#
#   FULMINE  -  il PC a razzo con un clic
#   Versione 1.3  -  by lozy
#
#   Un doppio clic su FULMINE.bat: scansiona il PC e sistema da solo
#   tutto quello che rallenta (monitor sotto la frequenza massima,
#   programmi inutili all'avvio, piano energetico, GPU, Game Bar,
#   priorita', rete, file temporanei...). Alla fine un rapporto dice
#   cosa ha trovato, cosa ha sistemato e cosa resta da fare (BIOS, driver).
#   Ripristina.bat torna esattamente a come era prima.
#
#   REGOLA FERREA: prima di cambiare qualsiasi cosa, salva il valore
#   ORIGINALE in un backup che non viene mai sovrascritto. Ogni
#   impostazione e' quindi reversibile con un clic (modalita' Ripristina).
#   Unica eccezione: i file temporanei cancellati non tornano indietro.
#
#   NON tocca MAI l'antivirus o il firewall: dopo un'infezione vera,
#   "piu' veloce" non vale "meno sicuro". Nessuna eccezione.
#
# =====================================================================

param(
    [switch]$Ripristina,   # torna allo stato di prima di Fulmine
    [switch]$Prova,        # controlla tutto ma non cambia niente
    [switch]$NoPause       # niente attesa finale (test)
)
$script:Prova = [bool]$Prova

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$VERSIONE = '1.3'

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
        if (-not $b -or -not $b.creato) { return $false }
        Nota "Backup originale gia' presente (creato il $([datetime]$b.creato | ForEach-Object { $_.ToString('dd/MM/yyyy HH:mm') })): non lo tocco."
        return $true
    }
    $stato = CatturaStatoAttuale
    $stato | ConvertTo-Json -Depth 6 | Out-File -FilePath $fileBackup -Encoding utf8
    if (-not (Test-Path -LiteralPath $fileBackup)) { return $false }
    Ok "Stato originale salvato: potrai sempre tornare qui con Ripristina.bat"
    return $true
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
    if ($modalita -eq 'prestazioni') {
        # Il piano "Ultimate Performance" duplicato si chiama in modo diverso in
        # ogni lingua di Windows ("Prestazioni eccellenti" in italiano, "Ultimate
        # Performance" in inglese...): cercarlo per nome non funziona su "tutti i
        # PC Windows" come deve fare Fulmine. Il GUID invece non cambia mai lingua,
        # quindi lo salviamo noi al momento della creazione e lo riusiamo dopo -
        # senza, ogni avvio di Fulmine in questa modalita' ne creerebbe uno nuovo,
        # riempiendo l'elenco dei piani energetici di doppioni.
        $guid = $null
        if (Test-Path -LiteralPath $fileBackup) {
            $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
            if ($b.ultimatePerfGuid -and (powercfg /list) -match [regex]::Escape($b.ultimatePerfGuid)) {
                $guid = $b.ultimatePerfGuid
            }
        }
        if (-not $guid) {
            $creato = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
            $guid = [regex]::Match(($creato -join ' '), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})').Value
            if ($guid -and (Test-Path -LiteralPath $fileBackup)) {
                $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
                $b | Add-Member -NotePropertyName 'ultimatePerfGuid' -NotePropertyValue $guid -Force
                $b | ConvertTo-Json -Depth 6 | Out-File -FilePath $fileBackup -Encoding utf8
            }
        }
        if ($guid) {
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
    # 2 = attiva, 1 = spenta. Senza il valore decide Windows: e' il vero "predefinito".
    $attuale = LeggiValore $percorso 'HwSchMode' $null
    if ($attiva) {
        if ($attuale -eq 2) { Ok "Pianificazione GPU accelerata da hardware: gia' come richiesto"; return }
        Set-ItemProperty -Path $percorso -Name 'HwSchMode' -Value 2 -Type DWord -Force
        Fatto "Pianificazione GPU accelerata da hardware -> attivata"
    } else {
        if ($null -eq $attuale) { Ok "Pianificazione GPU accelerata da hardware: gia' sul predefinito di Windows"; return }
        Remove-ItemProperty -Path $percorso -Name 'HwSchMode' -Force
        Fatto "Pianificazione GPU accelerata da hardware -> predefinito di Windows"
    }
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
    # Questa classe elenca anche hub USB, tastiere e altro: si toccano solo le schede di rete.
    $schede = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { $_.PnPDeviceID } | Where-Object { $_ })
    foreach ($a in (Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue)) {
        $eScheda = $false
        foreach ($id in $schede) { if ($a.InstanceName.StartsWith($id, [StringComparison]::OrdinalIgnoreCase)) { $eScheda = $true } }
        if (-not $eScheda) { continue }
        try {
            $a.Enable = -not $disattiva
            Set-CimInstance -InputObject $a -ErrorAction Stop
            $n++
        } catch { }
    }
    if ($n -gt 0) { Fatto "Risparmio energia sulle schede di rete -> $(if($disattiva){'disattivato'}else{'predefinito'}) su $n adattatori (riduce i micro-lag di rete)" }
    else { Nota "Nessuna scheda di rete compatibile trovata per questa impostazione." }
}

# I file recenti possono servire a un'installazione o a un programma aperto. I
# collegamenti a cartelle si saltano: seguirli cancellerebbe file fuori dalla cartella.
function PulisciCartellaTemp($cartella, $limite) {
    $liberati = 0L
    foreach ($x in (Get-ChildItem -LiteralPath $cartella -Force -ErrorAction SilentlyContinue)) {
        if ($x.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($x.PSIsContainer) {
            $vecchia = $x.LastWriteTime -lt $limite
            $liberati += PulisciCartellaTemp $x.FullName $limite
            if ($vecchia) { try { [IO.Directory]::Delete($x.FullName) } catch { } }
        } elseif ($x.LastWriteTime -lt $limite) {
            $dimensione = $x.Length
            Remove-Item -LiteralPath $x.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $x.FullName)) { $liberati += $dimensione }
        }
    }
    return $liberati
}
function PuliziaRapida {
    $limite = (Get-Date).AddDays(-7)
    $liberati = 0L
    foreach ($c in @($env:TEMP, "$env:SystemRoot\Temp")) {
        if (Test-Path -LiteralPath $c) { $liberati += PulisciCartellaTemp $c $limite }
    }
    Fatto "File temporanei piu' vecchi di 7 giorni ripuliti: circa $([math]::Round($liberati/1MB)) MB liberati"
}
$ripristiniFalliti = 0
function RipristinaValore($percorso, $nome, $valore, $etichetta) {
    try {
        if ($null -eq $valore) {
            # Il valore in origine non esisteva: tornare indietro vuol dire toglierlo.
            if ($null -ne (Get-ItemProperty -Path $percorso -Name $nome -ErrorAction SilentlyContinue)) {
                Remove-ItemProperty -Path $percorso -Name $nome -Force -ErrorAction Stop
            }
        } else {
            if (-not (Test-Path $percorso)) { New-Item -Path $percorso -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $percorso -Name $nome -Value $valore -Type DWord -Force -ErrorAction Stop
        }
        if ($etichetta) { Fatto "$etichetta ripristinati" }
    } catch {
        $script:ripristiniFalliti++
        Avviso "Non sono riuscito a ripristinare $nome : $($_.Exception.Message)"
    }
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
#  SCANSIONE E CORREZIONE  (novita' 1.2)
#  Ogni controllo registra il problema trovato e, se lo sistema da
#  solo, la soluzione applicata. Quello che il software non puo' fare
#  (BIOS, driver) finisce in "Da fare tu" con le istruzioni.
# =====================================================================
$script:Trovati   = New-Object System.Collections.ArrayList
$script:Sistemati = New-Object System.Collections.ArrayList
$script:DaFare    = New-Object System.Collections.ArrayList
function Problema($m)  { [void]$script:Trovati.Add($m) }
function Risolto($m)   { [void]$script:Sistemati.Add($m); Fatto $m }
function TocaATe($m)   { [void]$script:DaFare.Add($m); Avviso $m }

# --- Monitor: frequenza di aggiornamento ------------------------------
if (-not ('FulmineSchermi' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class FulmineSchermi {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string n; public short spec,drv,size,extra; public int fields;
    public int px,py; public int orient; public int fixedo; public short col,dup,yres,tt,coll;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string fn; public short lp; public int bpp,w,h,dflags,freq,icm,ii,mt,dt,r1,r2,pw2,ph2; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DD { public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Str;
    public int Flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettingsW(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevicesW(string dev, int i, ref DD dd, int f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsExW(string dev, ref DEVMODE dm, IntPtr h, int flags, IntPtr p);
  // Restituisce: nome|monitor|larghezza|altezza|bit|Hz attuali|Hz massimi alla stessa risoluzione
  public static List<string> Elenco() { var r = new List<string>();
    for (int i=0;i<16;i++) { var dd=new DD(); dd.cb=Marshal.SizeOf(dd); if(!EnumDisplayDevicesW(null,i,ref dd,0)) break; if((dd.Flags&1)==0) continue;
      var m=new DEVMODE(); m.size=(short)Marshal.SizeOf(m); if(!EnumDisplaySettingsW(dd.Name,-1,ref m)) continue;
      int max=0; for(int j=0;;j++){ var t=new DEVMODE(); t.size=(short)Marshal.SizeOf(t); if(!EnumDisplaySettingsW(dd.Name,j,ref t)) break;
        if(t.w==m.w && t.h==m.h && t.bpp==m.bpp && t.freq>max) max=t.freq; }
      var mon=new DD(); mon.cb=Marshal.SizeOf(mon); EnumDisplayDevicesW(dd.Name,0,ref mon,0);
      r.Add(dd.Name+"|"+mon.Str+"|"+m.w+"|"+m.h+"|"+m.bpp+"|"+m.freq+"|"+max); }
    return r; }
  // Imposta la frequenza mantenendo la risoluzione. 0 = ok, 1 = serve riavvio, <0 = errore.
  public static int Frequenza(string dev, int freq) {
    var m=new DEVMODE(); m.size=(short)Marshal.SizeOf(m); if(!EnumDisplaySettingsW(dev,-1,ref m)) return -100;
    m.freq=freq; m.fields=0x80000|0x100000|0x400000; // larghezza, altezza, frequenza
    return ChangeDisplaySettingsExW(dev, ref m, IntPtr.Zero, 0x01, IntPtr.Zero); }
}
"@
}
function ElencoSchermi {
    foreach ($r in [FulmineSchermi]::Elenco()) {
        $p = $r -split '\|'
        [pscustomobject]@{ Nome = $p[0]; Monitor = $p[1]; L = [int]$p[2]; A = [int]$p[3]; Bit = [int]$p[4]; Hz = [int]$p[5]; Max = [int]$p[6] }
    }
}
function CorreggiFrequenzaMonitor {
    $k = 0
    foreach ($s in @(ElencoSchermi)) {
        $k++
        $etichetta = "Monitor $k ($($s.L)x$($s.A))"
        if ($s.Max -le $s.Hz) { Ok "${etichetta}: gia' alla frequenza massima ($($s.Hz) Hz)"; continue }
        Problema "$etichetta a $($s.Hz) Hz, ma supporta $($s.Max) Hz"
        if ($script:Prova) { Nota "[PROVA] porterei $etichetta da $($s.Hz) a $($s.Max) Hz"; continue }
        $esito = [FulmineSchermi]::Frequenza($s.Nome, $s.Max)
        $dopo = @(ElencoSchermi | Where-Object Nome -eq $s.Nome)
        if ($esito -ge 0 -and $dopo -and $dopo[0].Hz -eq $s.Max) { Risolto "$etichetta -> da $($s.Hz) a $($s.Max) Hz" }
        elseif ($esito -eq 1) { Risolto "$etichetta -> $($s.Max) Hz (attivo dopo il riavvio)"; Riavvio 'Nuova frequenza del monitor.' }
        else { TocaATe "${etichetta}: imposta $($s.Max) Hz da Impostazioni > Sistema > Schermo > Schermo avanzato" }
    }
}

# --- Programmi all'avvio: solo una lista SICURA ------------------------
# Solo programmi Microsoft che partono da soli senza motivo. NON tocca mai:
# Discord, launcher dei giochi, software di mouse/tastiere/cuffie (iCUE,
# G HUB, Stream Deck...), antivirus, driver, OneDrive (backup dei file).
$script:AvvioRun  = '^(Teams|com\.squirrel\.Teams\.Teams|MicrosoftEdgeAutoLaunch_[0-9A-F]+|Skype.*|Cortana)$'
$script:AvvioStore = '^(MSTeams|MicrosoftTeams|Microsoft\.MicrosoftOfficeHub|MicrosoftWindows\.CrossDevice|Microsoft\.YourPhone|Microsoft\.Copilot|Microsoft\.Windows\.Ai\.Copilot\.Provider|Microsoft\.Todos|Microsoft\.PowerAutomateDesktop|Microsoft\.549981C3F5F10|Microsoft\.SkypeApp|Microsoft\.M365Companions)_'
$script:ChiaviApproved = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
                           'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run')
$script:ChiaveStore = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'

function NomeLeggibile($n) {
    switch -Regex ($n) {
        'Teams'          { 'Microsoft Teams'; break }
        'EdgeAutoLaunch' { 'Microsoft Edge (avvio automatico)'; break }
        'OfficeHub'      { 'Microsoft 365 / Office'; break }
        'CrossDevice|YourPhone' { 'Collegamento al telefono'; break }
        'Copilot'        { 'Copilot'; break }
        'Todos'          { 'Microsoft To Do'; break }
        'PowerAutomate'  { 'Power Automate'; break }
        '549981C3F5F10|Cortana' { 'Cortana'; break }
        'Skype'          { 'Skype'; break }
        'M365Companions' { 'Microsoft 365 Companions'; break }
        default          { $n }
    }
}

# Elenco dei programmi della lista presenti sul PC, con il loro stato attuale.
function ElencoAvvioInutile {
    $runKeys = @{ 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' = $script:ChiaviApproved[0]; 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' = $script:ChiaviApproved[1] }
    foreach ($rk in $runKeys.Keys) {
        $vals = Get-ItemProperty $rk -ErrorAction SilentlyContinue
        if (-not $vals) { continue }
        foreach ($nome in ($vals.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object Name)) {
            if ($nome -notmatch $script:AvvioRun) { continue }
            $ap = (Get-ItemProperty $runKeys[$rk] -Name $nome -ErrorAction SilentlyContinue).$nome
            [pscustomobject]@{ Tipo = 'run'; Chiave = $runKeys[$rk]; Nome = $nome; Attivo = (-not $ap -or ($ap[0] -band 1) -eq 0); Originale = $(if ($ap) { [Convert]::ToBase64String([byte[]]$ap) } else { $null }) }
        }
    }
    foreach ($pkg in (Get-ChildItem $script:ChiaveStore -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $script:AvvioStore })) {
        foreach ($task in (Get-ChildItem $pkg.PSPath -ErrorAction SilentlyContinue)) {
            $st = (Get-ItemProperty $task.PSPath -Name State -ErrorAction SilentlyContinue).State
            if ($null -eq $st) { continue }
            [pscustomobject]@{ Tipo = 'store'; Chiave = $task.PSPath; Nome = $pkg.PSChildName; Attivo = ($st -eq 2); Originale = $st }
        }
    }
}

function DisattivaAvvioInutile {
    $attivi = @(ElencoAvvioInutile | Where-Object Attivo)
    if ($attivi.Count -eq 0) { Ok "Programmi inutili all'avvio: nessuno attivo"; return }
    Problema "$($attivi.Count) programmi inutili partono all'avvio di Windows"
    foreach ($a in $attivi) {
        $nome = NomeLeggibile $a.Nome
        if ($script:Prova) { Nota "[PROVA] toglierei dall'avvio: $nome"; continue }
        try {
            if ($a.Tipo -eq 'run') {
                if (-not (Test-Path $a.Chiave)) { New-Item -Path $a.Chiave -Force | Out-Null }
                $val = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc()))
                Set-ItemProperty -Path $a.Chiave -Name $a.Nome -Value $val -Type Binary -Force -ErrorAction Stop
            } else {
                Set-ItemProperty -Path $a.Chiave -Name State -Value 1 -Type DWord -Force -ErrorAction Stop
            }
            Risolto "Avvio automatico disattivato: $nome"
        } catch { TocaATe "Non riesco a togliere $nome dall'avvio: Gestione attivita' > App di avvio > Disabilita" }
    }
}

# --- Driver della scheda video -------------------------------------------
function ControllaDriverVideo($gpu) {
    if (-not $gpu -or -not $gpu.Data) { return }
    $data = $gpu.Data; if ($data -is [string]) { try { $data = [Management.ManagementDateTimeConverter]::ToDateTime($data) } catch { return } }
    $mesi = [int](((Get-Date) - $data).TotalDays / 30)
    if ($mesi -lt 6) { Ok "Driver scheda video aggiornato ($($data.ToString('dd/MM/yyyy')))"; return }
    Problema "Driver della scheda video vecchio di $mesi mesi ($($data.ToString('dd/MM/yyyy')))"
    $pagina = switch ($gpu.Vendor) {
        'NVIDIA' { 'https://www.nvidia.com/it-it/drivers/' }
        'AMD'    { 'https://www.amd.com/it/support/download/drivers.html' }
        'Intel'  { 'https://www.intel.it/content/www/it/it/support/detect.html' }
        default  { $null }
    }
    if ($pagina -and -not $script:Prova) { Start-Process $pagina }
    TocaATe "Aggiorna il driver della scheda video ($($gpu.Vendor))$(if ($pagina) { ": ho aperto la pagina ufficiale" })"
}

# --- Spazio sul disco di sistema ------------------------------------------
function ControllaSpazioDisco {
    $c = Get-Volume -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
    if (-not $c -or -not $c.Size) { return }
    $libero = [math]::Round($c.SizeRemaining / $c.Size * 100)
    if ($libero -ge 10) { Ok "Disco di sistema: $libero% libero"; return }
    Problema "Disco di sistema quasi pieno: solo $libero% libero"
    TocaATe "Libera spazio su $($env:SystemDrive): con meno del 10% libero Windows e i giochi rallentano"
}

# --- RAM: profilo XMP/DOCP/EXPO -------------------------------------------
function ControllaRAM {
    $moduli = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if (-not $moduli) { return }
    $attuale = ($moduli | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
    if (-not $attuale) { $attuale = ($moduli | Measure-Object Speed -Minimum).Minimum }
    # La velocita' dichiarata e' quasi sempre nel codice del modulo (es. CMW32GX4M2Z3600C18 -> 3600).
    $dichiarata = 0
    foreach ($m in $moduli) {
        foreach ($x in [regex]::Matches([string]$m.PartNumber, '(?<!\d)(2[4-9]\d\d|[3-8]\d\d\d)(?!\d)')) {
            $v = [int]$x.Value; if ($v -gt $dichiarata -and $v % 100 -in 0, 33, 66) { $dichiarata = $v }
        }
    }
    if ($dichiarata -gt 0 -and $attuale -and $dichiarata -gt ($attuale + 100)) {
        Problema "RAM a $attuale MHz invece di $dichiarata MHz: il profilo XMP/DOCP/EXPO non e' attivo"
        TocaATe "Attiva il profilo XMP/DOCP/EXPO nel BIOS (riavvia, premi Canc o F2, cerca 'XMP' o 'DOCP', scegli Profilo 1, salva con F10)"
    } else {
        Ok "RAM a $attuale MHz$(if ($dichiarata) { ' (velocita'' dichiarata raggiunta)' })"
    }
}

# =====================================================================
#  NOVITA' 1.3: portatili, doppia scheda video, giochi in finestra,
#  condivisione degli aggiornamenti, accelerazione del mouse.
# =====================================================================

# --- Portatile? ----------------------------------------------------------
function RilevaPortatile {
    $telaio = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $tipiPortatile = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    [bool]((@($telaio | Where-Object { $_ -in $tipiPortatile }).Count) -or @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count)
}

# Sul piano energetico creato da Fulmine: in carica tutto al massimo, a
# batteria niente turbo e processore libero di scendere (meno calore, piu'
# autonomia). Si tocca SOLO il piano di Fulmine, che Ripristina cancella.
function AdattaPortatile {
    if (-not $script:Portatile) { return }
    $guid = $null
    if (Test-Path -LiteralPath $fileBackup) { $guid = (Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json).ultimatePerfGuid }
    if (-not $guid -or -not ((powercfg /getactivescheme) -match [regex]::Escape($guid))) {
        Nota "Portatile: piano energetico non creato da Fulmine, lo lascio com'e' a batteria"
        return
    }
    powercfg /setdcvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE 0 | Out-Null
    powercfg /setdcvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMIN 5 | Out-Null
    powercfg /setactive $guid | Out-Null
    Risolto "Portatile: prestazioni piene in carica, a batteria turbo spento (meno calore, piu' autonomia)"
}

# --- Doppia scheda video (integrata + dedicata) ---------------------------
function ElencoGPU {
    Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec|Meta' } | ForEach-Object {
        # Le Intel Arc con numero di modello (A770, B580...) sono dedicate; 'Arc Graphics' e' l'integrata dei Core Ultra.
        $integrata = ($_.Name -match 'Intel\(R\) (UHD|HD|Iris)|^Intel.*Graphics$|Radeon\(TM\) (Graphics|Vega)|^AMD Radeon Graphics$|Radeon\(TM\) \d{3,4}M') -and ($_.Name -notmatch 'Arc\(TM\) [AB]\d{3}')
        [pscustomobject]@{ Nome = $_.Name; Integrata = $integrata }
    }
}
function TrovaGiochiInstallati {
    $cartelle = New-Object System.Collections.Generic.List[string]
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        $librerie = @($steam) + @(if (Test-Path $vdf) { [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } })
        foreach ($l in ($librerie | Select-Object -Unique)) { Get-ChildItem (Join-Path $l 'steamapps\common') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $cartelle.Add($_.FullName) } }
    }
    foreach ($r in "$env:ProgramFiles\Epic Games", "${env:ProgramFiles(x86)}\Epic Games") { Get-ChildItem $r -Directory -ErrorAction SilentlyContinue | ForEach-Object { $cartelle.Add($_.FullName) } }
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Publisher -match 'Activision|Blizzard|Electronic Arts|Riot|Ubisoft|Epic Games|Rockstar|Bethesda|CD PROJEKT|Valve' -and $_.InstallLocation -and (Test-Path $_.InstallLocation) } |
        ForEach-Object { $cartelle.Add($_.InstallLocation.TrimEnd('\')) }
    $escludi = 'unins|setup|install|crash|report|redist|vcredist|directx|dotnet|launcher|helper|updater|update|anticheat|easyanticheat|battleye|attestation|wizard|cef|webhelper|overlay|bootstrap'
    $cartelle | Select-Object -Unique | ForEach-Object {
        Get-ChildItem $_ -Filter *.exe -Recurse -Depth 2 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 5MB -and $_.BaseName -notmatch $escludi }
    } | Select-Object -First 200 -ExpandProperty FullName -Unique
}
function GpuDedicataPerGiochi {
    $gpu = @(ElencoGPU)
    if (-not (@($gpu | Where-Object Integrata).Count -and @($gpu | Where-Object { -not $_.Integrata }).Count)) {
        Ok "Scheda video: una sola (nessuna scelta tra integrata e dedicata da fare)"
        return
    }
    $dedicata = ($gpu | Where-Object { -not $_.Integrata } | Select-Object -First 1).Nome
    $chiave = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path $chiave)) { if (-not $script:Prova) { New-Item -Path $chiave -Force | Out-Null } }
    $esistenti = Get-ItemProperty $chiave -ErrorAction SilentlyContinue
    $nuovi = @(TrovaGiochiInstallati | Where-Object { -not ($esistenti -and $esistenti.PSObject.Properties[$_]) })
    if ($nuovi.Count -eq 0) { Ok "Doppia scheda video: i giochi trovati usano gia' la dedicata ($dedicata)"; return }
    Problema "PC con doppia scheda video: $($nuovi.Count) giochi potrebbero partire sulla scheda integrata"
    if ($script:Prova) { Nota "[PROVA] imposterei $($nuovi.Count) giochi sulla scheda dedicata ($dedicata)"; return }
    foreach ($exe in $nuovi) { Set-ItemProperty -Path $chiave -Name $exe -Value 'GpuPreference=2;' -Type String -Force }
    $script:GpuAggiunti = $nuovi
    Risolto "$($nuovi.Count) giochi impostati sulla scheda dedicata ($dedicata)"
    [void]$script:DaFare.Add("Giochi installati in altre cartelle: Impostazioni > Sistema > Schermo > Grafica > scegli il gioco > Prestazioni elevate")
}

# --- Ottimizzazioni per i giochi in finestra + frequenza variabile ----------
$script:ChiaveDX = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
function ImpostaOpzioneDX([hashtable]$Valori) {
    $attuale = (Get-ItemProperty $script:ChiaveDX -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue).DirectXUserGlobalSettings
    $coppie = [ordered]@{}
    foreach ($p in ([string]$attuale -split ';' | Where-Object { $_ -match '=' })) { $k, $v = $p -split '=', 2; $coppie[$k.Trim()] = $v.Trim() }
    $cambiate = @()
    foreach ($k in $Valori.Keys) { if ($coppie[$k] -ne $Valori[$k]) { $coppie[$k] = $Valori[$k]; $cambiate += $k } }
    if ($cambiate.Count -and -not $script:Prova) {
        if (-not (Test-Path $script:ChiaveDX)) { New-Item -Path $script:ChiaveDX -Force | Out-Null }
        $testo = (($coppie.Keys | ForEach-Object { "$_=$($coppie[$_])" }) -join ';') + ';'
        Set-ItemProperty -Path $script:ChiaveDX -Name DirectXUserGlobalSettings -Value $testo -Type String -Force
    }
    $cambiate
}
function OttimizzaGiochiInFinestra {
    $cambiate = @(ImpostaOpzioneDX @{ SwapEffectUpgradeEnable = '1'; VRROptimizeEnable = '1' })
    if (-not $cambiate.Count) { Ok "Ottimizzazioni per i giochi in finestra e frequenza variabile: gia' attive"; return }
    Problema "Ottimizzazioni per i giochi in finestra / frequenza variabile non attive"
    if ($script:Prova) { Nota "[PROVA] attiverei le ottimizzazioni per i giochi in finestra e la frequenza variabile"; return }
    Risolto "Ottimizzazioni per i giochi in finestra e frequenza variabile (FreeSync/G-Sync) -> attive (meno ritardo nei giochi a schermo intero in finestra)"
}

# --- Windows Update: niente invio di aggiornamenti ad altri PC --------------
$script:ChiaveDO = 'Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings'
function SpegniCondivisioneUpdate {
    $attuale = (Get-ItemProperty $script:ChiaveDO -Name DownloadMode -ErrorAction SilentlyContinue).DownloadMode
    if ($attuale -eq 0) { Ok "Windows Update: condivisione degli aggiornamenti con altri PC gia' spenta"; return }
    Problema "Windows Update usa la tua connessione per inviare aggiornamenti ad altri PC"
    if ($script:Prova) { Nota "[PROVA] spegnerei la condivisione degli aggiornamenti con altri PC"; return }
    try {
        if (-not (Test-Path $script:ChiaveDO)) { New-Item -Path $script:ChiaveDO -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $script:ChiaveDO -Name DownloadMode -Value 0 -Type DWord -Force -ErrorAction Stop
        Risolto "Windows Update: condivisione degli aggiornamenti con altri PC -> spenta (banda libera, meno lag)"
    } catch { TocaATe "Spegni a mano: Impostazioni > Windows Update > Opzioni avanzate > Ottimizzazione recapito > Consenti download da altri dispositivi: No" }
}

# --- Accelerazione del mouse ("Migliora precisione puntatore") -------------
if (-not ('FulmineMouse' -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class FulmineMouse {
  [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint a, uint p, int[] v, uint w);
  // [soglia1, soglia2, accelerazione]: 0,0,0 = accelerazione spenta. Applica subito e salva.
  public static bool Imposta(int t1, int t2, int acc) { return SystemParametersInfo(0x0004, 0, new int[] { t1, t2, acc }, 0x03); }
}
"@
}
function SpegniAccelerazioneMouse {
    $m = Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue
    if ($m -and "$($m.MouseSpeed)" -eq '0') { Ok "Accelerazione del mouse: gia' spenta (mira costante)"; return }
    Problema "Accelerazione del mouse accesa: la mira cambia con la velocita' del movimento"
    if ($script:Prova) { Nota "[PROVA] spegnerei l'accelerazione del mouse"; return }
    if ([FulmineMouse]::Imposta(0, 0, 0)) { Risolto "Accelerazione del mouse ('Migliora precisione puntatore') -> spenta (mira costante)" }
    else { TocaATe "Spegni a mano: Impostazioni > Bluetooth e dispositivi > Mouse > Impostazioni aggiuntive > Puntatore > togli 'Migliora precisione puntatore'" }
}

# =====================================================================
#  BACKUP delle voci nuove (1.2): per chi ha gia' un backup creato con
#  una versione precedente, si aggiungono SOLO le voci mancanti, prese
#  ora, prima di cambiarle. Le voci gia' salvate non si toccano.
# =====================================================================
function StatoNuoveVoci {
    @{
        schermi = @(ElencoSchermi | ForEach-Object { @{ nome = $_.Nome; monitor = $_.Monitor; l = $_.L; a = $_.A; hz = $_.Hz } })
        avvio   = @(ElencoAvvioInutile | ForEach-Object { @{ tipo = $_.Tipo; chiave = $_.Chiave; nome = $_.Nome; originale = $_.Originale } })
        # 1.3 (avvolti in @{ v = ... } per distinguere 'non salvato' da 'non esisteva')
        dx      = @{ v = (Get-ItemProperty $script:ChiaveDX -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue).DirectXUserGlobalSettings }
        doMode  = @{ v = (Get-ItemProperty $script:ChiaveDO -Name DownloadMode -ErrorAction SilentlyContinue).DownloadMode }
        mouse   = $($m = Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue; @{ speed = [int]$m.MouseSpeed; t1 = [int]$m.MouseThreshold1; t2 = [int]$m.MouseThreshold2 })
    }
}
function CompletaBackup {
    if (-not (Test-Path -LiteralPath $fileBackup)) { return $false }
    $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
    if (-not $b) { return $false }
    $nuove = StatoNuoveVoci
    $cambiato = $false
    if ($null -eq $b.schermi) { $b | Add-Member -NotePropertyName schermi -NotePropertyValue $nuove.schermi -Force; $cambiato = $true }
    if ($null -eq $b.avvio)   { $b | Add-Member -NotePropertyName avvio   -NotePropertyValue $nuove.avvio   -Force; $cambiato = $true }
    foreach ($k in 'dx', 'doMode', 'mouse') {
        if ($null -eq $b.$k) { $b | Add-Member -NotePropertyName $k -NotePropertyValue $nuove[$k] -Force; $cambiato = $true }
    }
    else {
        # Programmi della lista comparsi dopo il primo backup: si salva il loro stato attuale.
        $noti = @($b.avvio | ForEach-Object { "$($_.chiave)|$($_.nome)" })
        $extra = @($nuove.avvio | Where-Object { "$($_.chiave)|$($_.nome)" -notin $noti })
        if ($extra.Count) { $b.avvio = @($b.avvio) + $extra; $cambiato = $true }
    }
    if ($cambiato) { $b | ConvertTo-Json -Depth 6 | Out-File -FilePath $fileBackup -Encoding utf8 }
    return $true
}

# I giochi impostati sulla scheda dedicata si aggiungono al backup, per toglierli con Ripristina.
function SalvaGpuAggiunti {
    if (-not $script:GpuAggiunti -or -not (Test-Path -LiteralPath $fileBackup)) { return }
    $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
    $tutti = @(@($b.gpuAggiunti) + $script:GpuAggiunti | Where-Object { $_ } | Select-Object -Unique)
    $b | Add-Member -NotePropertyName gpuAggiunti -NotePropertyValue $tutti -Force
    $b | ConvertTo-Json -Depth 6 | Out-File -FilePath $fileBackup -Encoding utf8
}

function RipristinaNuoveVoci($b) {
    foreach ($s in @($b.schermi)) {
        if (-not $s.nome) { continue }
        $ora = @(ElencoSchermi | Where-Object Nome -eq $s.nome)
        if (-not $ora -or $ora[0].Hz -eq $s.hz) { continue }
        if ($ora[0].L -ne $s.l -or $ora[0].A -ne $s.a) { Nota "Monitor $($s.nome): risoluzione cambiata da allora, frequenza lasciata com'e'"; continue }
        if ([FulmineSchermi]::Frequenza($s.nome, [int]$s.hz) -ge 0) { Fatto "Monitor $($s.l)x$($s.a) -> di nuovo a $($s.hz) Hz" }
        else { $script:ripristiniFalliti++; Avviso "Non sono riuscito a riportare il monitor $($s.nome) a $($s.hz) Hz" }
    }
    $n = 0
    foreach ($a in @($b.avvio)) {
        try {
            if ($a.tipo -eq 'run') {
                if ($null -eq $a.originale) { Remove-ItemProperty -Path $a.chiave -Name $a.nome -ErrorAction SilentlyContinue }
                else { Set-ItemProperty -Path $a.chiave -Name $a.nome -Value ([Convert]::FromBase64String($a.originale)) -Type Binary -Force -ErrorAction Stop }
            } elseif (Test-Path $a.chiave) {
                Set-ItemProperty -Path $a.chiave -Name State -Value ([int]$a.originale) -Type DWord -Force -ErrorAction Stop
            }
            $n++
        } catch { $script:ripristiniFalliti++; Avviso "Non sono riuscito a ripristinare l'avvio di $(NomeLeggibile $a.nome)" }
    }
    if ($n) { Fatto "Programmi all'avvio riportati com'erano ($n)" }
    if ($b.dx) {
        try {
            if ($null -eq $b.dx.v) { Remove-ItemProperty -Path $script:ChiaveDX -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue }
            else { Set-ItemProperty -Path $script:ChiaveDX -Name DirectXUserGlobalSettings -Value ([string]$b.dx.v) -Type String -Force -ErrorAction Stop }
            Fatto "Ottimizzazioni per i giochi in finestra ripristinate"
        } catch { $script:ripristiniFalliti++; Avviso "Non sono riuscito a ripristinare le ottimizzazioni per i giochi in finestra" }
    }
    if ($b.doMode) {
        try {
            if ($null -eq $b.doMode.v) { Remove-ItemProperty -Path $script:ChiaveDO -Name DownloadMode -ErrorAction SilentlyContinue }
            else { Set-ItemProperty -Path $script:ChiaveDO -Name DownloadMode -Value ([int]$b.doMode.v) -Type DWord -Force -ErrorAction Stop }
            Fatto "Condivisione degli aggiornamenti di Windows ripristinata"
        } catch { $script:ripristiniFalliti++; Avviso "Non sono riuscito a ripristinare la condivisione degli aggiornamenti" }
    }
    if ($b.mouse) {
        if ([FulmineMouse]::Imposta([int]$b.mouse.t1, [int]$b.mouse.t2, [int]$b.mouse.speed)) { Fatto "Accelerazione del mouse ripristinata" }
        else { $script:ripristiniFalliti++; Avviso "Non sono riuscito a ripristinare l'accelerazione del mouse" }
    }
    $g = 0
    foreach ($exe in @($b.gpuAggiunti)) {
        if (-not $exe) { continue }
        $v = (Get-ItemProperty $script:ChiaveDX -Name $exe -ErrorAction SilentlyContinue).$exe
        if ($v -eq 'GpuPreference=2;') { Remove-ItemProperty -Path $script:ChiaveDX -Name $exe -ErrorAction SilentlyContinue; $g++ }
    }
    if ($g) { Fatto "Preferenza scheda video tolta da $g giochi (come prima di Fulmine)" }
}

# =====================================================================
#  AVVIO
# =====================================================================
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
Write-Host $(if ($Ripristina) { "ripristino" } else { "scansione e ottimizzazione del PC" }) -NoNewline -ForegroundColor White
Write-Host " ]" -NoNewline -ForegroundColor DarkGray
Write-Host "  v$VERSIONE" -ForegroundColor DarkYellow
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
Write-Host ("  " + (" " * 46) + "~ by lozy ~") -ForegroundColor DarkGray
Write-Host ""
if ($Prova) { Avviso "MODALITA' PROVA: controllo tutto ma non cambio niente."; Write-Host "" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $Prova) {
    Write-Host "  Servono i permessi di amministratore: chiudi e avvia $(if ($Ripristina) { 'Ripristina.bat' } else { 'FULMINE.bat' })." -ForegroundColor Yellow
    Write-Host "  Senza, alcune modifiche fallirebbero e il PC resterebbe a meta'." -ForegroundColor Yellow
    if (-not $NoPause) { Read-Host }
    exit 1
}

if ($Ripristina) {
    Write-Host "  RIPRISTINO IN CORSO" -ForegroundColor White
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
    Write-Host ""
    if (-not (Test-Path -LiteralPath $fileBackup)) {
        Write-Host "  Nessun backup trovato: Fulmine non ha ancora modificato nulla su" -ForegroundColor Yellow
        Write-Host "  questo PC, quindi non c'e' niente da ripristinare." -ForegroundColor Yellow
    } else {
        $b = Get-Content -LiteralPath $fileBackup -Raw | ConvertFrom-Json
        Nota "Backup del $([datetime]$b.creato | ForEach-Object { $_.ToString('dd/MM/yyyy HH:mm') })"
        $pianoOk = $true
        if ($b.pianoEnergetico) {
            powercfg /setactive $b.pianoEnergetico
            $pianoOk = (powercfg /getactivescheme) -match [regex]::Escape($b.pianoEnergetico)
            if ($pianoOk) { Fatto "Piano energetico ripristinato" }
            else { $ripristiniFalliti++; Avviso "Non sono riuscito a riattivare il piano energetico originale" }
        }
        if ($pianoOk -and $b.ultimatePerfGuid -and (powercfg /list) -match [regex]::Escape($b.ultimatePerfGuid)) {
            powercfg -delete $b.ultimatePerfGuid
            Fatto "Piano 'Prestazioni elevate personalizzate' creato da Fulmine -> rimosso"
        }
        RipristinaValore 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $b.hags 'Valori della pianificazione GPU'
        Riavvio "La pianificazione GPU richiede un riavvio."
        RipristinaValore 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $b.visualFx 'Effetti visivi'
        RipristinaValore 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' $b.backgroundApps 'Permessi delle app in background'
        RipristinaValore 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $b.gameDvr 'Valori della Game Bar'
        RipristinaValore 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' $b.gameBarAutoGameMode $null
        RipristinaValore 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' $b.gameBarShowStartup $null
        if ($b.sysMainStart) {
            # Il backup usa le parole di WMI ("Auto"), che Set-Service non accetta.
            $avvioSysMain = switch ($b.sysMainStart) { 'Auto' { 'Automatic' } 'Automatic' { 'Automatic' } 'Disabled' { 'Disabled' } default { 'Manual' } }
            try {
                Set-Service -Name SysMain -StartupType $avvioSysMain -ErrorAction Stop
                if ($avvioSysMain -eq 'Automatic') { Start-Service -Name SysMain -ErrorAction SilentlyContinue }
                Fatto "Servizio SysMain ripristinato"
            } catch { $ripristiniFalliti++; Avviso "Non sono riuscito a ripristinare il servizio SysMain" }
        }
        RipristinaValore 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' $b.win32PrioritySeparation 'Valori di priorita'' dei processi'
        RipristinaValore 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' $b.fseGlobal 'Valori delle ottimizzazioni schermo intero'
        RipristinaValore 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' $b.fseHonorUser $null
        $nicFalliti = 0
        foreach ($n in $b.nic) {
            try {
                $obj = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
                       Where-Object { $_.InstanceName -eq $n.instanza }
                if ($obj) { $obj.Enable = $n.abilitato; Set-CimInstance -InputObject $obj -ErrorAction Stop }
            } catch { $nicFalliti++ }
        }
        if ($nicFalliti -gt 0) { $ripristiniFalliti += $nicFalliti; Avviso "Risparmio energia: $nicFalliti dispositivi non ripristinati" }
        elseif ($b.nic -and @($b.nic).Count -gt 0) { Fatto "Risparmio energia dei dispositivi ripristinato" }
        RipristinaNuoveVoci $b
        Write-Host ""
        if ($ripristiniFalliti -eq 0) { Write-Host "  Tutto riportato allo stato precedente a Fulmine." -ForegroundColor Green }
        else { Write-Host "  Ripristino incompleto: $ripristiniFalliti voci non riuscite, vedi sopra." -ForegroundColor Yellow }
    }
} else {
    # --- 1. Rilevamento ---------------------------------------------------
    Write-Host "  [1/3] SCANSIONE DEL PC" -ForegroundColor White
    Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray
    $gpu = RilevaSchedaVideo
    $dischi = DischiFissi
    $ceSSD = $false
    foreach ($d in $dischi) {
        $fisico = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $d.DriveLetter -ErrorAction SilentlyContinue).DiskNumber }
        if ($fisico -and $fisico.MediaType -eq 'SSD' -and $d.DriveLetter -eq $env:SystemDrive[0]) { $ceSSD = $true }
    }
    StampaSuggerimentoGPU $gpu
    Nota "Disco di sistema: $(if($ceSSD){'SSD'}else{'HDD o non rilevato'})"
    $script:Portatile = RilevaPortatile
    Nota "Tipo di PC: $(if ($script:Portatile) { 'portatile (adatto il piano energetico alla batteria)' } else { 'fisso' })"
    ControllaRAM
    ControllaDriverVideo $gpu
    ControllaSpazioDisco
    Write-Host ""

    # --- 2. Backup --------------------------------------------------------
    if (-not $Prova) {
        if (-not (Backup) -or -not (CompletaBackup)) {
            Write-Host "  Non riesco a salvare o leggere il backup dello stato originale:" -ForegroundColor Red
            Write-Host "  non cambio nulla, altrimenti Ripristina non potrebbe tornare indietro." -ForegroundColor Red
            if (-not $NoPause) { Read-Host }
            exit 1
        }
    }

    # --- 3. Ottimizzazione ----------------------------------------------
    Write-Host ""
    Write-Host "  [2/3] OTTIMIZZAZIONE" -ForegroundColor White
    Write-Host ("  " + ("-" * 68)) -ForegroundColor DarkGray
    CorreggiFrequenzaMonitor
    DisattivaAvvioInutile
    GpuDedicataPerGiochi
    OttimizzaGiochiInFinestra
    SpegniCondivisioneUpdate
    SpegniAccelerazioneMouse
    if (-not $Prova) { SalvaGpuAggiunti }
    if ($Prova) {
        Nota "[PROVA] applicherei anche: piano energetico massimo, pianificazione GPU, effetti visivi minimi,"
        Nota "[PROVA] app in background bloccate, Game Bar senza registrazione, priorita' al gioco,"
        Nota "[PROVA] risparmio energia di rete spento, pulizia file temporanei, TRIM degli SSD."
    } else {
        ImpostaPianoEnergetico 'prestazioni'
        AdattaPortatile
        ImpostaHAGS $true
        ImpostaEffettiVisivi 'prestazioni'
        ImpostaAppInBackground $true
        ImpostaGameBar 'prestazioni'
        ImpostaSysMain $true $ceSSD
        ImpostaPrioritaProcessi 'prestazioni'
        ImpostaFullscreenOptimizations $false
        ImpostaRisparmioEnergiaSchedeRete $true
        PuliziaRapida
        TrimDischiSSD $dischi
    }

    # --- 4. Rapporto finale ---------------------------------------------
    Write-Host ""
    Write-Host "  [3/3] RAPPORTO" -ForegroundColor White
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkGray
    Write-Host "  Problemi trovati: $($Trovati.Count)" -ForegroundColor $(if ($Trovati.Count) { 'Yellow' } else { 'Green' })
    foreach ($x in $Trovati) { Write-Host "    - $x" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "  Sistemati da Fulmine: $($Sistemati.Count)" -ForegroundColor Green
    foreach ($x in $Sistemati) { Write-Host "    + $x" -ForegroundColor Green }
    if (-not $Prova) { Write-Host "  Inoltre: impostazioni di Windows al massimo delle prestazioni (piano energetico, GPU, Game Bar, rete, priorita')" -ForegroundColor DarkGreen }
    if ($DaFare.Count) {
        Write-Host ""
        Write-Host "  DA FARE TU: $($DaFare.Count)" -ForegroundColor Yellow
        foreach ($x in $DaFare) { Write-Host "    > $x" -ForegroundColor Yellow }
    }
    if ($serveRiavvio.Count -gt 0) {
        Write-Host ""
        Write-Host "  Per completare, riavvia il PC." -ForegroundColor Magenta
    }
    Write-Host ""
    Write-Host "  Per tornare indietro in qualsiasi momento: Ripristina.bat" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Fulmine v$VERSIONE" -NoNewline -ForegroundColor DarkYellow
Write-Host "  ~  " -NoNewline -ForegroundColor DarkGray
Write-Host "by " -NoNewline -ForegroundColor DarkGray
Write-Host "lozy" -ForegroundColor Yellow
Write-Host ""
if (-not $NoPause) {
    Write-Host "  Premi INVIO per chiudere..." -ForegroundColor DarkGray
    Read-Host
}
