# ochepulse-webseite

Statische Website für [ochepulse.de](https://ochepulse.de/).

Ein Push auf `main` gleicht den vollständigen Inhalt von `public/` automatisch
mit `/srv/ochepulse/web/` auf dem OchePulse-Server ab. Neue und geänderte
Dateien werden veröffentlicht; in Git gelöschte Dateien werden auch auf dem
Server entfernt. `public/index.html` bleibt der Einstiegspunkt.

Weitere Seiten und Assets können frei unterhalb von `public/` angelegt werden,
zum Beispiel:

```text
public/
├── index.html
├── impressum.html
├── datenschutz.html
├── ueber-uns.html
├── css/
├── js/
└── images/
```

Der Workflow prüft den vollständigen Dateibaum vor dem Deployment, vergleicht
danach dessen Manifest mit dem Server und bestätigt zusätzlich die öffentlich
ausgelieferte Startseite bytegenau.

Der dafür verwendete SSH-Schlüssel ist serverseitig auf den geprüften
Deployment-Vorgang beschränkt und kann keine beliebigen Shell-Befehle
ausführen. Zulässig sind bis zu 5.000 reguläre Dateien, 50 MiB komprimiert und
200 MiB entpackt; Symlinks und Sonderdateien werden abgewiesen.
