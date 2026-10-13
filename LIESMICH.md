# Grünweiten – begehbare Szene nach dem KI-Konzeptbild

## Starten

**Fertiges Spiel (Windows):** `Gruenweiten.exe` doppelklicken. `Gruenweiten.pck` und `libvoxelcore.windows.template_release.x86_64.dll`
müssen im selben Ordner liegen (die DLL ist der C++-Voxelkern fürs Abbauen und Bauen).
Das Spiel startet im Vollbild. F11 oder Alt+Enter schaltet um.

**Godot-Projekt:** Den Ordner in Godot **4.7** öffnen (gebaut mit 4.7.2) und F5 drücken.
Beim ersten Öffnen importiert Godot die Assets, das dauert ein paar Sekunden.

## Steuerung

| Aktion | Tastatur/Maus | Controller |
|---|---|---|
| Laufen | WASD | linker Stick |
| Kamera | Maus | rechter Stick |
| Kamera-Abstand | Mausrad (im Baumodus Strg+Mausrad) | – |
| Sprinten | Shift oder Q | L1 / L3 |
| Springen | Leertaste | A / Kreuz |
| Gleiter (in der Luft halten) | F | B / Kreis |
| Sprechen / Kiste / Runenstein | E | Y / Dreieck |
| Abbauen / Schwertschlag | linke Maustaste halten (oder 1) | X / Viereck oder R2 |
| Baumodus an/aus | B | – |
| Ego-Perspektive an/aus | H (oder ganz reinzoomen) | – |
| Inventar · Talente · Journal · Karte | I · T · J · M | – |
| Manatrank / Essen | 2 / G | Steuerkreuz |
| Menü (Pause, Speichern, Laden, Grafik) | Esc | Options/Start |

**Chat:** Enter öffnet das Chatfeld (Enter sendet, Esc bricht ab).

## Abbauen

Fadenkreuz auf Erde, Stein, Holz, Bäume oder Felsen richten und die linke Maustaste halten – das passende Werkzeug
(Schaufel, Spitzhacke, Axt) nimmt der Held automatisch. Jeder Schlag bricht einen unregelmäßigen Brocken aus den
12,5-cm-Voxeln, die Krümel fliegen davon und werden zu dir gezogen. Was unterhöhlt in der Luft hängt, bricht ab und
fällt. Bäume bekommen bei jedem Axthieb eine tiefere Kerbe, kippen dann von dir weg, die Krone platzt in Laub, der
Stamm zerfällt in Holzstämme zum Aufsammeln und der Stumpf bleibt stehen.

- Im Stein stecken Erzadern: **Kupfer** (ab ~1 m Tiefe), **Eisen** (tiefer), **Kristall** (ganz unten).
  Eisenerz und Bergfels brauchen Kupferwerkzeug, Kristall und Gold Eisenwerkzeug (**I → Herstellen**).
- Natur-Material (Erde, Stein, Sand …) gibt 1 Rohstoff je Voxel. Verbaute Baustoffe (Bruchstein, Bretter, Ziegel,
  Glas …) kosten beim Bauen 1 Rohstoff je 4 Voxel und geben beim Abbauen genau so viel zurück.
- 8 **Runensteine** (leuchtend blau) mit E berühren, 6 vergrabene **Schätze** unter einem X aus Kieseln ausgraben.

## Bauen (B)

Statt einzelner Blöcke ziehst du Formen auf. Die Vorschau zeigt die echten Farben und Muster, die Maße und was es kostet
(grün = passt, rot = geht nicht, mit Grund).

| | |
|---|---|
| **Linke Maus** | bauen – gedrückt halten und ziehen = Grundfläche, loslassen = fertig. Klick ohne Ziehen nimmt die letzte Größe |
| **Rechte Maus** | dieselbe Form **ausschneiden** (Türen, Fenster, Keller, Tunnel) |
| **Mausrad** / **Shift+Rad** | Höhe (an Wänden: Tiefe) / Wandstärke |
| **1 – 0** | Formen: Quader, Wand, Boden, Raum, Haus, Pinsel, Kugel, Turm, Treppe, Dach – nochmal drücken oder **V** = Variante |
| **R** / **Shift+R** | drehen / spiegeln (Treppen, Pultdächer, Tore richten sich sonst nach deiner Blickrichtung) |
| **X** | Modus: Bauen → Färben (Material austauschen) → Kopieren (Bereich ziehen = Bauplan) |
| **P** | gespeicherte Baupläne durchschalten und setzen |
| **G** | Raster 12,5 cm / 25 cm / 50 cm / 1 m |
| **Mittlere Maus** | Pipette: Material von der Welt übernehmen · **Alt+Rad**: letzte Materialien |
| **Strg+Z / Strg+Y** | rückgängig / wiederholen (Rohstoffe kommen zurück) |
| **Tab** | Baukasten: alle Formen und Varianten, 36 Materialien, 7 Muster, Größe in Metern, Optionen, Baupläne |

- **Haus** baut auf einen Zug Wände, Dach (im Zweitmaterial), Tür, Fenster und Dielenboden.
- **Pinsel** modelliert frei (Gelände formen, Hecken aus Laub), rechte Maus formt weg.
- **Fundament**: am Hang wird die Unterkante automatisch bis zum Boden aufgefüllt (im Baukasten abschaltbar).
- Kreativmodus (unendlich Material) gibt es im Baukasten.

## Fortschritt

Abbauen, Bauen, Bäume fällen, Runensteine und Aufträge geben Erfahrung. Jede Stufe bringt einen Talentpunkt (**T**):
Bergbau (größere Brocken, Erz-Gespür: Erze leuchten durch den Stein, Sprengkraft), Holzfäller, Baumeister
(Kugel/Turm → Bögen/Treppen → Dächer/Zinnen, größere Formen bis 16 m, Sparsam, mehr Baupläne) und Entdecker
(schneller laufen, Schätze und Runen auf der Karte). Die Aufträge im Journal (**J**) führen vom ersten Graben über
Kupfer und neues Werkzeug zum **Wachturm** am Fluss (leuchtender Umriss, der gefüllt werden will), den Runensteinen
und den Schätzen. Speichern im Menü sichert auch die veränderte Welt, gefällte Bäume und deine Baupläne.

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
  Das Menü pausiert im Mehrspieler nicht. Aufträge, Rohstoffe und Kisten zählt jeder für sich. **Enter** öffnet den Chat.
- Abbauen, gefällte Bäume und alles Gebaute sehen alle Spieler. Wer später dazukommt, bekommt vom Host die schon
  veränderte Welt übertragen.

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
- `native/` – C++-Voxelkern (GDExtension): Meshing, Kollision, Abbau-Brocken, Statik, Formen, Baupläne.
  Bauen mit godot-cpp: `scons platform=windows target=template_release use_mingw=yes` (siehe `native/`).
- `scripts/voxel/` – editierbare Welt, fallende Teile, Krümel; `scripts/game/` – Abbauen (`tools.gd`), Bauen
  (`builder.gd`), Fortschritt (`game_state.gd`); `scripts/ui/` – HUD, Baukasten, Buch (Inventar/Talente/Karte).
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
