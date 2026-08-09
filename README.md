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

**Ottimizzazione prestazioni per Windows. Doppio clic, scegli la modalità, gioca.**

Piano energetico, pianificazione GPU, effetti visivi, app in background, priorità dei processi, servizi, risparmio energia di rete — tutti gli interventi che di solito si fanno a mano, uno alla volta, in dieci posti diversi delle Impostazioni.

## Tre modalità

```
1. scarica i file nella stessa cartella
2. doppio clic su FULMINE.bat
3. concedi i permessi di amministratore
4. scegli: 1 prestazioni · 2 qualità visiva · 3 bilanciata · 4 ripristina
```

**[1] Prestazioni (FPS)** — piano energetico al massimo, pianificazione GPU accelerata, Game Bar e registrazione in background disattivate, app UWP in background bloccate, priorità al programma in primo piano, effetti visivi minimi, risparmio energia di rete disattivato, pulizia file temporanei, TRIM sugli SSD.

**[2] Qualità visiva** — effetti visivi al massimo, Game Bar attiva per registrare, prestazioni comunque alte: pensata per chi vuole vedere bene e catturare clip, non solo il numero più alto possibile.

**[3] Bilanciata** — tutto ai valori predefiniti di Windows.

**[4] Ripristina** — torna esattamente allo stato di **prima** di aver mai usato Fulmine, non solo all'ultima modalità.

## Perché puoi fidarti di premere 1

Al primo avvio, prima di cambiare qualunque cosa, Fulmine salva lo stato **originale** del tuo PC in un file che non viene mai sovrascritto. Ripristina rilegge sempre quello — anche se nel frattempo hai provato tutte e tre le modalità dieci volte. Il ciclo backup → modifica → ripristino è testato, incluso il caso in cui un valore originale è `0` (un errore comune in script del genere: trattare zero come "assente" e perdere quel valore).

**Non tocca mai l'antivirus né il firewall.** Dopo un'infezione vera, "più veloce" non vale "meno sicuro" — nessuna eccezione, in nessuna modalità.

## Sul pannello della tua scheda video

NVIDIA e AMD tengono le impostazioni del proprio pannello (es. "preferisci prestazioni massime") in un formato privato che nessuno script esterno può leggere o scrivere in modo affidabile. Fulmine rileva quale scheda hai e **ti dice esattamente dove cliccare** nel suo pannello, invece di fingere di poterlo fare al posto tuo.

## Cosa controlla prima di iniziare

Scheda video (marca e suggerimento specifico), tipo di disco di sistema (SSD/HDD, cambia se disattivare SysMain), velocità della RAM — se gira al minimo JEDEC (2666 MHz su DDR4) invece che al profilo dichiarato XMP/DOCP, te lo segnala: è un'impostazione del BIOS, non di Windows, ma è spesso la causa più grande di un calo di prestazioni "senza motivo" su piattaforme AMD, dove la velocità della RAM è legata all'Infinity Fabric della CPU.

## Requisiti

Windows 10/11, PowerShell 5.1 (incluso), permessi di amministratore per la maggior parte delle modifiche (senza, funzionano solo quelle utente: effetti visivi e Game Bar).

## File

| | |
|---|---|
| `FULMINE.bat` | avvio: chiede i permessi e lancia il programma |
| `fulmine.ps1` | il programma, in chiaro e leggibile |
| `Crea-collegamento.bat` | crea sul Desktop un collegamento con l'icona |
| `fulmine.ico` · `fulmine.png` | il logo |

Il backup dello stato originale viene salvato in `%LOCALAPPDATA%\Fulmine\backup-originale.json`.

## Limiti

Non tocca il BIOS (RAM/XMP, undervolt, curve ventole): sono impostazioni della scheda madre, il software non può arrivarci. Non regola i pannelli proprietari NVIDIA/AMD (vedi sopra). I guadagni di FPS dipendono dal gioco, dall'hardware e da cosa era già configurato prima — non promette un numero.

## Licenza

MIT · by lozy

---

<div align="center">
  <sub>Fulmine — <b>by lozy</b> — dalla stessa famiglia di <a href="https://github.com/coremacsv/sentinella">Sentinella</a></sub>
</div>
