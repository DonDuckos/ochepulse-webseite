# ochepulse-webseite

Statische Website für [ochepulse.de](https://ochepulse.de/).

Ein Push auf `main` veröffentlicht `index.html`, `impressum.html` und
`datenschutz.html` automatisch auf dem OchePulse-Server. Der Workflow prüft
die Dateien vor dem Deployment und vergleicht anschließend die öffentlich
ausgelieferten Dateien bytegenau mit dem Commit.

Der dafür verwendete SSH-Schlüssel ist serverseitig auf den geprüften
Deployment-Vorgang beschränkt und kann keine beliebigen Shell-Befehle
ausführen.
