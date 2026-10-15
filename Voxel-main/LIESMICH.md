# Grünweiten – Voxel-Abenteuer und Bauen

**Neue Naturwelten:** Wiesen, Wälder, Seen und große Gebirge entstehen gemeinsam,
mit unterschiedlich großen Gebieten, breiten Übergängen, Baumgruppen und Lichtungen.
Seerosen und Steine beleben Gewässer; Bäume wachsen nur auf trockenem Boden.
Erkundete Abschnitte werden einschließlich fertiger Geometrie komprimiert zwischengespeichert.
Hintergrund-Threads, Bewegungsvorlauf, verteiltes Einblenden und vorbereitete Modelle
reduzieren Arbeitsspitzen. Die neue Biomeinteilung gilt für neue Welten; vorhandene
Spielstände und Testmap behalten ihr Gelände. Mehr dazu in `../Spiel/LIESMICH.txt`.

**Neue Gegner:** Goblins, Hexen und Räuber in Gruppen von ein bis fünf nach Gebietslevel.
Neue Welten haben einzelne Zyklopen, Drachen und Riesen-Sandwürmer an eigenen Dungeonplätzen.
Feste Körper verhindern Hindurchlaufen; Treffer und Zustände werden im Mehrspieler synchronisiert.
Die Testmap enthält alle sechs Typen. Details stehen in `../Spiel/LIESMICH.txt`.

**Neu:** Zoombare Karte mit M/Mausrad und Ziehen; Krieger-Kampfsystem mit dauerhaft gezogenem
Schwert (1 schaltet zu Fäusten), Dreierkombo, Shift-Sprint, Strg-Rolle, Q-Wirbel und R-Sprungschlag.
T öffnet den Kriegerbaum mit 19 Talenten und weiteren Fähigkeiten. Tierlevel steigen mit der Entfernung,
Treffer blinken und stoßen zurück, besiegte Tiere zerfallen in Pixelstücke. Wildtiere spawnen außerhalb
der Dorf-Schutzzonen; Hofhühner bleiben erhalten. Details und Tasten stehen in `../Spiel/LIESMICH.txt`.

## Starten

**Fertiges Spiel (Windows):** Im Ordner `Spiel` die `Gruenweiten.exe` doppelklicken. Die Spieldaten sind in der EXE eingebettet. `libvoxelcore.windows.template_release.x86_64.dll`
müssen im selben Ordner liegen (die DLL ist der C++-Voxelkern fürs Abbauen und Bauen).
Das Spiel startet im Vollbild. F11 oder Alt+Enter schaltet um.

**Godot-Projekt:** Den Ordner in Godot **4.7** öffnen (gebaut mit 4.7.2) und F5 drücken.
Beim ersten Öffnen importiert Godot die Assets, das dauert ein paar Sekunden.

## Hauptmenü und Optionen

Das Spiel startet im Hauptmenü mit **Einzelspieler**, **Mehrspieler**, **Optionen** und **Verlassen**.
Einzelspieler bietet eine neue Welt oder das Fortsetzen eines vorhandenen Spielstands.
Mehrspieler führt zur bestehenden Online-/Heimnetz-Lobby. Nach dem Hosten oder Beitreten führen Zurück und Weiter in die Welt.
Über Esc sind die Optionen auch im Spiel erreichbar. Hauptmenü im Pausenmenü speichert die Welt und trennt die Verbindung.

Die Optionen werden automatisch gespeichert und wirken sofort:

- **Sound:** Gesamtlautstärke, Effekte/Menü, Umgebungsgeräusche.
- **Grafik:** Qualität, Sichtfeld, MSAA, Vollbild, V-Sync, Schatten.
- **Shader:** Schwarze Voxel-Ränder an/aus und Stärke, Bloom, SSAO, SDFGI, Pflanzenwind, Farbsättigung.
- **Steuerung:** Mausempfindlichkeit, Y-Achse umkehren und Tastenbelegung mit Konfliktprüfung und Standardbelegung.

SSAO gilt ab Qualität Mittel, SDFGI bei Hoch. Controller- und Mausbelegungen bleiben beim Ändern einer Taste erhalten.
Die festen Baugesten und Zifferntasten sind im Steuerungsbereich erklärt.

Windows neu exportieren: Im übergeordneten Ordner `Build-Spiel.ps1` ausführen (Godot 4.7.2 und die lokale Exportvorlage erforderlich).

## Tierfamilien, Rudel und Schwärme

Die Welt enthält jetzt 102 Tiere: 66 erwachsene Tiere und 36 Jungtiere. Alle sieben Arten haben beide Altersstufen:
Bären, Wölfe, Hasen, Schildkröten, Vögel, Bienen sowie Hühner mit gelben Küken. Jungtiere sind kleiner, haben weniger
Lebenspunkte und folgen ihren Eltern beziehungsweise ihrer Gruppe. Auch kleine und friedliche Tiere lassen sich mit
dem Schwert treffen. Hühner laufen bei den Feldern umher, picken und gackern; Küken haben eigene Pieplaute.

Wölfe sind 24 Prozent kleiner als zuvor. Zwei Rudel aus jeweils vier Erwachsenen und zwei Welpen patrouillieren auf
begehbaren, trockenen Wegen zwischen Flussufern und Wald. Drei erwachsene Wölfe folgen ihrem Anführer anhand seiner
Laufspur. Hindernisse führen zu Umwegen. Wölfe jagen und fressen Hasen. Mindestens drei nahe erwachsene Rudelmitglieder
wagen gemeinsam einen Angriff auf einen Bären; einzelne Wölfe meiden unprovozierte erwachsene Bären.

Bären ohne Jungtier halten Abstand und greifen erst bei großer Nähe oder nach einem Angriff an. Bei lebenden Jungen
in der Nähe verteidigen sie ein größeres Gebiet gegen Spieler und andere Tiere. Angriffe auf ein Jungtier alarmieren
die Eltern. Bienen bleiben friedlich, bis eine angegriffen wird; dann wehren sich auch benachbarte Bienen mit Stichen.

42 Vögel fliegen in drei bewegten Formationen: V-Formation, versetzte Reihen und eine schräge Staffel. Die Formationsplätze
bleiben auch in Kurven zusammen. Tierzustände, Fresspausen, Rudelrouten und Schwarmzeit werden mitgespeichert und im
Mehrspieler vom Host gesteuert. Frühere Spielstände behalten ihre ursprünglichen erwachsenen Tier-IDs.

## Abbauen, Holzfällen und Bauen an-/ausschalten

**Optionen → Spiel → Abbauen, Holzfällen & Bauen** ist in dieser Version standardmäßig **Aus**.
Damit sind Bodenabbau, Baumfällen, Baumodus und Baukasten gesperrt; die zugehörigen Quests und Bauhinweise verschwinden.
Tierkämpfe, Erkundung, Dorfaufträge und Speichern bleiben möglich. Beim Wiedereinschalten erscheint der gespeicherte
Bau- und Questfortschritt wieder. Im Mehrspieler gelten die Regeln des Hosts; Gäste können sie nicht überschreiben.

Das alte globale Wasser-/Vogel-Mischgeräusch ist durch getrennte Quellen ersetzt:
Fluss und Wasserfälle werden mit der Entfernung leiser und verstummen außerhalb ihrer Hörweite.
Wände dämpfen Umgebungsgeräusche, unter Dächern wird der Wind leiser. Waldrauschen ist an Waldgebiete gebunden.
Tierlaute und Bienensummen kommen aus der jeweiligen Richtung. Schritte unterscheiden Gras, Stein/Holz und Wasser.
Unter Optionen → Sound gibt es einen eigenen Regler für Tiergeräusche.
Alle neuen WAVs sind eigens synthetisiert, keine fremden Tonaufnahmen. Modelle und Sounds lassen sich mit
`python tools/gen/wildlife_assets.py` (numpy) neu erzeugen, ohne die bestehende Welt neu zu bauen.

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



