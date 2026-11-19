<img src="fulmine.png" width="130" align="right" alt="Logo di Fulmine: un fulmine">

# Fulmine

```
  ███████╗██╗   ██╗██╗     ███╗   ███╗██╗███╗   ██╗███████╗
  ██╔════╝██║   ██║██║     ████╗ ████║██║████╗  ██║██╔════╝
  █████╗  ██║   ██║██║     ██╔████╔██║██║██╔██╗ ██║█████╗
  ██╔══╝  ██║   ██║██║     ██║╚██╔╝██║██║██║╚██╗██║██╔══╝
  ██║     ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║███████╗
  ╚═╝      ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝
                                              ~ by lozy ~
```

**Il PC a razzo con un clic.** Fulmine scansiona il PC, sistema da solo tutto quello che lo rallenta e alla fine ti dice cosa ha trovato e cosa ha fatto.

## Come si usa

```
1. scarica i file nella stessa cartella
2. doppio clic su FULMINE.bat
3. concedi i permessi di amministratore
```

Fine. Niente menu, niente scelte.

## Cosa fa con quel clic

**1. Scansione.** Scheda video, disco di sistema, RAM, età del driver video, spazio libero.

**2. Ottimizzazione automatica:**

| | |
|---|---|
| 🖥️ **Monitor** | se un monitor va a 60 Hz ma ne supporta di più (144, 240…), lo porta alla **frequenza massima**, senza cambiare la risoluzione |
| 🚀 **Programmi all'avvio** | toglie dall'avvio **solo** programmi Microsoft che partono senza motivo (Teams, Edge, Office, Collegamento al telefono, Copilot, To Do…). **Non tocca mai** Discord, i launcher dei giochi, il software di mouse/tastiere/cuffie, l'antivirus, i driver, OneDrive |
| ⚡ **Windows** | piano energetico al massimo, pianificazione GPU accelerata, Game Bar senza registrazione in background, app in background bloccate, priorità al gioco, effetti visivi minimi, schermo intero esclusivo, risparmio energia di rete spento |
| 🧹 **Pulizia** | file temporanei più vecchi di 7 giorni, TRIM sugli SSD |

**3. Rapporto finale:**
```
  Problemi trovati: 2
    - Monitor 2 (1920x1080) a 60 Hz, ma supporta 144 Hz
    - 2 programmi inutili partono all'avvio di Windows
  Sistemati da Fulmine: 3
    + Monitor 2 (1920x1080) -> da 60 a 144 Hz
    + Avvio automatico disattivato: Microsoft 365 / Office
    + Avvio automatico disattivato: Collegamento al telefono
  DA FARE TU: ...
```

Quello che un programma **non può** fare da solo finisce in **DA FARE TU**, con le istruzioni:
- **RAM senza XMP/DOCP/EXPO.** Fulmine legge la velocità dichiarata dal codice del modulo (es. `CMW32GX4M2Z3600C18` → 3600 MHz) e, se la RAM gira più piano, spiega come attivare il profilo nel BIOS. Su AMD la velocità della RAM è legata all'Infinity Fabric della CPU: spesso è la causa più grande di un calo di prestazioni "senza motivo".
- **Driver video vecchio di più di 6 mesi.** Apre la pagina ufficiale di AMD, NVIDIA o Intel.
- **Disco di sistema quasi pieno** (meno del 10% libero).

## Tornare indietro: `Ripristina.bat`

Doppio clic su **`Ripristina.bat`**: tutto torna esattamente allo stato di **prima** di aver mai usato Fulmine, comprese frequenza dei monitor e programmi all'avvio.

## Perché puoi fidarti

Al primo avvio, prima di cambiare qualunque cosa, Fulmine salva lo stato **originale** del PC in un file che non viene mai sovrascritto. Ripristina rilegge sempre quello, anche dopo dieci esecuzioni. Le voci aggiunte nelle versioni nuove vengono salvate la prima volta che le usi, prima di cambiarle. Il ciclo Fulmine → Ripristina → Fulmine è testato su un PC reale.

**Non tocca mai l'antivirus né il firewall.** Dopo un'infezione vera, "più veloce" non vale "meno sicuro". Nessuna eccezione.

Vuoi solo vedere cosa farebbe? Da PowerShell: `.\fulmine.ps1 -Prova` controlla tutto e non cambia niente.

## Sul pannello della tua scheda video

NVIDIA e AMD tengono le impostazioni del proprio pannello (es. "preferisci prestazioni massime") in un formato privato che nessuno script esterno può leggere o scrivere in modo affidabile. Fulmine rileva quale scheda hai e **ti dice esattamente dove cliccare**, invece di fingere di poterlo fare al posto tuo.

## Requisiti

Windows 10/11, PowerShell 5.1 (incluso), permessi di amministratore.

## File

| | |
|---|---|
| `FULMINE.bat` | **il clic**: chiede i permessi, scansiona e ottimizza |
| `Ripristina.bat` | torna a com'era prima di Fulmine |
| `fulmine.ps1` | il programma, in chiaro e leggibile |
| `Crea-collegamento.bat` | crea sul Desktop un collegamento con l'icona |
| `fulmine.ico` · `fulmine.png` | il logo |

Il backup dello stato originale viene salvato in `%LOCALAPPDATA%\Fulmine\backup-originale.json`.

## Limiti

Non tocca il BIOS (RAM/XMP, undervolt, curve ventole): sono impostazioni della scheda madre. Non aggiorna i driver da solo: un installer da centinaia di MB con riavvii non si lancia alla cieca, quindi apre la pagina giusta. Non regola i pannelli proprietari NVIDIA/AMD. I file temporanei cancellati non tornano indietro. I guadagni di FPS dipendono dal gioco, dall'hardware e da cosa era già configurato prima: non promette un numero.

## Licenza

MIT · by lozy

---

<div align="center">
  <sub>Fulmine — <b>by lozy</b> — dalla stessa famiglia di <a href="https://github.com/coremacsv/sentinella">Sentinella</a> e <a href="https://github.com/coremacsv/Mod-Audio-COD">Mod Audio COD</a></sub>
</div>
