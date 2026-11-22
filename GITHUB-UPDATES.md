# Aggiornamenti GitHub — HackCheck 2.8.0

L'app controlla automaticamente (una volta al giorno) un file `update.json` pubblicato su GitHub e mostra una finestra con le note di rilascio in italiano o inglese. **Non installa da sola l'aggiornamento**: apre la pagina Release o scarica il DMG, perché la build è firmata *ad-hoc* e non notarizzata.

---

## Stato attuale

- Repository previsto: **`fabiosun/HackCheck2`**
- Feed: `https://raw.githubusercontent.com/fabiosun/HackCheck2/main/update.json`
- Versione corrente: **2.8.0** (`CFBundleVersion`; `CFBundleShortVersionString` resta `2.0`)
- Impostazioni → **Aggiornamenti** permette di cambiare il repository senza ricompilare.

Il tuo account GitHub risulta avere solo `fabiosun/AMD_Vanilla`, quindi il repo `HackCheck2` va creato. Se scegli un altro nome, cambialo in **Impostazioni → Aggiornamenti → Repository GitHub (utente/repo)** oppure modifica `UpdateChecker.defaultRepo`.

---

## 1. Creare il repository e pubblicare

`gh` non è installato su questa macchina. Puoi usare il sito GitHub (**New repository → fabiosun/HackCheck2 → Public**) oppure installare GitHub CLI:

```bash
brew install gh
gh auth login
cd "/Users/fabio/Downloads/HackCheck-SenzaFondo"
gh repo create fabiosun/HackCheck2 --public --source=. --remote=origin --push
git branch -M main
git push -u origin main
```

Se crei il repo dal sito, sostituisci l'ultimo blocco con:

```bash
cd "/Users/fabio/Downloads/HackCheck-SenzaFondo"
git remote add origin https://github.com/fabiosun/HackCheck2.git
git branch -M main
git push -u origin main
```

Il file `update.json` deve stare nella **root** del branch `main`: è quello che legge l'app.

## 2. Pubblicare la Release v2.8.0

Sempre da GitHub: **Releases → Draft a new release**

- Tag: `v2.8.0`
- Title: `HackCheck 2.8.0`
- Description: incolla `README-2.8.0.md`
- Allegati:
  - `dist/HackCheck-2.8.0-universal.dmg`
  - `dist/HackCheck-2.8.0-universal.zip`

Gli URL in `update.json` devono corrispondere esattamente a tag e nomi dei file.

## 3. Verificare dall'app

1. Apri HackCheck 2.8.0.
2. Menu **HackCheck → Controlla aggiornamenti…** oppure **Impostazioni → Aggiornamenti → Controlla ora**.
3. Dopo la prima pubblicazione di una versione successiva, appare la finestra con le note.

Per forzare un nuovo controllo ignoralo cache locale:

```bash
defaults delete app.hackcheck.modern lastUpdateCheck
defaults delete app.hackcheck.modern skippedUpdateVersion
```

---

## Pubblicare una versione futura

1. Aggiorna `CFBundleVersion` in `Info.plist`.
2. Aggiorna `UpdateNotice.currentNotes` in `Sources/UpdateNotice.swift`.
3. Aggiorna le nuove frasi in `Sources/Localization.swift` (nessuna chiave duplicata).
4. Compila e impacchetta:

```bash
cd "/Users/fabio/Downloads/HackCheck-SenzaFondo"
./build.sh
TMP=$(mktemp -d)
cp -R build/HackCheck.app "$TMP/HackCheck.app"
hdiutil create -volname HackCheck -srcfolder "$TMP/HackCheck.app" -ov -format UDZO dist/HackCheck-<VERSION>-universal.dmg
ditto -c -k --sequesterRsrc --keepParent build/HackCheck.app dist/HackCheck-<VERSION>-universal.zip
shasum -a 256 dist/HackCheck-<VERSION>-universal.dmg
rm -rf "$TMP"
```

5. Aggiorna `update.json`: `version`, `build`, `published`, note IT/EN, `pageURL`, `downloadURL`, `sha256` del **nuovo DMG**.
6. Fai commit/push e crea la Release con il tag `v<VERSION>` e i due allegati.

---

## Update flow (English)

The app checks `update.json` once a day and shows localized release notes. It does **not** install updates by itself: the build is ad-hoc signed, so it opens the Release page or downloads the DMG for manual installation.

- Expected repository: `fabiosun/HackCheck2`
- Feed: `https://raw.githubusercontent.com/fabiosun/HackCheck2/main/update.json`
- The repository can be changed in **Settings → Updates → GitHub repository** without rebuilding.
- Create the repo, push `main`, create release `v2.8.0` and attach both DMG and ZIP.
- For every new release: bump `CFBundleVersion`, rebuild, repackage, refresh `update.json` (including the new DMG SHA-256), push and create the release.
