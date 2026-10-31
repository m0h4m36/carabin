# Spécification fonctionnelle — application de révision pour étudiants en médecine

Nom du projet : **Carabin** (différent de l'appli d'origine).
Licence : Apache-2.0 (voir `LICENSE`).
Règle de projet : spec écrite à partir de l'observation de l'appli et de sa documentation publique, jamais à partir de son code. Aucun visuel, texte ou logo repris.

Version v5 (31/10/2026) : complétée après quatre parcours de l'appli sur Windows (premier lancement, Items, Réglages, Planning, Mes J, QCM de la composition à la copie, Flashcards de la création à la fin d'une séance et de l'auto-test, Cours, atelier d'annotation avec ses panneaux de notes et d'erreurs, carnet d'erreurs, studio de création de cartes, onglet Examen, recherche globale, synchronisation du dossier). Les parties marquées « à vérifier » ou listées en section 18 n'ont pas été observées.

---

## 1. Principes

- Fonctionne hors connexion, sans compte.
- Les données restent sur l'appareil.
- Tout est stocké dans un dossier ordinaire, lisible sans l'application.
- Les documents importés ne sont jamais modifiés : les annotations vivent dans une copie.
- Plateformes cibles : iOS/iPadOS/macOS en priorité, puis Windows, Android, Linux.

## 2. Données et stockage

- Dossier racine unique choisi au premier lancement : un écran propose soit de créer un dossier à l'emplacement par défaut (sous « Documents »), soit d'en ouvrir un existant. Il précise que tout reste sur le disque et que l'app fonctionne hors connexion.
- Le dossier peut être sauvegardé ou déplacé comme n'importe quel autre ; renommé ou déplacé depuis l'explorateur de fichiers, l'app le retrouve.
- Structure observée sur le disque (noms à reprendre dans l'esprit, pas forcément à l'identique) :
  - une base SQLite à la racine (cartes, historique de révision, QCM, copies, planning, erreurs), avec ses fichiers journaux (mode WAL) ; elle ne doit jamais être copiée à chaud sans fermer l'appli
  - `Cours/<année>/<semestre>/<matière>/<thème>/` : un dossier par thème, qui contient les polys (le PDF importé, les annotations et notes vivent à côté)
  - `Decks/<année>/<semestre>/<matière>/` pour les paquets rangés par matière, et `Decks/Sans matière/<paquet>/` pour les autres ; un petit fichier JSON décrit chaque paquet
  - `QCM/<année>/<semestre>/<matière>/` de la même façon, et `QCM/Sans matière/<série>.qcm.json` : une épreuve = un fichier JSON lisible et partageable
  - `Archives/` avec trois sous-dossiers (Cours, Flashcards, QCM) pour ce qui est supprimé
- Réglages du dossier :
  - Synchroniser : relire le dossier et intégrer les fichiers ajoutés ou déplacés (aucune suppression sans confirmation). Un PDF déposé à la main dans un dossier de thème est repris au clic : l'appli affiche un bilan en trois lignes (fichiers du dossier ajoutés à l'appli, fichiers rangés selon l'appli annotations et notes comprises, paquets de cartes écrits dans le dossier et rangés comme les cours). Testé : c'est le chemin de repli fiable quand le sélecteur de fichier ne s'ouvre pas
  - Déplacer / renommer le dossier
  - Changer de dossier : copier vers une nouvelle destination, conserver l'ancien (sert de sauvegarde ; utile pour passer sur un autre disque)
  - Distinction à garder : renommer/déplacer ne copie rien (le dossier bouge, l'app suit) ; changer de dossier copie tout (base, polys, paquets)
- iCloud (Apple uniquement) pour partager le dossier entre appareils. Avertir de ne pas placer le dossier dans un autre service de synchronisation (risque de corruption de la base).
- Désinstaller l'app ne supprime pas le dossier (ordinateur).

## 3. Cours

### 3.1 Hiérarchie
Année → Semestre → Matière → Thème (= chapitre). Le bouton s'appelle « Thème » mais la fenêtre de création parle de « groupe » : un seul concept, à nommer de façon unique dans la version libre.
Un thème rattache : polys, paquets de cartes, épreuves QCM (par correspondance de nom avec la matière), erreurs, progression.

### 3.2 Gestion
- Écran d'accueil de « Cours » vide : une seule invitation à créer une année, avec un champ de recherche de polys et un bouton d'import en haut. La barre latérale ajoute alors le niveau année · semestre, puis les matières dépliables (un thème par ligne) et une rubrique « Récents » qui rouvre directement un poly.
- Fenêtre « Nouvelle année » : année (exemple DFGSM2 2025-2026), semestre et matière facultatifs, zone de dépôt de polys facultative (PDF, Word, image : chaque poly devient un thème au nom du cours).
- Fenêtre « Nouvelle matière » : nom, couleur (treize pastilles, une pipette de couleur personnalisée, valeur hexadécimale et RVB affichées), zone de dépôt de polys.
- Niveau matières (grille ou liste, bouton « + Matière », menu « ⋯ ») : une carte par matière avec couleur, « n thème · n poly », barre de répartition des cartes (état « aucune » tant qu'il n'y en a pas), état d'avancement (« pas encore commencé »), bouton « Ouvrir la matière ».
- Niveau thèmes : une carte par thème avec bandeau de la couleur de la matière, poignée de glisser-déposer, crayon (renommer) et corbeille au survol, liste de ses polys avec type (PDF…), état de lecture (« pas encore lu » + six pastilles) et « n document(s) » ; un thème vide invite à importer un PDF ou à y glisser un poly d'un autre thème ; tuile en pointillés « Nouveau thème » ; fenêtre « Nouveau groupe » (dépôt de polys, ou nom d'un groupe vide).
- Sélection multiple pour déplacer ou supprimer, réordonnancement par glisser-déposer.
- Suppression = déplacement dans Archives (le menu d'un poly propose pourtant aussi « Supprimer définitivement » : à confirmer deux fois).

### 3.3 Import
- Formats : PDF, Word (DOCX), images, texte. Bouton « Importer » dans un thème, ou glisser des fichiers depuis l'explorateur de fichiers sur le thème.
- Remarque d'observation : sur Windows, le sélecteur de fichiers lancé par « Importer » ne s'est pas affiché dans l'environnement de test (la fenêtre de l'appli est passée en inactif sans qu'aucune boîte ne soit visible). À implémenter avec le sélecteur natif de la plateforme et à tester tôt.
- Import d'un dossier complet ou d'un .zip avec son arborescence, sans doublon.
- Dépôt direct de fichiers dans `Cours/` puis « Synchroniser ».
- OCR local sur les pages scannées pour rendre le texte sélectionnable.

### 3.4 Écran d'un thème (observé)
Fil d'Ariane cliquable (Cours › année › semestre › matière › thème), recherche de polys, bouton « Importer ». Deux panneaux côte à côte.

**Panneau gauche « Le cours »**
- En-tête : flèches précédent/suivant entre les documents du thème (« 1/1 »), nom du poly, crayon pour le renommer, et un compteur double (nombre de fichiers, nombre d'erreurs en rouge) qui ouvre un tiroir « Fichiers ».
- Tiroir « Fichiers » : champ de filtre, liste « Tous les documents » (un bouton à icône de dossier permet probablement de créer des dossiers de rangement), ligne « Erreurs hors poly » avec son compteur.
- Aperçu défilant du poly, gros bouton « Consulter » (ouvre l'atelier, section 4) et bouton « ⋯ » : ouvrir hors de l'appli, montrer le PDF annoté dans le gestionnaire de fichiers, supprimer définitivement (en rouge).
- Quand le thème est vide : message d'invitation à importer un PDF, un DOCX ou une image, ou à glisser des fichiers.

**Panneau droit « Mon travail »** (accordéons)
- En-tête : six pastilles de lecture + « jamais relu » (ou le nombre de lectures), puis le résultat des QCM et des cartes du cours, « — » tant qu'il n'y en a pas.
- Flashcards : « Aucune carte pour ce poly » ; l'appli suggère un paquet existant dont le nom partage des mots avec le poly (« ce paquet semble aller avec ce poly, mots communs : … ») avec un bouton « Associer » ; bouton « Créer mes premières cartes » (ouvre le studio, section 5.2, après avoir demandé dans quel paquet ranger les cartes, avec « Nouveau paquet » et « Quitter l'atelier »).
- QCM du cours : épreuves de la matière dont le nom correspond (« aucune épreuve à ce nom dans la matière » sinon).
- Erreurs : formulaire « ce que j'ai raté » (titre court), état À revoir / Comprise, bouton « Capturer un passage » (cadre une zone du poly), note libre (pourquoi je me suis trompé, ce qu'il faut retenir), « Ajouter au carnet ». Dessous, la liste des erreurs du chapitre qui n'ont pas de poly (titre, note, état, corbeille, bouton « Rattacher à ce poly »).
- Documents joints : TD, photo, mémo vocal, lien (rangés avec le poly, voir le panneau « Notes » de l'atelier, section 4.1).
- Les erreurs d'un thème sans poly (TD, colle, cours pris à la main) se notent dans le même formulaire ; elles reviennent avec les autres dans le carnet (section 9).

## 4. Atelier (lecture et annotation)

Plein écran (la barre latérale disparaît), ouvert par « Consulter » ou depuis « Récents ». La touche Échap ferme l'atelier (ne pas s'en servir pour fermer un menu : prévoir un autre geste). En mode comparaison, un premier Échap quitte la comparaison. Une remarque restée sans texte disparaît quand on quitte la saisie avec Échap. Un petit chronomètre de séance flotte en bas à gauche (un par panneau en comparaison), avec pause et masquage.

### 4.1 Barre du haut
- Titre du poly et chemin (matière · thème).
- « Relu » : six pastilles à cocher, une par lecture complète ; un second clic sur une pastille la décoche. Cocher une lecture remet le chronomètre de séance à zéro.
- Sommaire : panneau latéral qui liste les titres repérés dans le texte avec leur numéro de page (cliquer pour y aller) ; fermable, repliable.
- Chercher : recherche dans le document.
- Numéro de page « n / N » modifiable, zoom − / pourcentage / + (l'ouverture du sommaire réajuste la largeur).
- Bouton à icône de stylo : masque la barre d'outils du bas, qui se réduit à une petite pastille ronde (flèche) ; un second clic la rétablit.
- Bouton œil : masque ou affiche toutes les annotations du poly (surlignages, remarques, post-it) sans les effacer.
- Bouton d'enregistrement/export (icône de téléchargement) : non testé par prudence (boîte de dialogue native) ; probablement l'export du PDF annoté.
- Bouton d'enregistrement/export (non testé : probablement l'export du PDF annoté).
- Comparer : fenêtre avec champ « rechercher un cours, une photo… », quatre dispositions du second document (gauche, droite, haut, bas) en boutons, arbre matière › thème › poly, et bouton « Photo ou PDF… » pour un fichier extérieur. Observé en comparant un poly avec lui-même : l'écran se coupe en deux panneaux ayant chacun sa barre du haut (sommaire, recherche, page, zoom, œil, export), son sommaire et son chronomètre ; la barre d'outils du bas reste unique. Quand la fenêtre est étroite la barre de chaque panneau déborde (prévoir un repli en menu).
- Pastille de couleur : ouvre un petit panneau « couleur » (une douzaine de pastilles, une pipette, la valeur hexadécimale du choix et un bouton « prendre sur l'écran ») qui s'applique aux pastilles et badges du cours ; la portée exacte (poly ou matière) est à vérifier. Un second panneau de six miniatures de dispositions s'est ouvert en même temps lors du test, usage non identifié (à vérifier). Bouton de fermeture à l'extrémité de la barre.
- Bouton « Réviser » : ouvre un petit menu proposant « Réviser ses n cartes » (les cartes rattachées à ce poly, révision FSRS de la section 5.5).
- Volet d'onglets (chevron en haut à gauche) : plusieurs documents ouverts en onglets, bouton « + » pour en ouvrir un autre.

### 4.2 Barre d'outils du bas (flottante, déplaçable par sa poignée)
De gauche à droite, chaque outil ouvre sa propre sous-barre avec un bouton « < » pour revenir :
1. Pointeur / lecture : sélection de texte, navigation.
2. Stylo : cinq outils (stylo, feutre, crayon, surligneur, gomme) ; cinq épaisseurs ; six couleurs (noir, bleu, rouge, vert, vert sombre, couleur personnalisée) ; annuler/rétablir. La gomme grise l'épaisseur et la couleur. L'icône de l'outil précédemment choisi reste affichée dans la barre principale.
3. Remarque : note rattachée à un passage, avec un **type** qui s'écrit sur l'annotation (Question, Remarque, Piège, À demander au prof par défaut, chacun avec sa couleur pastel). Menu « ⋯ » : éditeur de types (renommer, choisir parmi cinq teintes, « + Nouveau type »). Le type, et non la couleur, porte le sens, et il se retrouve sur les autres appareils. Comportement observé : on sélectionne un passage avec l'outil ; la remarque est créée aussitôt (type Question par défaut), le passage est souligné en pointillés, l'outil retombe sur le pointeur, et une carte d'édition apparaît sous la page (liste des types, passage cité, zone « Votre remarque… »). Elle est comptée dans le panneau « Notes » (ligne « p. n · type · texte », « sans texte » tant qu'elle est vide).
4. Texte : famille de police, taille (− 14 +), gras, italique, souligné, barré, alignement, couleur de fond, couleur du texte (cinq plus une personnalisée).
5. Formes : rectangle, ellipse, trait, flèche ; quatre épaisseurs ; couleurs ; remplissage.
6. Ruban : masque un passage pour le réciter, trois styles (fin, rose, plein), cinq couleurs plus une personnalisée, boutons « tout masquer » et « tout révéler ».
7. Post-it : cinq types de couleur nommés (dont un type « mnémo »), « ⋯ » pour les gérer. Comportement observé : un clic sur la page pose une carte jaune avec un menu de type en tête (« Remarque » par défaut), une croix pour annuler, une coche pour valider, une zone de texte, une poignée de redimensionnement et un petit sélecteur « Post-it | Remarque » en dessous. Une fois validé, le texte reste affiché et une corbeille rouge apparaît dans le coin. La sous-barre propose cinq couleurs, « ⋯ », annuler et rétablir.
8. Noter une erreur (triangle) : bascule en mode capture (le pointeur se désactive) ; on tire un rectangle sur la page, ce qui ouvre le panneau latéral « Notes » sur son onglet « Erreurs n » avec le formulaire d'erreur (titre court, état À revoir / Comprise, miniature du passage capturé qu'on peut retirer, note « pourquoi je me suis trompé », page, bouton « Ajouter au carnet »). Dessous : les erreurs déjà notées sur ce poly (page, miniature, état, corbeille).
9. Deux icônes de fin, chacune avec une pastille de compteur : le livre (n erreurs) ouvre le panneau latéral sur l'onglet « Erreurs » ; le carnet (n notes) l'ouvre sur l'onglet « Notes » : liste des remarques et post-it du poly (page, type, texte), puis « Pièces jointes » avec quatre boutons (Fichier, Photo, Vocal, Lien) qui rangent un TD corrigé, une photo de tableau, un mémo vocal ou une adresse web avec le poly ; le lien demande une adresse, un nom facultatif et un bouton « Accrocher le lien ». Fichier, Photo et Vocal (micro) n'ont pas été testés.
10. Annuler / rétablir.

### 4.3 Persistance
Copie annotée enregistrée à côté de l'original (original intact), exportable en PDF lisible sans l'app. Les types de remarque, les couleurs de post-it et la dernière sélection d'outil sont mémorisés.

## 5. Flashcards

### 5.1 Types de cartes
1. Texte à trous (cloze), numérotation c1, c2…
2. Basique (question / réponse)
3. Inversée (question dans les deux sens)
4. Saisie (réponse tapée, pour les termes exacts)
5. Occlusion d'image (légendes masquées sur un schéma)

Champs : texte, extra (« verso » : explication, source, mnémo), tags, champ de contexte (ajoutable à la demande). Chaque champ a une punaise pour garder son contenu d'une carte à la suivante.
Éditeur de texte riche : gras, italique, souligné, surlignage, couleur du texte, taille/police, exposant, indice, formule (Σ), image, et un bouton de trou { } avec numéro de trou (c1, c2…, − / +).
Syntaxe du texte à trous visible dans le champ : `{{c1::mot}}` ; un trou par numéro et un numéro par carte fabriquée.

### 5.2 Création depuis un poly
- Écran divisé : poly à gauche, carte à droite ; bouton pour changer la disposition.
- Barre du haut : retour, titre, sélecteur de paquet (« Deck »), bouton « + » (nouveau paquet), bouton de gestion des paquets, sélecteur de poly, disposition, aide, raccourcis clavier, thème clair/sombre. À l'arrivée, une fenêtre demande dans quel paquet ranger les cartes (liste avec compteur, « Nouveau paquet », « Quitter l'atelier ») ; sans paquet choisi, un message d'erreur rouge empêche d'ajouter.
- Seconde barre : les cinq types de carte sous forme d'onglets colorés avec leur raccourci, nombre de pages du poly, bascule « Poly | Cartes » (voir les cartes déjà créées), zoom, indication d'usage (au doigt : naviguer ; au stylet ou à la souris : tirer un rectangle pour capturer).
- Bouton « Ajouter » pour créer la carte ; le champ texte affiche en filigrane un exemple à deux trous (à remplacer par un exemple original dans la version libre).
- Recadrage d'une zone du poly pour en faire l'image de la carte ou le fond d'une occlusion ; collage d'images possible (non éprouvé).
- Flux de création observé : choisir le type (onglet ou Alt+1 à 5), saisir ou sélectionner du texte dans le poly, puis « Ajouter » (ou Ctrl+Entrée) ; un compteur de cartes créées s'affiche, le paquet cible reste choisi. Cloze : on sélectionne un mot, Ctrl+Maj+C l'enveloppe dans `{{c1::…}}`, et une carte est fabriquée par numéro de trou.
- Basique, Saisie, Inversée : mêmes champs (recto, verso, extra, étiquettes, contexte ajoutable) ; l'éditeur de texte riche est partagé.
- Occlusion : on choisit (ou recadre) une image, puis on dessine des rectangles de masque. Trois modes : « tout caché » (une seule carte masque toutes les zones à la fois), « un seul caché » (une carte par zone, les autres restent visibles) et « groupement » (les zones d'un même groupe forment une carte). Des compteurs indiquent zones, groupes et nombre de cartes à fabriquer ; le bouton devient « Ajouter n carte(s) ». À la révision, l'image s'affiche avec les zones pleines et, à la réponse, elles se réduisent à un contour ; zoom − / % / + sur l'image.
- Pastille « ✎ n » près du zoom : affiche ou masque dans le studio les annotations du poly (n = leur nombre), pour créer des cartes à partir de ses propres surlignages.
- Raccourcis par défaut observés (modifiables dans les réglages) :
  - Type de carte : Alt+1 à Alt+5 (Cloze, Basique, Inversée, Saisie, Occlusion)
  - Enregistrer la carte : Ctrl+Entrée
  - Créer un trou sur la sélection : Ctrl+Maj+C ; appuyé deux fois de suite, il passe au numéro de trou suivant
  - Numéro de trou suivant : Ctrl+Maj+B ; précédent : Ctrl+Maj+V
  - Annuler la dernière note ou le dernier masque : Ctrl+Z

### 5.3 Paquets
- Écran d'accueil des flashcards : nombre de decks et de cartes ; quatre compteurs (révisions + nouvelles du jour avec durée estimée, nouvelles en attente, cartes au total, cartes difficiles) dont les deux premiers sont cliquables ; bouton principal « Réviser » ; recherche de deck, menu « ⋯ », crayon (studio de création) et bouton d'import ; bloc « S'entraîner » (plusieurs paquets à la suite, pour réviser ou se noter sur 20) ; liste « Mes decks » avec bascule « Par matière / À plat ». Barre latérale : « Tous les paquets » et « À réviser aujourd'hui » (compteur).
- Menu général « ⋯ » : nouveau deck, exporter toute la progression (vers un autre appareil), réglages d'étude, raccourcis clavier.
- Filtres latéraux : tous les paquets, à réviser aujourd'hui.
- En vue « par matière » : une section repliable par matière (couleur, nombre de cartes), y compris vide (message « glissez-en un ici pour le ranger ») ; « Sans matière » pour le reste ; déplaçables par glisser-déposer depuis la poignée du deck.
- Création d'un deck : un champ de nom en ligne (exemples : Anatomie, Foie) puis Créer.
- Carte de deck : poignée, nom, trois compteurs (dues, nouvelles, cartes), bouton Réviser, menu « ⋯ » :
  - Renommer, changer de matière, badge du paquet, associer un poly
  - Voir les cartes : vue plein cadre « nom du deck · n notes · n cartes » (fermer en haut à droite), bouton « Nouvelle carte », recherche dans le deck, liste de notes à gauche (case de sélection, type, aperçu, nombre de cartes), détail à droite (type, n carte(s), « Mettre en pause », « Modifier », corbeille) avec l'aperçu question/réponse (trous colorés pour un cloze, image et zone surlignée pour une occlusion)
  - Réglages d'étude : le deck suit par défaut les réglages généraux (affichés en lecture seule) ; une case « ce deck a ses propres réglages » active les mêmes options que le général : une seule carte par notion et par jour, ordre de passage (mélangées ou dans l'ordre du cours), nouvelles par jour (20) et révisions par jour (200) chacune avec « sans plafond », exigence de mémorisation (curseur 70–97 %, 90 % par défaut, avec les jalons J+4, J+18, J+62, J+187 qui bougent en direct), cartes maudites (nombre d'oublis, action), rattrapage de retard propre au deck (« Tout reporter » ou « Étaler le retard »)
  - Date butoir (« à savoir pour le… ») : les cartes qui reviendraient après cette date sont ramenées avant et étalées sur les jours restants ; la mémorisation n'est pas touchée, seules les dates bougent
  - Partager le deck (images comprises), exporter la progression
  - Sélectionner plusieurs, supprimer
- Écran « S'entraîner » (depuis l'accueil) : deux onglets, « Nouvelle séance » et « Historique ». Nouvelle séance : liste de cases à cocher (matière → paquets, avec nombre de cartes, « Tout sélectionner / Tout désélectionner ») et panneau de réglages : Mode (Réviser : chaque carte est reprogrammée ; Se tester : je savais ou pas, une note sur 20 à la fin, rien n'est reprogrammé), Nombre de cartes tirées au hasard dans les paquets cochés (20, 50, 100, Tout ou un nombre libre), Ordre (mélangé ou ordre du cours). Le bouton principal en haut à droite (« Réviser » ou « Se tester » selon le mode) reste grisé tant que rien n'est coché.
- Séance « Se tester » : en haut « n / N » et le nombre de justes ; sous la carte, « Afficher la réponse » puis deux boutons « Je ne savais pas (F) » et « Je savais (V) ». Écran de résultat : note sur 20 avec une appréciation en mots, « n juste sur N · x % », rappel que rien n'a été reprogrammé, boutons « Refaire un tirage » et « Voir l'historique ». Historique : une ligne par séance (note sur 20, n / N, date, durée, paquets) avec une corbeille.

### 5.4 Import / export
- Import Anki (.apkg) avec historique de révision.
- Import CSV/TSV (ex. copie depuis un autre outil de cartes).
- Export d'un paquet en fichier unique, images incluses.

### 5.5 Révision
- Algorithme : FSRS (bibliothèque open source open-spaced-repetition).
- Avant la séance d'un paquet, une petite fenêtre demande l'ordre : mélangées, dans l'ordre du cours (comme elles ont été écrites) ou « comme d'habitude » (réglage général).
- Écran de révision : barre du haut (quitter, position « n / N », boutons annuler, ajouter une note, enterrer, mettre de côté, supprimer en rouge, thème clair/sombre), pastilles de files en dessous (nouvelles n/N, puis une file d'apprentissage), carte avec son type et l'étiquette « première fois / vue n fois · carte n », bouton « Afficher la réponse ».
- Quatre réponses, libellés observés : Encore, Difficile, Bien, Facile (touches 1 à 4) ; le délai avant le prochain passage est affiché sous chaque bouton (exemple d'une carte neuve : 1 min, 5 min, 10 min, 19 j ; à son second passage dans la séance : 4 min, 9 min, 3 j, 5 j). Une carte ratée ou en apprentissage revient pendant la séance.
- Écran de fin « Terminé » : nombre de cartes révisées, date de la prochaine révision et nombre de cartes programmées ; boutons « Réviser à nouveau », « Annuler la dernière » et « Retour aux decks ».
- Actions de séance : révéler/cacher la réponse, révéler le contexte, annuler la dernière note, mettre la carte de côté, enterrer la notion (toutes ses cartes sœurs reviennent le lendemain), supprimer définitivement la carte (avec confirmation).
- Raccourcis par défaut observés (tous modifiables, avec un bouton « rétablir » par ligne) :
  - Révéler/cacher : Entrée ou Espace ; contexte : H
  - Notes : 1 (Encore), 2 (Difficile), 3 (Bien), 4 (Facile)
  - Annuler : Ctrl+Z ; mettre de côté : S ; enterrer la notion : touche moins ; supprimer : Ctrl+Suppr
- Mécanismes de séance, réglables (voir section 12) :
  - Une seule carte par notion et par jour : un texte à six trous fabrique six cartes, mais une seule est servie par jour, les autres reviennent le lendemain (évite de répondre six fois à la même chose)
  - Compteur de passages sur la carte : combien de fois l'algorithme l'a vue et combien de fois elle a été oubliée (réglage propre à l'appareil)
  - Ordre de passage : mélangé par défaut (autres ordres possibles) ; l'ordre seul change, jamais le choix ni le nombre de cartes, qui relèvent de l'ordonnanceur
  - Cartes « maudites » (leeches) : après N oublis (8 par défaut) la carte est jugée à réécrire plutôt qu'à répéter ; action au choix (mise de côté par défaut)
  - Rattrapage de retard sur tous les paquets : décaler toutes les échéances de N jours (3 par défaut) ou étaler le retard ; ne touche que les dates, les cartes jamais vues restent intactes
- Panneau de session (à droite) : bloc Session (révisées, restantes, minutes, secondes par carte), bloc Carte (type, modèle, passages, oublis), bloc Prochaine échéance (les quatre délais) et rappel des raccourcis (révéler Entrée, noter 1 à 4, contexte H, enterrer touche moins, supprimer Ctrl+Retour arrière).
- Limites quotidiennes : 20 nouvelles cartes et 200 révisions par jour par défaut, avec case « sans plafond ». Règle : le plafond le plus strict l'emporte ; si un examen est daté, la matière garde son propre rythme. Les modes « bachotage » et « mélange partiel » ignorent le plafond de révisions (demandes explicites).
- Objectif de rétention (« exigence de mémorisation ») : 90 % par défaut. Plus il monte, plus les intervalles se resserrent (plus de travail, moins d'oublis).
- Estimation affichée en réglages : charge quotidienne attendue (≈ 100 révisions par jour une fois le rythme installé pour 20 nouvelles par jour) comparée au plafond.
- Onglets de session : nouvelles / en apprentissage / à revoir.

## 6. QCM

### 6.1 Épreuves
Organisation de l'écran QCM : trois onglets (Passer, Historique, Édition) et, dessous, deux sous-onglets (Épreuves / Annales, ou Épreuves / Entraînements dans l'historique). Une épreuve est une série écrite (annale, colle, les 40 questions d'un poly) qui garde son ordre, son barème et ses explications et se repasse à l'identique pour se comparer. Elle s'écrit dans l'appli ou arrive d'un camarade sous forme de fichier.

- Types de questions :
  - QCM : propositions à cocher ; une seule bonne réponse = QRU, plusieurs = QRM (la bascule est automatique dès qu'on coche une deuxième réponse) ; QRP (propositions avec réponses attendues)
  - QROC : réponse courte écrite ; l'étudiant écrit en quelques mots puis se compare. Champs : énoncé, images, nature de la réponse attendue (un texte par défaut), longueur maximale (aucune ou n lignes), réponse modèle montrée à la correction, éléments attendus (chacun rapporte ses points ; « ; » sépare ce qu'il faut tous trouver, « | » des synonymes acceptés). Sans élément attendu, l'étudiant s'auto-évalue (juste, partiel, faux) face à la réponse modèle
  - TCS (test de concordance de script) : une hypothèse (« si vous pensez à… »), une échelle (par exemple diagnostic infirmé ↔ confirmé), une information nouvelle (« …et que vous trouvez… »), puis les réponses d'un panel d'experts sur cinq niveaux (de −2 fortement infirmée à +2) : l'auteur clique le niveau retenu par un expert ou saisit combien d'experts ont choisi chaque niveau ; le niveau le plus choisi vaut 1 point, les autres au prorata
  - QZP (zone à pointer) : cliquer au bon endroit d'une image (scanner, schéma, ECG…) ; l'auteur colle ou choisit une image et dessine les zones-réponses
- Cas (suivis de leurs questions), via un champ « Dans un cas clinique » (« Non, question isolée » par défaut) et un « Genre » :
  - Dossier progressif : un cas qui évolue, chaque question apporte la suite de l'histoire ; jamais coupé ni mélangé, et une question ne se rouvre plus une fois la suite vue
  - KFP : un cas court, les décisions clés ; un champ « contexte, commun à toutes les questions du cas » précède les questions
  - Le menu « Genre » d'un cas liste Dossier progressif, KFP et Lecture critique d'article ; changer le genre renomme le cas
  - LCA : un article, plusieurs questions ; l'article se joint en PDF (sélecteur de fichier) ou se colle en texte, et reste consultable pendant toutes les questions. Au passage, un bandeau repliable (« Lecture critique d'article · question n sur N », lien « Replier / Afficher l'article ») précède l'énoncé ; il se retrouve dans la copie
  - Contexte commun à toutes les questions du cas ; bouton « Ajouter une question au dossier »
- Champs communs : énoncé, images (coller avec Ctrl+V n'importe où ou déposer), explication lue à la correction (« pourquoi c'est celle-là, et le piège des autres »).
- Éditeur (ouvert par « + Série » puis un nom, ou en modifiant une épreuve) :
  - Barre du haut : retour aux séries, titre, compteur « n prête(s) · n à finir », matière (« Sans matière » par défaut), champ Items (lien avec les items des EDN), Aperçu, Mélanger, dupliquer, Composer (désactivé tant qu'aucune question n'est prête), fermer
  - Colonne gauche : liste des questions numérotées avec état (« à finir » ou coche verte) et regroupement par dossier ; boutons d'ajout d'une question (QCM, QROC, TCS, QZP) et d'un cas (dossier progressif, KFP, LCA)
  - Centre : formulaire de la question (onglets de type en haut, dupliquer, monter, descendre, supprimer)
  - Droite : aperçu en direct « tel que ce sera posé », avec les messages de validation (au moins deux propositions, au moins une bonne réponse, un énoncé, une image pour QZP)
- Carte d'épreuve : titre, matière, « n question(s) · à finir · passée n fois », dernière note, barre de progression, bouton Composer (Éditer en mode Édition) ; menu « ⋯ » : éditer, changer de matière, mettre dans les annales, rattacher à un poly, dupliquer, partager, sélectionner plusieurs, supprimer.
- Mode sélection multiple : barre du bas (tout sélectionner, déplacer, vers les annales, supprimer, terminé, S'entraîner) pour passer plusieurs épreuves ensemble.
- Une épreuve peut aussi être placée dans Annales via son menu ou, comme le dit le guide, par un titre contenant « annale ».
- Filtre latéral : toutes les épreuves, jamais passées, et par matière. Recherche d'une épreuve. Bouton « Prochaine épreuve » et bouton « S'entraîner » en haut à droite.
- Partage : « Partager l'épreuve » montre le fichier de l'épreuve (`<titre>.qcm.json`) dans le gestionnaire de fichiers du système, prêt à être envoyé ; ouverture d'une épreuve reçue depuis un fichier (réception non testée). Le fichier embarque les images.

### 6.2 Passage
- Fenêtre de réglages avant de commencer (valeurs par défaut, valables pour toutes les épreuves et entraînements jusqu'à changement) :
  - Une partie seulement : bascule (désactivée par défaut) pour ne passer qu'une partie des questions, sinon toutes, dans l'ordre
  - Correction : à chaque question, ou à la fin (par défaut, comme le jour de l'épreuve) ; en correction immédiate, la question validée affiche un badge « Juste / Fausse », colore les propositions et propose « Question suivante » (« Voir les résultats » à la dernière)
  - Retour en arrière : interdit par défaut (une question validée ne se rouvre pas, la note compte) ou permis
  - Minuteur : désactivé par défaut (pas de limite de temps)
  - Notation : EDN (par défaut en médecine) ou Points
  - Règles EDN affichées en dépliant l'aide : QRU tout ou rien ; QRM 1 point sans discordance, 0,5 pour une, 0,2 pour deux, 0 au-delà ; QRP bonnes réponses cochées sur réponses attendues ; annulation (une proposition indispensable oubliée ou une proposition inacceptable cochée donne 0). Ces règles du barème national sont publiques.
  - Mélanger les propositions : activé par défaut, nouvel ordre à chaque passage
- Écran de passage (plein écran, sans barre de fenêtre) :
  - En haut : quitter, position « 1 / N », zoom (− / + ; 120 % par défaut), bascule clair/sombre
  - Question : badge du type, rappel de la notation, bouton Doute (drapeau), énoncé, propositions, boutons Passer et Valider
  - Panneau droit : avancement (une pastille numérotée par question, avec légende traitée / passée), compteurs « Traitées n / N », bouton rouge Rendre la copie
  - À la dernière question validée, la copie s'affiche directement
- Mode S'entraîner : le bouton de l'en-tête passe l'écran en sélection multiple (case à cocher sur chaque épreuve, barre du bas « tout sélectionner, déplacer, vers les annales, supprimer, terminé, S'entraîner ») pour tirer des questions dans plusieurs épreuves ou annales. L'en-tête garde le bouton « Carnet » (section 9), qui s'affiche alors avec son libellé.
- « Prochaine épreuve » ouvre directement la fenêtre de réglages de l'épreuve suivante à passer (titre, nombre de questions, boutons Annuler / Commencer).

### 6.3 Copie
- Note en points (exemple 2,00 / 2,00) et barre de progression, puis tuiles : justes, partielles, fausses, passées, note sur 20, durée. Mention « épreuve écrite à la main » pour une épreuve rédigée par l'utilisateur.
- Onglets Toutes / À reprendre ; pastilles colorées par question en bas de la colonne gauche.
- Détail par question : numéro, verdict (Juste, Partielle, Fausse, Passée), type, points gagnés, réponses cochées en couleur, propositions oubliées, explication.
- Actions : Refaire mes ratées, Repasser l'épreuve, Une autre épreuve, envoyer les questions manquées au carnet d'erreurs.

### 6.4 Historique
- Deux sous-onglets : Épreuves et Entraînements ; recherche d'une copie.
- Bloc « Mes copies » : une ligne par épreuve avec « n copie(s) · meilleure note », une perle par copie (le chiffre est la note sur 20, sous la perle la date), un cerclage pour la part d'un entraînement, un écart proportionnel au temps entre deux passages, et la dernière note en grand à droite.
- Bloc « Où je chute » : résultats par matière ou par chapitre, du plus bas au plus haut (pourcentage et rapport juste/total) ; « Non rangé » pour les épreuves sans matière.

## 7. Planning

- Deux modes dans la barre latérale : « Planning » (agenda) et « Mes J » (méthode des J, section 8).
- Vues : jour, semaine (par défaut), mois, année, avec raccourcis clavier J / S / M / A (affichés dans le menu de la vue) ; navigation « Aujourd'hui » et flèches précédent/suivant ; titre de la période ; recherche en haut à droite ; pastille « Examen d'<matière> · J-n » (compte à rebours) à l'extrémité. La vue semaine est une grille horaire (à partir de 05:00 dans l'écran vu) avec une ligne rouge pour l'heure courante et la mention du fuseau. En mode Planning, la barre latérale liste les types à cocher (Examen, CM, ED, TP, lien « Gérer ») et une case « Méthode des J » ; la barre du haut a le bouton de panneau des types (pastille bleue), le bouton d'import .ics et « + ».
- Import d'un emploi du temps au format .ics (bouton dédié). Remarque : sur Windows, ce bouton a ouvert l'explorateur de fichiers puis l'application a redémarré ; à implémenter proprement dans la version libre (sélecteur de fichier natif, aucun redémarrage).
- Types d'événements :
  - Types par défaut : Examen (verrouillé, intégré, alimente le compte à rebours), CM, ED, TP. Dans le panneau, un intitulé qui commence par CM, ED, TD ou TP reçoit automatiquement ce type, à l'import comme à la saisie
  - Couche « Méthode des J » (vos révisions) affichable ou non, désactivée par défaut dans l'agenda
  - Panneau « Types d'événements » : tout afficher / tout masquer, une bascule par type, « + Nouveau type » (nom libre, palette d'une douzaine de couleurs plus une couleur personnalisée), bouton « Typer les événements sans type » pour appliquer la règle d'auto-typage à l'existant
  - Cases de filtre par type dans la barre latérale, lien « Gérer »
- Création d'un événement (bouton « + ») : titre, type (liste avec « Sans type » par défaut et « Nouveau type »), date, horaire ou journée entière, début, fin, durée rapide (15 min, 30 min, 1 h), répétition (« Ne pas répéter » ou « Chaque semaine » avec date de fin « Jusqu'au »), lieu (facultatif), notes (facultatif).
- Création/déplacement d'événements à la main.
- Disponibilités et rubrique « À placer » : décrits dans le guide, mais introuvables dans l'interface, même après avoir suivi un cours en Mes J (aucune entrée correspondante dans la barre latérale ni dans le panneau « Types d'événements ») ; à tenir pour une fonction à confirmer ou d'une autre version.
- Apple : affichage du calendrier système et inscription des séances.

## 8. Méthode des J

- J0 = jour d'apprentissage ; rappels à J1, J3, J7, J15, J30.
- Onglet « Mes J » (dans Planning) : liste latérale « Cours suivis » (vide au départ), vue calendrier des J (jour / semaine / mois / année), état vide avec bouton « + Ajouter des J ».
- Suivre un cours : panneau « Ajouter des J » avec trois modes :
  - Item (EDN) : recherche par numéro ou par mot, filtre par spécialité, liste des items, « + Item hors liste » pour un sujet libre
  - Poly : recherche parmi les polys importés
  - Chapitre : recherche parmi les chapitres
  - Champ « Appris » : Pas encore (par défaut, J0 à faire, la suite partira du jour où l'on coche), Aujourd'hui, Hier, ou un autre jour
  - Boutons Annuler / Suivre. « Revoir toute la matière » suit tous les cours d'une matière.
- Séquences prédéfinies observées :
  - Classique : J1 J3 J7 J15 J30
  - Serrée : J1 J2 J4 J7 J14 J21 J30
  - Longue : J1 J3 J7 J15 J30 J60 J90
  - Légère : J1 J7 J30
  - Espacée : calée sur l'algorithme des cartes, environ J4 J18 J62 J187 puis intervalles de plus en plus longs, pour un objectif de rétention de 90 % ; c'est le rythme affiché par défaut côté cartes
  - Personnalisée : un champ texte prérempli avec la séquence en cours (écriture observée : « J0 J1 J3 J7 J15 J30 », des J séparés par des espaces, J0 compris) et un bouton « Appliquer »
- Deux réglages distincts au départ : la séquence des cours (Classique par défaut, choisie dans le panneau « Séquence et options » du mode Mes J) et le rythme des cartes (Espacée, issu de l'objectif de rétention, dans Réglages › Étude). Quand ils diffèrent, le panneau Mes J affiche un bandeau : « vos flashcards ont un autre rythme : J4 J18 J62 J187 (90 %) » avec deux boutons d'harmonisation : « Cartes au rythme des cours » (la rétention monte alors à 97 %) et « Cours au rythme des cartes ». Côté Réglages › Étude, le texte précise que les cours suivent encore la séquence classique tant qu'on ne choisit pas un rythme commun.
- Réglages › Étude : curseur d'objectif de rétention (de 70 % « chaîne large » à 97 % « chaîne serrée ») qui montre en direct les jalons (délai entre chaque J, J+4, J+18, J+62, J+187…) ; la mention « si vous la retrouvez à chaque fois » rappelle qu'une carte ratée retombe beaucoup plus tôt.
- Panneau « Séquence et options » (icône de réglages en haut du mode Mes J) :
  - Séquence de vos cours (six choix ci-dessus)
  - Pause (vacances) : début de la pause (aujourd'hui par défaut), reprise des J (une semaine plus tard par défaut), bouton « Mettre en pause » ; les J qui tombent pendant la pause partent au jour de la reprise et la suite s'enchaîne
  - Affichage : case « Aussi dans le planning officiel » (désactivée par défaut) pour voir les J à côté des cours et examens
- Après « Suivre », le panneau « Séquence et options » s'ouvre tout seul. Un aperçu des dates (J0 aujourd'hui, J1, J3, J7…) est montré avant de valider. J0 est apparu comme fait aussitôt (« Appris : Aujourd'hui » choisi et cartes du cours déjà révisées le même jour : les deux causes n'ont pas été séparées, à vérifier). Le calendrier affiche un bloc par J (« J0 », « J1 »… avec le poly et la matière) ; en vue mois, un J fait est barré.
- Barre latérale « Cours suivis » : groupes par matière (compteur), bouton « Revoir toute la matière », et pour chaque poly son prochain J (« J1 · 1 nov »).
- Panneau « Par matière » : une séquence propre à une matière (liste : « Comme les autres » ou une séquence précise).
- Fenêtre d'un J (clic sur un bloc) : nom du poly et chemin, pastilles J0 J1 J3 J7 J15 J30 (faits en couleur, J courant cerclé), ligne « n cartes du cours revues aujourd'hui », boutons « Ouvrir le poly » et « Réviser ses n cartes », bouton coché « J0 fait aujourd'hui » suivi du retour **Difficile / Correct / Facile** (Difficile rapproche le J suivant, l'écart étant divisé, et une petite icône colorée s'affiche sur le bloc ; Facile l'éloigne, d'après le guide, non testé), « + Ajouter une note », « Décocher J0 », « Ensuite J1, date » avec « Faire J1 aujourd'hui ». Section « Réglages » : rappel de la date d'examen (un J qui tomberait après l'examen est avancé), séquence propre à ce poly, « + Séance en plus », « Décocher », « Ne plus suivre » (en rouge).
- Les J se déplacent comme n'importe quel événement.
- Externat : onglet Items pour suivre les étapes de chaque item des EDN (voir section 8 bis).

## 8 bis. Items des EDN (module externat)

Visible seulement pour la filière Médecine, année « Externat (EDN) » ; la méthode des J s'applique alors par item, et les QCM peuvent suivre le barème des EDN.

- Données : la liste des 367 items du référentiel officiel des EDN. Elle est publique : à récupérer depuis la source officielle (ministère / collège), pas en copiant la base de l'appli d'origine. Chaque item a un numéro, un titre, une ou plusieurs spécialités (« aussi en… » pour les items partagés).
- Progression globale : « n faits sur 367 », barre « fait dans toutes ses spécialités » / « entamé », compteurs cette semaine et ce mois-ci.
- Étapes d'un item (cases à cliquer pour compter un passage, à la date choisie par l'utilisateur) :
  - Étapes par défaut : Rang A, Rang B, Ancrages, QI, DP, Annales, Fiche, Cartes
  - Étape facultative proposée mais décochée : Tours
  - Étapes personnalisées ajoutables (exemples donnés : Mindmap, Sous-colle)
  - Modèles prédéfinis d'étapes (fondés sur des ressources de préparation courantes) et mode « Tout »
  - Réordonner les étapes, en cacher une sans effacer ses passages (ils reviennent si on la recoche)
- Couleur du compteur par étape : 1 fois / 2 fois / 3 fois ou plus.
- Trois vues :
  1. Statistiques : items travaillés en 14 jours, moyenne par semaine (4 dernières), meilleur jour, passages d'étapes en 14 jours ; progression par étape (n sur 367 items, rien en 14 jours) ; historique des 14 derniers jours
  2. Par spécialité : liste des spécialités avec compteur (ex. 0/4), détail des items à droite avec filtres Tous / À faire / Faits
  3. Tous les items : recherche par numéro ou par mot, filtres Tous / À faire / Entamés / Faits, ligne par item (case, numéro coloré, titre, spécialités, pastilles d'étapes, volet déplié)
- Onglets personnalisés (« + Onglet ») pour regrouper des items à sa façon.

## 9. Carnet d'erreurs

- Sources : passages d'un poly (atelier), questions manquées d'un QCM, saisie libre depuis « Mon travail » d'un thème (TD, colle, cours à la main).
- Chaque erreur garde : titre court, note libre (pourquoi je me suis trompé, ce qu'il faut retenir), état (À revoir / Comprise), origine (poly + date, QCM, saisie libre), rattachement matière › thème, et pour un poly document, page, extrait.
- Écran « Carnet d'erreurs » (bouton « Carnet » dans l'en-tête des QCM, depuis un cours, et rubrique du tableau de bord) : compteur « n à revoir », filtres À revoir / Comprises et Tout / Polys / QCM, liste regroupée par matière (couleur, nombre) puis par thème (nombre), chaque carte d'erreur montrant titre, note, origine et date.
- Une erreur sans poly peut être rattachée plus tard à un poly du thème (bouton « Rattacher à ce poly »).

## 10. Tableau de bord

1. Date du jour, accès aux écrans principaux
2. Recherche + compte à rebours avant le prochain examen
3. Cartes à réviser (révisions + nouvelles, durée estimée), nouvelles en attente, cartes difficiles
4. J à faire aujourd'hui
5. Effort : cartes révisées par jour (14/30/60 j), série de jours consécutifs, moyenne, pic
6. Rétention : proportion de cartes retrouvées sur 7 et 30 jours
7. Stock : cartes neuves / en apprentissage / jeunes / mûres, avec pourcentage de cartes mûres affiché en tête. Seuils : une carte est « jeune » dès qu'elle a passé son premier jour d'apprentissage (le lendemain), « mûre » à partir d'un intervalle de 21 jours. Message d'état vide tant qu'aucune carte n'existe.
8. Où je chute : résultats QCM, les cinq chapitres les plus bas (message d'invite tant qu'aucune copie n'a été rendue)
9. Carnet d'erreurs récentes

Deux onglets en haut de l'écran : « Tableau de bord » et « Examen » (compte à rebours et préparation de l'examen daté). Barre de recherche de polys en haut à droite. Bloc « Aujourd'hui » : nombre de cartes à réviser, nouvelles en attente, cartes difficiles, état « rien à faire » quand tout est fait. Bloc « Mon effort » : courbe des cartes révisées, nombre de cartes, jours travaillés, moyenne par séance, pic. Bloc rétention : deux courbes 7 j et 30 j, qui n'apparaissent qu'aux premiers rappels (la rétention ne compte que les cartes déjà apprises qui reviennent).

### 10.0 Onglet « Examen » (observé)
- Vide : explication (réunir les matières d'un examen : leurs polys à cocher une fois traités, leurs notes de QCM et ce qu'il reste à faire) et bouton « + Nouvel examen ».
- Fenêtre « Nouvel examen » : nom, date (champ date natif à saisir segment par segment ; l'intitulé du jour de la semaine s'affiche), compteur « n matière(s) », liste des matières par année · semestre à cocher ; une matière sans date d'examen reçoit celle-ci (elle apparaît au planning et règle les J). Boutons Annuler / Créer l'examen.
- Une fois créé : pastille en haut à droite de tout le tableau de bord « Examen d'<matière> · J-n » (compte à rebours global) ; onglets d'examens (nom + date) et « + Nouvel examen » ; carte de l'examen (nom, date, gros « J-n », crayon pour modifier, icône d'archivage, barre « n % préparé », « n matière(s) · n poly(s) à traiter ») ; bloc « Moyennes par matière » (échelle 0 – 20, repères moyenne et dernière note, « Aucune copie » tant qu'il n'y en a pas) ; une section dépliable par matière (couleur, « n % préparé », « n % polys » avec ratio, annales, copies) contenant : « Polys de l'examen » (tous les polys de la matière comptent par défaut, bouton « Choisir les polys », lien « Ouvrir dans Cours », chaque poly avec une case ronde à cocher une fois traité, regroupés par thème avec ratio « 0/1 »), « Annales » de la matière, et « À faire » (liste de tâches libres, « + Ajouter une tâche… »).

### 10.1 Premier lancement (deux écrans)

1. « Quelles études faites-vous ? » : Médecine, Autre filière de santé, Droit, Sciences/ingénierie, Lettres/langues/sciences humaines, Lycée, Autre. Pour Médecine, une seconde question demande l'année : PASS, L.AS, 2e année (DFGSM2), 3e année (DFGSM3), Externat (EDN), Internat. Boutons « Plus tard » et « Valider ». Un texte explique ce que l'année active (pour l'externat : l'onglet Items avec les 367 items, la méthode des J par item, les QCM au barème des EDN). Tout est modifiable plus tard dans les réglages.
2. « Qu'est-ce que vous venez faire ici ? » : profils prédéfinis (Tout, Flashcards uniquement, QCM uniquement, Cours et flashcards) et cases par module (Cours, Flashcards, QCM, Planning, Méthode des J). Ce qui est décoché disparaît de la barre latérale sans rien effacer ; tout se rallume dans les réglages.
Barre latérale de l'application complète : Tableau de bord, Planning, Cours, Flashcards, QCM, Items (externat uniquement), Réglages en bas.

## 11. Recherche globale

- Raccourci Cmd/Ctrl+K depuis tout écran : une petite palette centrée « Chercher un poly… » (↑↓ pour naviguer, Entrée pour ouvrir, Échap pour fermer ; mention rappelant que la recherche est locale et fonctionne hors ligne). Un résultat affiche le titre, le chemin (année › semestre › matière › thème) et une étiquette de nature (« Document »). Dans la version testée, seuls les titres de polys ont répondu (un mot présent dans le texte du poly mais pas dans son titre n'a rien donné).
- Cible pour la version libre : matières, thèmes, polys, paquets, cartes (et pourquoi pas le texte des polys). Fonctionne hors connexion.

## 12. Réglages

Fenêtre modale à cinq onglets : Général, Étude, Dossier, Raccourcis, Communauté.

- **Général** : activation de chaque module (Cours, Flashcards, QCM, Planning, Méthode des J) ; filière et année d'études (listes déroulantes) ; apparence automatique / claire / sombre ; langue (automatique : français, ou anglais hors d'un pays francophone) ; « Autre fenêtre » pour ouvrir l'écran courant à côté (par exemple le cours et le studio de création en parallèle).
- **Étude** : séance (une seule carte par notion et par jour, compteur de passages, ordre de passage), plafonds quotidiens, objectif de rétention, rythme commun cartes/cours (séquences de J, curseur de rétention, estimation de la charge), cartes maudites (nombre d'oublis, action), rattrapage de retard (reporter tout, étaler), bouton « revenir aux valeurs par défaut ». Détails en sections 5.5 et 8.
- **Dossier** : emplacement, synchroniser, renommer, déplacer, changer de dossier (section 2).
- **Raccourcis** : cliquer sur une combinaison puis appuyer sur les touches voulues ; une alternative par action ; bouton de remise à zéro par ligne. Deux groupes seulement : Révision et Studio de création (sections 5.2 et 5.5). Compléments observés dans le studio : rétablir ce qu'on vient d'annuler (Ctrl+Y ou Ctrl+Maj+Z) ; occlusion : groupe de masques suivant (G) et précédent (Maj+G) ; lien « Tout réinitialiser » en bas.
- **Communauté** : un seul lien d'invitation vers un groupe de discussion externe (actualités, entraide, idées). Pour la version libre, remplacer par un lien vers le dépôt (discussions / issues).

## 13. Direction visuelle « épurée »

- Une seule couleur d'accent ; la couleur par matière reste, mais en petite touche (pastille, trait), pas en fond de carte.
- Beaucoup d'espace blanc, une hiérarchie typographique simple (2 tailles de titre, 1 de texte).
- Cartes sans bordures lourdes ; séparateurs fins.
- Tableau de bord : 4 blocs principaux au premier plan (à réviser, J du jour, progression, erreurs), le reste en détails dépliables.
- Atelier et révision en plein écran, sans barre inutile ; outils affichés au besoin.
- Mode sombre dès le début. Cibles tactiles ≥ 44 pt.
- Écrans propres sur iPhone (navigation par onglets) comme sur iPad/Mac (barre latérale).

## 14. Hors périmètre

- Aucune reprise de code, textes, icônes, logo, nom ou captures de l'appli d'origine.
- Pas de contournement de protection ni de rétro-ingénierie du binaire.

## 15. Ordre de développement proposé

1. Dossier, base SQLite, import de PDF, hiérarchie des cours
2. Flashcards : types basique et cloze, révision avec FSRS, limites quotidiennes
3. Import/export Anki et CSV, autres types (inversée, saisie, occlusion)
4. QCM : édition, passage, copie, historique
5. Planning (.ics, disponibilités), méthode des J (séquences prédéfinies et Espacée) et module Items EDN
6. Carnet d'erreurs, tableau de bord (dont l'onglet Examen), recherche globale
7. Atelier d'annotation PDF (partie la plus lourde)
8. iCloud, OCR, multiplateforme

## 16. Choix techniques à trancher

- Apple uniquement : SwiftUI + SQLite (GRDB) + PDFKit/PencilKit.
- Multiplateforme : Flutter ou Tauri ; l'annotation PDF est plus complexe dans ce cas.

## 17. Distribution

- Formats observés dans le guide de l'appli d'origine : boutiques d'applications (Store), AppImage, .deb, .rpm. Pour une version libre : releases GitHub avec installeur Windows, paquets Linux (AppImage, .deb, .rpm) et, côté Apple, TestFlight ou build à compiler soi-même (le programme développeur payant n'est nécessaire que pour l'App Store).
- Données de l'utilisateur toujours hors de l'installation : désinstaller ne supprime pas le dossier de travail.

## 18. Reste à observer

Observé dans cette version : réglages complets, Planning (types, création d'événement, vues), Mes J (séquences, personnalisée, pause, ajout, suivi d'un poly, fenêtre d'un J avec retour Difficile/Facile), Items, QCM (composition, passage, correction immédiate, copie, historique, mode sélection, KFP et LCA à l'édition, LCA au passage, QROC, partage), Flashcards (accueil, menu de deck, voir les cartes, réglages d'un paquet, studio de création : cloze, basique, occlusion, révision FSRS jusqu'à l'écran de fin, S'entraîner noté sur 20 et historique), Cours (création année/matière/thème, écran d'un thème, « Mon travail »), atelier d'annotation (barre du haut, tous les outils de la barre du bas, panneaux Notes et Erreurs, comparaison, bascules œil et barre), carnet d'erreurs, onglet Examen, recherche globale, synchronisation du dossier. Non observé :

- Flashcards : l'éditeur Inversée en détail, le recadrage d'une zone du poly, l'import Anki / CSV (bouton d'import non actionné : sélecteur de fichier), le bouton « Cartes » du studio
- Atelier : le bouton d'export du haut, le rendu réel du stylo, des formes et du ruban sur la page, la portée de la pastille de couleur, le panneau de six miniatures de dispositions apparu avec elle, les boutons Fichier / Photo / Vocal des pièces jointes
- Cours : sélecteur de fichiers de « Importer » (ne s'est pas affiché), import d'un .zip ou d'un dossier, OCR
- Planning : import .ics (le bouton a provoqué l'ouverture de l'explorateur puis un redémarrage de l'appli) ; disponibilités et « À placer » introuvables
- QCM : éditeur des zones d'une QZP (une image est nécessaire, le collage d'image n'a pu être simulé), passage d'un KFP et d'un TCS, réception d'une épreuve partagée, entraînement mené jusqu'au bout, onglet Annales rempli
- Recherche globale : recherche dans les cartes, paquets, matières (seuls les titres de polys ont été éprouvés)

Constats utiles pour la version libre :
- L'aide de l'onglet Dossier parle de « Finder » même sous Windows (texte non adapté à la plateforme) ; il en va de même du tiroir de fichiers d'un thème (« glisser des fichiers depuis le Finder »).
- Après un redémarrage de l'appli, l'onglet Items (réservé à l'externat) a disparu puis réapparu : la persistance du niveau d'études et des modules choisis est à soigner (la tester dès la première version).
- La touche Échap ferme l'atelier : dans la version libre, réserver Échap à la fermeture des menus et popovers.
- Dans « Mon travail », la ligne « Erreurs » peut afficher « Rien de noté » alors que l'en-tête du panneau gauche compte une erreur sans poly : prévoir un affichage cohérent (compteur unique, liste visible).
- « Partager l'épreuve » ouvre une fenêtre du gestionnaire de fichiers du système : prévoir aussi un export dans l'appli (copier le fichier vers un dossier choisi, ou un lien) pour ne pas dépendre du gestionnaire de fichiers.
- À la révision, les jalons (J+4, J+18, J+62, J+187) et les délais sous les boutons dépendent de l'objectif de rétention : prévoir un test unitaire de l'ordonnanceur avec des jeux de valeurs fixes.
- Les barres de la comparaison de deux documents débordent quand la fenêtre est étroite : prévoir un menu de repli.
- La saisie rapide d'un texte contenant des accents ou des accolades est un point de friction pour les tests automatisés ; prévoir des identifiants d'accessibilité sur les champs des éditeurs de cartes et de QCM.
