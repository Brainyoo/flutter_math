# Design: Top-Level-Zeilenumbrüche für `\\`, `\cr`, `\newline`

- **Datum:** 2026-06-16
- **Status:** Genehmigt (bereit für Implementierungsplan)
- **Betroffenes Package:** `flutter_math_fork`

## 1. Problem / Hintergrund

`\\`, `\cr` und `\newline` funktionieren aktuell **nur innerhalb von Umgebungen**
(`matrix`, `aligned`, `cases`, `array`, …). Frei stehend — z.B.
`Math.tex(r'a \\ b')` — **parst** der Ausdruck zwar, **crasht** aber beim Bauen:

```
Unsupported operation: Temporary node CrNode encountered.
```

### Ursachenkette (verifiziert)

1. `\\` ist ein Makro → `\newline` (`macros.dart:640`). `\cr`/`\newline` sind in
   `cr.dart:27` registriert. Alle drei erzeugen über `_crHandler` einen `CrNode`
   (`cr.dart:61`).
2. `CrNode extends TemporaryNode` (`cr.dart:35`). `TemporaryNode` ist laut
   Quellcode ausdrücklich nur ein Parse-Platzhalter und wirft in `buildWidget`
   (`syntax_tree.dart:819-827`: „Only for improvisional use during parsing").
3. `CrNode` wird **nur von Umgebungs-Parsern konsumiert** (`array.dart:159`,
   `eqn_array.dart:206`). Außerhalb einer Umgebung überlebt der Knoten bis zum
   Build → Crash → `Math` fällt auf das Fehler-Widget zurück.

**Kernursache:** Ein frei stehender Zeilenumbruch in einer einzelnen Gleichung
wurde im Renderer/AST nie implementiert; nur die Umgebungs-Parser wissen, was sie
mit `CrNode`s anfangen sollen.

### KaTeX-Referenz (Vorbild des Packages)

In KaTeX (`src/functions/cr.ts`) ist `\\` **keine Umgebung**, sondern ein Knoten
vom Typ `"cr"` mit eigenem `htmlBuilder`: er erzeugt eine
`<span class="mspace newline">`. Das eigentliche Umbrechen macht CSS
(`.newline { display:block }`) — der Inline-Fluss bricht **linksbündig** um.
Innerhalb von Arrays wird derselbe `cr`-Knoten stattdessen vom Array-Parser
konsumiert. Also exakt dieselbe Zwei-Welten-Trennung, die flutter_math bereits hat.

flutter_math besitzt das KaTeX-Äquivalent zu „Umbruch im Fluss" schon: **Break-
Points als Knoten, ausgewertet über die `Math.texBreak()`-API** (`tex_break.dart`;
`\allowbreak` → Penalty 0, `\nobreak` → 10000 in `break.dart:31`). Ein
erzwungener `\\`-Umbruch fügt sich also nativ in dieses Modell ein.

## 2. Ziel / Nicht-Ziel

### Ziel
- `Math.tex(r'a \\ b')` rendert ohne Crash automatisch mehrzeilig, linksbündig.
- `\\`, `\cr`, `\newline` am Top-Level erzeugen einen echten, renderbaren
  Umbruch-Knoten, der sich in die bestehende `texBreak()`-API einfügt.
- Verhalten innerhalb von Umgebungen bleibt **unverändert**.

### Nicht-Ziel (v1)
- Auto-Mehrzeiligkeit in `SelectableMath` (bleibt einzeilig; siehe Detail #1).
- Zeilenumbruch innerhalb von Gruppen `{ … }` (rendert als No-op; Detail #6).
- Ausrichtung an `&` am Top-Level (`&` bleibt wie bisher ein Top-Level-Parsefehler;
  Spaltenausrichtung gibt es nur in echten Umgebungen).
- Spaltenzentrierung / `gather`-artige Zentrierung (bewusst linksbündig gewählt).

## 3. Design

Drei kleine, isolierte Bausteine. **Kein** neuer Render-Primitive — es wird
ausschließlich vorhandene, getestete Maschinerie wiederverwendet.

### Baustein 1 — `CrNode` wird ein renderbarer AST-Knoten (statt `TemporaryNode`)

**Schichtgrenze (Review P2-5):** `CrNode` liegt aktuell als `part of katex_base`
in der Parser-Schicht (`lib/src/parser/tex/functions/katex_base/cr.dart`).
`tex_break.dart` und `math.dart` (AST-/Render-Schicht) dürfen aber nicht auf die
Parser-Schicht zugreifen. Deshalb wird die **Klasse `CrNode` in ein echtes
AST-Node-File verschoben**: neu `lib/src/ast/nodes/cr.dart`. Die Parser-Function
`_crHandler` bleibt in der Parser-`cr.dart` und konstruiert nur noch den
AST-Knoten (Import des neuen Node-Files über die `katex_base`-Library). Umgebungen
(`array.dart`, `eqn_array.dart`) importieren den AST-Knoten direkt.

`CrNode` erbt künftig von `LeafNode` (wie `SpaceNode`) statt von `TemporaryNode`
und erhält konkrete Implementierungen:

- `buildWidget(...)` → **baseline-fähige** No-op-Box. **Nicht** eine nackte
  `SizedBox`/`Container`: das Line-Layout erzwingt
  `child.getDistanceToBaseline(textBaseline)!` (`line.dart:345`), und eine Box ohne
  Baseline liefert `null` → Crash. Daher wie `SpaceNode` über `ResetBaseline`
  wrappen, z.B. `ResetBaseline(height: 0, child: SizedBox.shrink())`
  (vgl. `space.dart:82`).
- `leftType` / `rightType` → `AtomType.ord`.
- `editingWidth` → `1` (belegt eine Cursor-Position, damit
  `caretPositions`/`clipChildrenBetween` für das Splitting wohldefiniert sind).
- `shouldRebuildWidget(...)` → `false`.
- `mode` → `Mode.math` (wie bisher).

Felder `newLine`, `newRow`, `size` bleiben erhalten.

**Auswirkungen:**
- Umgebungen konsumieren `CrNode` weiterhin während des Parsens
  (`assertNodeType<CrNode>` prüft den Laufzeittyp; unverändert). Sie bauen den
  Knoten nie, d.h. die neue `buildWidget`-Implementierung ist dort irrelevant.
- **Bonus:** Bisher crashende Fälle (`\\` in einer Gruppe, ein nicht konsumierter
  `CrNode`) rendern jetzt als No-op statt zu werfen.

> Prüfauftrag für die Implementierung: sicherstellen, dass nirgends
> `CrNode is TemporaryNode` o.ä. vorausgesetzt wird (Grep `TemporaryNode`).

### Baustein 2 — `texBreak()` erkennt Top-Level-`CrNode` als Pflichtumbruch

In `EquationRowNodeTexStyleBreakExt.texBreak` (`tex_break.dart:38`) wird die
Schleife um einen Fall erweitert: ist ein Kind ein `CrNode`, wird an dieser Stelle
ein Umbruchpunkt mit Pflicht-Penalty (`-10000`, TeX-Konvention für erzwungenen
Umbruch) hinzugefügt.

Damit liefert `Math.texBreak()` die `\\`-Umbrüche als Bruchstellen aus — die
KaTeX-treue, entwicklergesteuerte Mehrzeilen-Variante (Teile in `Wrap`/`Column`).

### Baustein 3 — `Math.build` splittet automatisch in eine linksbündige Column

Neue Hilfsmethode auf `EquationRowNode`, z.B.
`BreakResult<EquationRowNode> splitAtNewlines()`:

- Zerlegt die Zeile **nur an Top-Level-`CrNode`s** (nicht an den weichen
  bin/rel-Bruchstellen). Nutzt `clipChildrenBetween` / `caretPositions` wie
  `texBreak`, aber mit **anderer Schnittlogik (Review P2-3):** `texBreak` schneidet
  bis `caretPositions[breakIndex + 1]` und nimmt den Break-Knoten ins *vorige*
  Segment mit (`tex_break.dart:80`). Der `CrNode` ist hier aber ein **Trenner** und
  muss aus *beiden* Segmenten heraus: also bis `caretPositions[breakIndex]`
  schneiden (vor dem `CrNode`) und ab `caretPositions[breakIndex + 1]` fortsetzen
  (nach dem `CrNode`).
- Gibt die Segmente (je eine `EquationRowNode` ohne die `CrNode`s) zurück, plus die
  vertikalen Abstände aus `CrNode.size` je Trenner.

`Math.build` (`math.dart:200`) wird angepasst:

```text
if (top-level row enthält CrNode) {
  parts, gaps = ast.splitAtNewlines()
  child = Column(
    crossAxisAlignment: start,
    mainAxisSize: min,
    children: [ lineFor(part0), gap0?, lineFor(part1), gap1?, … ]
  )
} else {
  child = ast.buildWidget(options)                 // unveränderter Pfad
}
```

- `gap` zwischen zwei Zeilen: `SizedBox(height: size)` aus `CrNode.size` (für
  `\\[1em]`).
- **Leere Segmente brauchen explizite Höhe (Review P1-2):** eine leere
  `EquationRowNode` baut zu `Line(children: [])`, das hat wegen `minHeight = 0`
  (`line.dart:96`) keine Höhe → die Leerzeile verschwände. `lineFor(part)` gibt für
  ein leeres Segment daher **`SizedBox(height: options.fontSize)`** zurück.
  Konkretes, deterministisches Maß: `options.fontSize` ist genau die Größe, die das
  Package bereits als „preferred line height" verwendet (`selectable.dart:553`:
  `preferredLineHeight => widget.options.fontSize`). Der Widget-Test prüft die Höhe
  **gegen denselben Ausdruck** (`options.fontSize`), nicht gegen einen hartcodierten
  Pixelwert → stabil gegenüber Font-/Metrik-Änderungen.

`SelectableMath` bleibt unverändert (eigener Build-Pfad; siehe Detail #1).

### Wo NICHT eingegriffen wird
- `TexParser.parse()` / `parseExpression`: keine Änderung. `CrNode`s bleiben in der
  Top-Level-Knotenliste; das Splitting passiert erst im Widget-Build.
- Umgebungs-Parser (`array.dart`, `eqn_array.dart`): keine Änderung.

## 4. Detail-Verhalten

| # | Fall | Verhalten | Begründung |
|---|---|---|---|
| 1 | **Scope** | Auto-Split nur in `Math`. `SelectableMath` rendert einzeilig (CrNode = No-op-Box, kein Crash); mehrzeilig dort via `texBreak()` | Selektion von `SelectableMath` hängt an *einer* editierbaren Zeile |
| 2 | **Nachgestelltes `\\`** (`a \\ b \\`) | letzte leere Zeile **verwerfen** (≙ `a \\ b`) | konsistent mit `\crcr`-Logik der Umgebungen (`array.dart:151`: `row.length == 1 && cellBody.isEmpty`) |
| 3 | **Führende/innere leere Zeile** (`\\ a`, `a \\\\ b`) | bleibt als **echte Leerzeile** mit expliziter Höhe (siehe Baustein 3) | bewusste Leerzeilen erhalten |
| 4 | **`\\[1em]`** | vertikaler `SizedBox` aus `CrNode.size` zwischen den Zeilen | nutzt vorhandenes `size`-Feld |
| 5 | **`displayMode` + strict** | `newLine`-Flag **ignorieren**, immer umbrechen | `displayMode` per Default `false`; bewusste, dokumentierte Abweichung von KaTeX |
| 6 | **`\\` in Gruppe** (`{a \\ b}`) | rendert als **No-op** (kein Umbruch, kein Crash) | `CrNode` ist jetzt renderbar; bekannte Grenze |
| 7 | **Ausrichtung** | linksbündig (`crossAxisAlignment.start`) | KaTeX-treu |
| 8 | **Kein `\\`** | unverändert ein Widget (`ast.buildWidget`) | Null-Overhead-Pfad, keine Regression |
| 9 | **Top-Level `\cr`** | bricht um wie `\\` | **bewusste Abweichung von KaTeX:** dort ist `\cr` nur *innerhalb* von Array-Umgebungen gültig (`array.ts:120`, gruppen-lokales Makro) und am Top-Level ein Fehler. `\\`/`\newline` bleiben dagegen KaTeX-treu |

## 5. Betroffene Dateien

| Datei | Änderung |
|---|---|
| `lib/src/ast/nodes/cr.dart` *(neu)* | `CrNode` als renderbarer `LeafNode` (baseline-fähig via `ResetBaseline`); aus der Parser-Schicht hierher verschoben |
| `lib/src/parser/tex/functions/katex_base/cr.dart` | nur noch `_crEntries` + `_crHandler` (konstruiert den AST-`CrNode`); Klassendefinition entfällt |
| `lib/src/parser/tex/functions/katex_base.dart` | Import des neuen Node-Files sicherstellen |
| `lib/src/parser/tex/environments/array.dart`, `eqn_array.dart` | Import-Pfad für `CrNode` anpassen (AST statt Parser) |
| `lib/src/ast/tex_break.dart` | `texBreak`: `CrNode` als Pflichtumbruch (-10000); neue `EquationRowNode.splitAtNewlines()` (gleiche Extension-Datei wie `texBreak`) |
| `lib/src/widgets/math.dart` | `build`: Auto-Split in linksbündige `Column` bei Top-Level-`CrNode`; leere Segmente mit expliziter Zeilenhöhe |

## 6. Teststrategie

Alle Tests über die vorhandenen Helfer (`test/helper.dart`: `getParsed`, `toBuild`)
bzw. Widget-Tests.

**Unit (AST / Parser):**
- `getParsed(r'a \\ b')` enthält weiterhin `[Symbol, CrNode, Symbol]` (Parsing
  unverändert).
- `splitAtNewlines()`: `a \\ b` → 2 Teile; `a \\ b \\` → 2 Teile (trailing verworfen);
  `\\ a` → 2 Teile (leer + `a`); `a \\\\ b` → 3 Teile (leere Mittelzeile); `a + b`
  → 1 Teil (kein Split).
- `\\[1em]`: Gap-Maß wird korrekt eingesammelt.

**Build / Widget:**
- `r'a \\ b'` baut **ohne** Exception (Regression gegen den aktuellen Crash) — via
  `expect(r'a \\ b', toBuild)`.
- `r'\cr'`, `r'a \newline b'` bauen ohne Exception.
- **Baseline (Review P1-1):** ein `CrNode`, der *nicht* weggesplittet wird, baut
  ohne `getDistanceToBaseline`-Crash — z.B. `r'{a \\ b}'` (CrNode in Gruppe) und
  `SelectableMath.tex(r'a \\ b')` bauen ohne Exception.
- `Math.tex(r'a \\ b')` erzeugt eine `Column` mit 2 Kindern, linksbündig.
- **Leerzeilenhöhe (Review P1-2):** `Math.tex(r'a \\\\ b')` erzeugt drei Zeilen,
  die mittlere (leer) hat eine Höhe > 0 (kein Kollaps).
- Umgebungen unverändert grün: `\begin{matrix}…\\…\end{matrix}`,
  `\begin{aligned}…\end{aligned}`, `\begin{cases}…\end{cases}` bauen weiter.

**texBreak:**
- `Math.tex(r'a \\ b').texBreak()` liefert 2 Teile mit Pflicht-Penalty am `\\`.

**Gesamte Suite:** `flutter test` bleibt vollständig grün; keine Golden-Regression
für bestehende Ausdrücke (Single-Widget-Pfad unverändert, wenn kein `\\` vorhanden).

## 7. Bekannte Grenzen & bewusste Abweichungen von KaTeX (dokumentiert)

**Was KaTeX-treu bleibt:** die Knoten-Repräsentation (`\\` = Break-im-Fluss, keine
Umgebung) und das Verhalten von `\\` und `\newline` am Top-Level.

**Grenzen (v1):**
- Kein Auto-Split in `SelectableMath`.
- `\\` innerhalb `{ … }` ist ein No-op (kein Umbruch).
- Keine `&`-Spaltenausrichtung am Top-Level.

**Bewusste Abweichungen von KaTeX:**
- **Top-Level `\cr`** wird hier gerendert (Umbruch). KaTeX erlaubt `\cr` nur
  innerhalb von Array-Umgebungen (`array.ts:120`); am Top-Level ist es dort ein
  Fehler. flutter_math behandelt `\cr` am Top-Level bewusst wie `\\` (Detail #9).
- **`displayMode` + strict:** KaTeXs „`\\` ist im Display-Mode ein No-op" wird nicht
  nachgebildet — wir brechen immer um (Detail #5).

## 8. KaTeX-Referenzpfade

- `KaTeX-main/src/functions/cr.ts` — `cr`-Knoten + `htmlBuilder` (`mspace`/`newline`).
- `KaTeX-main/src/environments/array.ts` — Konsum von `cr` in Arrays.

## 9. Review-Korrekturen (2026-06-16)

Gegen den ersten Entwurf eingearbeitete, am Code verifizierte Befunde:

- **P1-1:** `CrNode.buildWidget` muss baseline-fähig bauen (`ResetBaseline`), sonst
  `getDistanceToBaseline(...)!`-Crash in `line.dart:345`. → Baustein 1.
- **P1-2:** Leere Segmente brauchen explizite Höhe (`minHeight = 0` in
  `line.dart:96`), sonst verschwinden Leerzeilen. → Baustein 3, Detail #3.
- **P2-3:** `splitAtNewlines()` muss um den `CrNode` herum schneiden (vor/nach),
  nicht wie `texBreak` den Trenner ins vorige Segment ziehen. → Baustein 3.
- **P2-4:** Trailing-Empty-Referenz korrigiert: `array.dart:151`, nicht
  `eqn_array.dart:198`. → Detail #2.
- **P2-5:** Schichtgrenze — `CrNode` ins AST-Modul (`lib/src/ast/nodes/cr.dart`)
  verschieben, da AST/Render nicht auf die Parser-Schicht zugreifen darf.
  → Baustein 1, §5.
