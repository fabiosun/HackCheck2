# HackCheck 2.7.9 — Note di rilascio

Aggiornamento incentrato sulle funzionalità di uso quotidiano: scorciatoie, sensori sempre a portata di mano nella barra dei menu e avvio automatico.

## Novità

### ⌨️ Scorciatoie da tastiera

Nuovo menu **Aspetto** nella barra dei menu dell'app, con comandi attivi in **qualsiasi schermata** (finestra principale e Impostazioni):

| Scorciatoia | Azione |
|---|---|
| `⌘⇧L` | Passa da **ITA** a **EN** e viceversa |
| `⌘⇧A` | Passa da **Light** a **Dark** e viceversa |
| `⌘⌥A` | Torna ad **Aspetto sistema** (segue macOS) |
| `⌘⇧M` | Passa da **Aqua** a **Moderno** e viceversa |

Le scorciatoie sono elencate anche nella finestra **Impostazioni → Scorciatoie da tastiera**.

### 📊 Sensori nella barra dei menu

Ora puoi scegliere **quali singoli sensori** mostrare in alto a destra della barra di macOS:

1. Apri la pagina **Sensori**.
2. Fai **clic destro** sulla riga del sensore che ti interessa.
3. Seleziona **Aggiungi alla barra dei menu**.

La riga mostra una piccola icona per ricordarti che è attiva. Per toglierla, fai di nuovo clic destro e scegli **Rimuovi dalla barra dei menu**.

- La barra mostra sempre la scritta **HackCheck**, seguita da icona e valore compatto con unità (termometro `63°`, ventola `1240 RPM`, disco `45°`).
- Il menu a discesa elenca i sensori selezionati con le **stesse icone** della pagina Sensori (termometro, ventola, display, disco…) e i valori estesi.
- Comandi rapidi nel menu: **Apri HackCheck**, **Impostazioni…**, **Esci**.
- In **Impostazioni → Sensori nella barra dei menu** trovi un promemoria e il pulsante **Rimuovi tutti i sensori dalla barra**.

### 🚀 Avvio all'accesso

Nuova opzione **Impostazioni → Avvio → Avvia all'accesso**: registra l'app negli Elementi di accesso di macOS tramite `SMAppService`. Se il sistema richiede conferma, l'app indica dove approvarla.

### 🛠️ Correzioni

- La chiusura della finestra con il pulsante rosso **ora termina completamente l'app**, invece di lasciarla attiva solo nella barra dei menu.

### 🎨 Rifiniture grafiche

- Rimosso il fondino "Liquid Glass" dietro il titolo **HackCheck** nella barra del titolo.
- I pulsanti dei selettori (ITA/EN, Aqua/Moderno, Light/Dark) sono ora **pillole separate** e completamente arrotondate.

## Build

App universale `x86_64 + arm64`, richiede macOS 13.0 o successivo.

```bash
cd /Users/fabio/Downloads/HackCheck-SenzaFondo
./build.sh
```

L'app compilata si trova in `build/HackCheck.app`.

---

# HackCheck 2.7.9 — Release notes (English)

Small update focused on everyday usability: keyboard shortcuts, sensors always available in the menu bar, and launch at login.

## What's new

### ⌨️ Keyboard shortcuts

New **Appearance** menu in the app's menu bar, active on **every screen** (main window and Settings):

| Shortcut | Action |
|---|---|
| `⌘⇧L` | Toggle **ITA** / **EN** |
| `⌘⇧A` | Toggle **Light** / **Dark** |
| `⌘⌥A` | Switch back to **System appearance** (follows macOS) |
| `⌘⇧M` | Toggle **Aqua** / **Modern** |

The shortcuts are also listed in **Settings → Keyboard shortcuts**.

### 📊 Sensors in the menu bar

You can now choose **which individual sensors** appear at the top right of the macOS menu bar:

1. Open the **Sensors** page.
2. **Right-click** the sensor row you want.
3. Choose **Add to menu bar**.

The row shows a small icon to remind you it is active. Right-click again and choose **Remove from menu bar** to turn it off.

- The menu bar always keeps the **HackCheck** label, followed by each sensor's SF Symbol and its value with unit (thermometer `63°`, fan `1240 RPM`, disk `45°`).
- The dropdown lists the selected sensors with the **same icons** used on the Sensors page (thermometer, fan, display, disk…) and full values.
- Quick commands: **Open HackCheck**, **Settings…**, **Quit**.
- **Settings → Sensors in the menu bar** has a reminder and a **Remove all sensors from the menu bar** button.

### 🚀 Launch at login

New **Settings → Startup → Launch at login** option, using `SMAppService`. If macOS requires approval, the app tells you where to enable it.

### 🛠️ Fixes

- Closing the window with the red button now **fully quits the app**, instead of leaving it running only in the menu bar.

### 🎨 Visual polish

- Removed the "Liquid Glass" background behind the **HackCheck** title in the window toolbar.
- Selector buttons (ITA/EN, Aqua/Modern, Light/Dark) are now **separate, fully rounded pills**.

## Build

Universal app `x86_64 + arm64`, requires macOS 13.0 or later.

```bash
cd /Users/fabio/Downloads/HackCheck-SenzaFondo
./build.sh
```

The built app is in `build/HackCheck.app`.
