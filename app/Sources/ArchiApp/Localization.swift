// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Interface language of the ribbon (SYS-026): tab, panel and main tool names in English, Romanian, German, French,
/// Spanish and Italian. Command names typed on the command line stay English (as in localized AutoCAD's "_" names),
/// so scripts work in every language. "auto" follows the macOS language list.
enum L10n {
    static let key = "uiLanguage"
    static let languages: [(code: String, name: String)] = [("en", "English"), ("ro", "Română"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("it", "Italiano")]
    private static let order = ["ro", "de", "fr", "es", "it"]

    /// Stored choice ("auto" or a language code).
    static var setting: String {
        get { UserDefaults.standard.string(forKey: key) ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    /// Language actually used for a setting.
    static func resolved(_ s: String = setting, preferred: [String] = Locale.preferredLanguages) -> String {
        if s != "auto" { return languages.contains { $0.code == s } ? s : "en" }
        for p in preferred {
            let c = String(p.prefix(2)).lowercased()
            if languages.contains(where: { $0.code == c }) { return c }
        }
        return "en"
    }
    /// Translation of an English ribbon string (the English text when there is none).
    static func t(_ s: String, _ lang: String? = nil) -> String {
        let l = resolved(lang ?? setting)
        guard l != "en", let row = table[s] ?? menuTable[s], let i = order.firstIndex(of: l), i < row.count else { return s }
        return row[i]
    }
    /// Share of the ribbon's tab and panel names translated for a language (0…1).
    static func coverage(_ lang: String, of strings: [String]) -> Double {
        guard !strings.isEmpty else { return 1 }
        return Double(strings.filter { t($0, lang) != $0 || table[$0]?.contains($0) == true }.count) / Double(strings.count)
    }

    /// English → [ro, de, fr, es, it].
    static let table: [String: [String]] = [
        // Tabs
        "Home": ["Acasă", "Start", "Accueil", "Inicio", "Home"],
        "Insert": ["Inserare", "Einfügen", "Insérer", "Insertar", "Inserisci"],
        "Annotate": ["Adnotare", "Beschriften", "Annoter", "Anotar", "Annota"],
        "Architecture": ["Arhitectură", "Architektur", "Architecture", "Arquitectura", "Architettura"],
        "Modeling": ["Modelare", "Modellierung", "Modélisation", "Modelado", "Modellazione"],
        "Analyze": ["Analiză", "Analysieren", "Analyser", "Analizar", "Analizza"],
        "Collaborate": ["Colaborare", "Zusammenarbeit", "Collaborer", "Colaborar", "Collabora"],
        "View": ["Vizualizare", "Ansicht", "Vue", "Vista", "Vista"],
        "Output": ["Ieșire", "Ausgabe", "Sortie", "Salida", "Output"],
        "Manage": ["Gestionare", "Verwalten", "Gérer", "Administrar", "Gestisci"],
        "Script": ["Script", "Skript", "Script", "Script", "Script"],
        // Panels
        "3D Measure": ["Măsurare 3D", "3D-Messen", "Mesure 3D", "Medición 3D", "Misura 3D"],
        "3D Operations": ["Operații 3D", "3D-Operationen", "Opérations 3D", "Operaciones 3D", "Operazioni 3D"],
        "3D Tools": ["Unelte 3D", "3D-Werkzeuge", "Outils 3D", "Herramientas 3D", "Strumenti 3D"],
        "AI Agents": ["Agenți AI", "KI-Agenten", "Agents IA", "Agentes IA", "Agenti IA"],
        "Automation": ["Automatizare", "Automatisierung", "Automatisation", "Automatización", "Automazione"],
        "Block & Reference": ["Bloc și referință", "Block & Referenz", "Bloc et référence", "Bloque y referencia", "Blocco e riferimento"],
        "Booleans": ["Operații booleene", "Boolesche Operationen", "Booléens", "Booleanas", "Booleane"],
        "Build": ["Construcție", "Bauen", "Construire", "Construir", "Costruisci"],
        "Build+": ["Construcție+", "Bauen+", "Construire+", "Construir+", "Costruisci+"],
        "Building Physics": ["Fizica clădirii", "Bauphysik", "Physique du bâtiment", "Física del edificio", "Fisica tecnica"],
        "Checks": ["Verificări", "Prüfungen", "Vérifications", "Comprobaciones", "Verifiche"],
        "Cleanup": ["Curățare", "Bereinigen", "Nettoyage", "Limpieza", "Pulizia"],
        "Content": ["Conținut", "Inhalte", "Contenu", "Contenido", "Contenuti"],
        "Coordination": ["Coordonare", "Koordination", "Coordination", "Coordinación", "Coordinamento"],
        "Dimensions": ["Cote", "Bemaßung", "Cotes", "Cotas", "Quote"],
        "Documentation": ["Documentație", "Dokumentation", "Documentation", "Documentación", "Documentazione"],
        "Draw": ["Desenare", "Zeichnen", "Dessiner", "Dibujo", "Disegna"],
        "Export": ["Export", "Export", "Exporter", "Exportar", "Esporta"],
        "Groups": ["Grupuri", "Gruppen", "Groupes", "Grupos", "Gruppi"],
        "History": ["Istoric", "Verlauf", "Historique", "Historial", "Cronologia"],
        "Images & Geo": ["Imagini și geo", "Bilder & Geo", "Images et géo", "Imágenes y geo", "Immagini e geo"],
        "Import": ["Import", "Import", "Importer", "Importar", "Importa"],
        "Inquiry": ["Interogare", "Abfrage", "Requête", "Consulta", "Interroga"],
        "Interface": ["Interfață", "Oberfläche", "Interface", "Interfaz", "Interfaccia"],
        "Layers": ["Straturi", "Layer", "Calques", "Capas", "Layer"],
        "Leaders & Tables": ["Indicatoare și tabele", "Führungslinien & Tabellen", "Repères et tableaux", "Directrices y tablas", "Direttrici e tabelle"],
        "Level": ["Nivel", "Geschoss", "Niveau", "Nivel", "Livello"],
        "Library": ["Bibliotecă", "Bibliothek", "Bibliothèque", "Biblioteca", "Libreria"],
        "Measure": ["Măsurare", "Messen", "Mesurer", "Medir", "Misura"],
        "Model": ["Model", "Modell", "Modèle", "Modelo", "Modello"],
        "Modify": ["Modificare", "Ändern", "Modifier", "Modificar", "Modifica"],
        "More": ["Mai mult", "Mehr", "Plus", "Más", "Altro"],
        "Navigate": ["Navigare", "Navigieren", "Naviguer", "Navegar", "Naviga"],
        "Panels": ["Panouri", "Paletten", "Panneaux", "Paneles", "Pannelli"],
        "Parametric": ["Parametric", "Parametrisch", "Paramétrique", "Paramétrico", "Parametrico"],
        "Plot": ["Plotare", "Plotten", "Tracer", "Trazar", "Stampa"],
        "Presentation": ["Prezentare", "Präsentation", "Présentation", "Presentación", "Presentazione"],
        "Properties": ["Proprietăți", "Eigenschaften", "Propriétés", "Propiedades", "Proprietà"],
        "Quantities": ["Cantități", "Mengen", "Quantités", "Cantidades", "Quantità"],
        "Review": ["Revizuire", "Prüfen", "Révision", "Revisión", "Revisione"],
        "Room & Area": ["Încăpere și arie", "Raum & Fläche", "Pièce et surface", "Habitación y área", "Locale e area"],
        "Schedules": ["Extrase", "Listen", "Nomenclatures", "Tablas de planificación", "Abachi"],
        "Scripting": ["Scripting", "Skripting", "Scripts", "Scripts", "Scripting"],
        "Selection": ["Selecție", "Auswahl", "Sélection", "Selección", "Selezione"],
        "Settings": ["Setări", "Einstellungen", "Réglages", "Ajustes", "Impostazioni"],
        "Share": ["Partajare", "Teilen", "Partager", "Compartir", "Condividi"],
        "Sheets": ["Planșe", "Pläne", "Feuilles", "Planos", "Tavole"],
        "Site": ["Amplasament", "Gelände", "Site", "Emplazamiento", "Sito"],
        "Solid Editing": ["Editare solide", "Volumenkörper bearbeiten", "Édition de solides", "Edición de sólidos", "Modifica solidi"],
        "Solids": ["Solide", "Volumenkörper", "Solides", "Sólidos", "Solidi"],
        "Style": ["Stil", "Stil", "Style", "Estilo", "Stile"],
        "Surfaces": ["Suprafețe", "Flächen", "Surfaces", "Superficies", "Superfici"],
        "Text": ["Text", "Text", "Texte", "Texto", "Testo"],
        "Versions & Issues": ["Versiuni și probleme", "Versionen & Probleme", "Versions et problèmes", "Versiones e incidencias", "Versioni e problemi"],
        "Views": ["Vederi", "Ansichten", "Vues", "Vistas", "Viste"],
        "Visual Programming": ["Programare vizuală", "Visuelle Programmierung", "Programmation visuelle", "Programación visual", "Programmazione visuale"],
        "Visual Style": ["Stil vizual", "Visueller Stil", "Style visuel", "Estilo visual", "Stile di visualizzazione"],
        "Workspace": ["Spațiu de lucru", "Arbeitsbereich", "Espace de travail", "Espacio de trabajo", "Area di lavoro"],
        // Main tools
        "Line": ["Linie", "Linie", "Ligne", "Línea", "Linea"],
        "Polyline": ["Polilinie", "Polylinie", "Polyligne", "Polilínea", "Polilinea"],
        "Circle": ["Cerc", "Kreis", "Cercle", "Círculo", "Cerchio"],
        "Arc": ["Arc", "Bogen", "Arc", "Arco", "Arco"],
        "Rectangle": ["Dreptunghi", "Rechteck", "Rectangle", "Rectángulo", "Rettangolo"],
        "Polygon": ["Poligon", "Polygon", "Polygone", "Polígono", "Poligono"],
        "Ellipse": ["Elipsă", "Ellipse", "Ellipse", "Elipse", "Ellisse"],
        "Spline": ["Spline", "Spline", "Spline", "Spline", "Spline"],
        "Hatch": ["Hașură", "Schraffur", "Hachures", "Sombreado", "Tratteggio"],
        "Move": ["Mutare", "Schieben", "Déplacer", "Desplazar", "Sposta"],
        "Copy": ["Copiere", "Kopieren", "Copier", "Copiar", "Copia"],
        "Rotate": ["Rotire", "Drehen", "Rotation", "Girar", "Ruota"],
        "Mirror": ["Oglindire", "Spiegeln", "Miroir", "Simetría", "Specchio"],
        "Scale": ["Scalare", "Skalieren", "Échelle", "Escala", "Scala"],
        "Stretch": ["Întindere", "Strecken", "Étirer", "Estirar", "Stira"],
        "Trim": ["Tăiere", "Stutzen", "Ajuster", "Recortar", "Taglia"],
        "Extend": ["Prelungire", "Dehnen", "Prolonger", "Alargar", "Estendi"],
        "Offset": ["Decalare", "Versetzen", "Décaler", "Desfase", "Offset"],
        "Fillet": ["Racordare", "Abrunden", "Raccord", "Empalme", "Raccorda"],
        "Chamfer": ["Teșire", "Fase", "Chanfrein", "Chaflán", "Cima"],
        "Array": ["Multiplicare", "Reihe", "Réseau", "Matriz", "Serie"],
        "Explode": ["Descompunere", "Ursprung", "Décomposer", "Descomponer", "Esplodi"],
        "Erase": ["Ștergere", "Löschen", "Effacer", "Borrar", "Cancella"],
        "Join": ["Unire", "Verbinden", "Joindre", "Juntar", "Unisci"],
        "Break": ["Întrerupere", "Bruch", "Coupure", "Partir", "Interrompi"],
        "MText": ["Text multilinie", "Absatztext", "Texte multiligne", "Texto multilínea", "Testo multilinea"],
        "Linear": ["Liniară", "Linear", "Linéaire", "Lineal", "Lineare"],
        "Aligned": ["Aliniată", "Ausgerichtet", "Alignée", "Alineada", "Allineata"],
        "Angular": ["Unghiulară", "Winkel", "Angulaire", "Angular", "Angolare"],
        "Radius": ["Rază", "Radius", "Rayon", "Radio", "Raggio"],
        "Diameter": ["Diametru", "Durchmesser", "Diamètre", "Diámetro", "Diametro"],
        "Leader": ["Indicator", "Führungslinie", "Ligne de repère", "Directriz", "Direttrice"],
        "Table": ["Tabel", "Tabelle", "Tableau", "Tabla", "Tabella"],
        "Wall": ["Perete", "Wand", "Mur", "Muro", "Muro"],
        "Door": ["Ușă", "Tür", "Porte", "Puerta", "Porta"],
        "Window": ["Fereastră", "Fenster", "Fenêtre", "Ventana", "Finestra"],
        "Opening": ["Gol", "Öffnung", "Ouverture", "Hueco", "Apertura"],
        "Curtain Wall": ["Perete cortină", "Vorhangfassade", "Mur-rideau", "Muro cortina", "Facciata continua"],
        "Column": ["Stâlp", "Stütze", "Poteau", "Pilar", "Pilastro"],
        "Beam": ["Grindă", "Träger", "Poutre", "Viga", "Trave"],
        "Slab": ["Placă", "Decke", "Dalle", "Losa", "Solaio"],
        "Roof": ["Acoperiș", "Dach", "Toit", "Cubierta", "Tetto"],
        "Ceiling": ["Tavan", "Unterdecke", "Plafond", "Techo", "Controsoffitto"],
        "Stair": ["Scară", "Treppe", "Escalier", "Escalera", "Scala"],
        "Railing": ["Balustradă", "Geländer", "Garde-corps", "Barandilla", "Ringhiera"],
        "Room": ["Încăpere", "Raum", "Pièce", "Habitación", "Locale"],
        "Grid": ["Axe", "Raster", "Quadrillage", "Rejilla", "Griglia"],
        "Component": ["Componentă", "Bauteil", "Composant", "Componente", "Componente"],
        "Quick Building": ["Clădire rapidă", "Schnellgebäude", "Bâtiment rapide", "Edificio rápido", "Edificio rapido"],
    ]

    @MainActor static var command: CommandDef {
        CommandDef("LANGUAGE", aliases: ["UILANGUAGE", "LIMBA", "SPRACHE", "LANGUE", "IDIOMA", "LINGUA"], category: "Settings", summary: "Interface language of the ribbon: Auto (macOS), English, Română, Deutsch, Français, Español, Italiano. Commands stay English.", modifies: false) { ed in
            let names = ["Auto"] + languages.map(\.name)
            let cur = setting == "auto" ? "Auto" : (languages.first { $0.code == setting }?.name ?? "Auto")
            let k = try await ed.getKeyword("Interface language [" + names.joined(separator: "/") + "] <\(cur)>", names, defaultValue: cur) ?? cur
            setting = k == "Auto" ? "auto" : (languages.first { $0.name == k }?.code ?? "en")
            ed.print("Interface language: \(k)" + (k == "Auto" ? " (\(languages.first { $0.code == resolved() }?.name ?? "English"))" : "") + ".")
        }
    }
}
