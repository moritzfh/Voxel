# Grünweiten – begehbare Szene nach dem KI-Konzeptbild

## Starten

**Fertiges Spiel (Windows):** `Gruenweiten.exe` doppelklicken. `Gruenweiten.pck` muss im selben Ordner liegen.
Das Spiel startet im Vollbild. F11 oder Alt+Enter schaltet um.

**Godot-Projekt:** Den Ordner in Godot **4.7** öffnen (gebaut mit 4.7.2) und F5 drücken.
Beim ersten Öffnen importiert Godot die Assets, das dauert ein paar Sekunden.

## Steuerung

| Aktion | Tastatur/Maus | Controller |
|---|---|---|
| Laufen | WASD | linker Stick |
| Kamera | Maus | rechter Stick |
| Kamera-Abstand | Mausrad | – |
| Sprinten | Shift oder Q | L1 / L3 |
| Springen | Leertaste | A / Kreuz |
| Gleiter (in der Luft halten) | F | B / Kreis |
| Sprechen / Kiste aufheben | E | Y / Dreieck |
| Schwertschlag | 1 oder linke Maustaste | X / Viereck oder R2 |
| Manatrank | 2 | Steuerkreuz hoch |
| Essen | G | Steuerkreuz runter |
| Menü (Pause, Speichern, Laden, Grafik) | Esc | Options/Start |

**Chat:** Enter öffnet das Chatfeld (Enter sendet, Esc bricht ab).

Zum Ausprobieren gibt es Dorfbewohner (Dorfältester am Weg, Händlerin am Markt, Wache an der Brücke, Bauer bei der Burg)
und zwei leuchtende Vorratskisten. Die zählen die Aufträge im HUD hoch. Ins Wasser kannst du rein, Kanten bis 0,5 m
steigst du automatisch hoch, höhere kletterst du per Sprung.

## Mehrspieler (bis 8 Spieler)

Esc → **Mehrspieler**, Name eintragen, dann:

- **Online hosten (Code für Freunde):** Du bekommst einen 6-stelligen Code (z. B. `K7P2QA`). Er landet automatisch
  in der Zwischenablage und steht auch im Chat. Den schickst du deinen Freunden.
- **Beitreten:** Code ins Feld tippen → „Beitreten“. Fertig – kein Router, keine Portfreigabe, kein Account.
- Technik: Die Spiele tauschen ihre Daten über einen öffentlichen MQTT-Vermittlungsdienst aus (EMQX, als Ausweich
  HiveMQ / Mosquitto). Die Daten sind nicht verschlüsselt-privat – wer den Code kennt, könnte mitlesen. Für ein
  Spiel unter Freunden egal.
- **Heimnetz:** „Im Heimnetz hosten (ohne Code)“ läuft direkt über UDP-Port 7777. Spiele im selben Netz tauchen
  automatisch unter „Spiele im Heimnetz“ auf; alternativ die IP ins Beitreten-Feld tippen. Beim ersten Mal fragt
  die Windows-Firewall – „Zulassen“ klicken.
- Jeder Spieler bekommt eine eigene Schalfarbe und ein Namensschild; auf der Minikarte sind die anderen als Punkte.
  Das Menü pausiert im Mehrspieler nicht. Aufträge und Kisten zählt jeder für sich. **Enter** öffnet den Chat.

## Grafik & Leistung

- **Menü (Esc) → Grafik: Hoch / Mittel / Niedrig.** Hoch = volle Auflösung + Global Illumination (SDFGI).
  Mittel = 80 % Renderauflösung mit FSR 2, ohne SDFGI. Niedrig = 67 % + kürzere Schatten/Graslänge.
  Auf sehr großen Bildschirmen (z. B. 5120×1440) startet das Spiel automatisch auf „Mittel“.
- **Menü → Sichtfeld: Normal / Weit / Maximal.** Begrenzt das horizontale Sichtfeld auf Ultrawide-Monitoren
  (110° / 125° / unbegrenzt), damit die Bildränder auf 32:9 nicht verzerren.
- **F3** blendet die FPS-Anzeige unten rechts ein/aus.
- Einstellungen werden gespeichert. Das Spiel schreibt alle 10 Sekunden die Bildrate in **leistung.txt**
  (neben der Gruenweiten.exe) – die Datei hilft beim Optimieren.

## Aufbau (für Änderungen)

Alles ist aus Code generiert, es gibt keine fremden Assets. Die Welt besteht komplett aus einfarbigen Voxeln
(keine Block-Texturen): 12,5 cm im spielbaren Bereich (mit 25/50 cm in der Entfernung), Pflanzen und Blumen 6,25 cm,
Bäume 12,5 cm mit 5 Detailstufen, Hügel und Berge in 1–4 m. Farbe, Helligkeits-Streuung und die feinen Fugen
kommen aus `shaders/voxel_common.gdshaderinc`.

- `tools/gen/` – Python-Generator: Terrain, Fluss und Wasserfälle, Häuser, Burg, Brücke, Ruine (`world.py`,
  `fine.py`, `structures.py`), Materialfarben (`vox.py`), Bäume, Pflanzen, Wolken (`flora.py`, `scatter.py`),
  Figuren, Icons, Minikarte und Umgebungsgeräusche.
- `bake/bake.gd` – wandelt die Generator-Ausgabe in Godot-Ressourcen (`generated/`) um.
- `scripts/` – Spieler, Kamera, Animationen, NPCs, HUD, Mehrspieler (`net.gd`, `remote_player.gd`);
  `shaders/` – Voxel, Wasser, Pflanzen, Wolken, Himmel.

Neu generieren (Python 3 mit numpy, numba, scipy und pillow), etwa 3 Minuten:

```
cd tools/gen
python world.py ../out
cd ../..
godot --headless --path . --import
godot --headless --path . --script res://bake/bake.gd
```

Screenshot-Modus (wird zum Vergleich mit dem Konzeptbild benutzt):
`godot --path . -- --shot=bild.png --frames=10 [--cam=x,z,yaw,pitch,abstand] [--nohud]`

Mehrspieler direkt starten: `Gruenweiten.exe -- --name=Moritz --host-online` bzw. `-- --name=Gast --join-code=K7P2QA`
(Heimnetz: `--host` / `--join=192.168.0.23`).
