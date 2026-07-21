# Synchroniser un catalogue Lightroom Classic entre deux PC

[English](README.md) | **Français**

Deux façons de synchroniser en toute sécurité un catalogue Lightroom Classic entre deux ordinateurs via un outil de sync cloud (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...), sans le corrompre. Choisis le dossier qui correspond à ta façon de travailler.

**Windows uniquement.** Les deux scripts sont des fichiers `.bat` Windows qui s'appuient sur des outils spécifiques à Windows (`robocopy`, `attrib`, PowerShell). Il n'existe pas de version macOS ni Linux, même si l'approche sous-jacente (dossier relais, pull non destructif, transport en `.7z`) n'est pas spécifique à Windows en soi et pourrait être portée en scripts shell. Contributions bienvenues.

Ce document couvre tout ce qui s'applique aux **deux** scripts. Le README propre à chaque variante ne couvre que ce qui la différencie : voir [Lequel choisir ?](#lequel-choisir-) pour en choisir une, puis lis aussi son README avant d'installer.

## Sommaire

- [Le problème](#le-problème)
- [Ce que d'autres ont essayé (et pourquoi ça échoue)](#ce-que-dautres-ont-essayé-et-pourquoi-ça-échoue)
- [Pourquoi des archives .7z](#pourquoi-des-archives-7z)
- [Compatibilité avec d'autres outils](#compatibilité-avec-dautres-outils)
- [Prérequis](#prérequis)
- [Lequel choisir ?](#lequel-choisir-)
- [Organisation des dossiers](#organisation-des-dossiers)
- [Épingler un script à la barre des tâches](#épingler-un-script-à-la-barre-des-tâches)
- [Sécurité : ce que les scripts font pour protéger tes données](#sécurité--ce-que-les-scripts-font-pour-protéger-tes-données)
- [Retour d'expérience : un incident réel](#retour-dexpérience--un-incident-réel)
- [Limites et conditions de test](#limites-et-conditions-de-test)
- [Pistes non retenues](#pistes-non-retenues)
- [Licence](#licence)

## Le problème

Depuis Lightroom Classic 11 (fin 2021), le catalogue ne se limite plus au seul fichier `.lrcat`. Plusieurs dossiers de données l'accompagnent, à côté du fichier principal :

| Élément | Contenu |
|---|---|
| `NomCatalogue.lrcat` | Le catalogue (base SQLite) : métadonnées, retouches, mots-clés |
| `NomCatalogue.lrcat-data` | Données IA : Denoise, sélections générées, masques |
| `NomCatalogue Previews.lrdata` | Aperçus (régénérables, mais longs à recalculer) |
| `NomCatalogue Helper.lrdata` | Reconnaissance de visages |
| `NomCatalogue Sync.lrdata` | Données de synchronisation cloud Adobe |

**Symptôme observé** : le fichier `.lrcat` se synchronise normalement via Synology Drive Client, mais les 4 dossiers associés ne se synchronisent jamais, silencieusement, sans message d'erreur.

**Cause identifiée** : Lightroom applique l'attribut Windows **Système (S)** à ces dossiers à chaque ouverture du catalogue. Synology Drive Client refuse par conception de synchroniser tout fichier ou dossier portant cet attribut.

Vérification reproductible :
```
attrib "NomCatalogue.lrcat-data"
```
confirme la présence de l'attribut `S`. Un `attrib -S "NomCatalogue.lrcat-data" /D /S` le retire temporairement, mais Lightroom le réapplique dès la prochaine ouverture du catalogue. Ce n'est donc pas un fix durable.

Ce problème passe souvent inaperçu au début : tant que ces dossiers sont vides ou peu utilisés (pas de retouches IA, pas de reconnaissance de visages), leur absence de synchronisation ne se voit pas. Il devient bloquant dès qu'on utilise réellement Denoise IA, les sélections générées, ou la reconnaissance de visages. Les données qui y sont stockées cessent alors d'être de simples caches et deviennent du travail perdu si elles ne sont jamais transférées vers l'autre machine.

Et au-delà de cet attribut : même si la synchro fonctionnait, laisser un outil de sync lire un catalogue **pendant** que Lightroom y écrit (c'est une base SQLite active) est le scénario classique de corruption. Deux problèmes distincts, donc, que la solution doit traiter ensemble.

## Ce que d'autres ont essayé (et pourquoi ça échoue)

Ce n'est pas un bug Synology isolé : le même mur est documenté sur tous les outils de sync grand public.

- **Adobe** indique explicitement ne pas supporter la synchronisation cloud, sur disque réseau ou sur disque externe pour ses catalogues. La recommandation officielle est un disque externe qu'on déplace physiquement entre les machines, pas une synchro en continu.
- **Infomaniak kDrive** documente officiellement le même type de souci pour les applications Adobe (Illustrator, Photoshop, Lightroom) : erreurs à l'enregistrement, duplication de fichiers. Leur recommandation officielle est d'exclure ces fichiers de la synchro.
- **Dropbox** : plusieurs utilisateurs des forums Lightroom Queen rapportent des catalogues corrompus après des mises à jour du client Dropbox, malgré des années d'usage stable auparavant. La parade qu'ils ont trouvée empiriquement : mettre la synchro en pause avant d'ouvrir Lightroom, ne la réactiver qu'après l'avoir fermé. C'est exactement le principe manuel que ces scripts automatisent.
- **OneDrive** : de nombreux fils sur les forums Adobe et Lightroom Queen décrivent des fichiers `.lrcat-data`/`.lrdata` qui refusent de se synchroniser tant que Lightroom les a ouverts, des previews corrompues, ou des renommages qui ne remontent jamais vers le cloud. Piège sournois : **Windows redirige par défaut le dossier "Images" (et donc le catalogue Lightroom, qui s'y installe par défaut) vers OneDrive à l'installation**, sans que l'utilisateur en ait toujours conscience.
- **Google Drive** : mêmes retours de prudence. Fonctionne tant qu'une copie locale existe et que la synchro est terminée avant chaque ouverture, mais aucune garantie native contre l'écriture concurrente.

La leçon unanime de toutes ces discussions, tous outils confondus : ne jamais stocker le catalogue vivant directement dans un dossier synchronisé, et ne jamais ouvrir Lightroom avant que la synchro précédente soit complètement terminée. Le mécanisme de blocage diffère d'un outil à l'autre (attribut Système, verrouillage de fichier, duplication...), mais le risque de fond est identique partout : un outil de synchronisation ne coordonne jamais son accès avec le verrou applicatif d'un logiciel qui écrit activement dans un fichier.

**Une remarque sur la position d'Adobe.** Il est légitime de se demander si le discours "non supporté" d'Adobe est purement technique ou aussi commercialement opportuniste. Adobe vend sa propre offre cloud (Creative Cloud, et une version cloud-native de Lightroom distincte de Classic) comme alternative "officiellement supportée" pour le multi-appareils : il y a donc un intérêt clair à ne pas investir dans un meilleur support des outils de sync tiers. Cela dit, le risque technique sous-jacent est réel et corroboré indépendamment : les incidents de corruption rapportés par les communautés existent en dehors de tout discours marketing, et le même type de problème touche d'autres logiciels à base de données embarquée (QuickBooks, Access...) sans lien avec Adobe. Les deux peuvent être vrais en même temps : un risque réel, qu'Adobe n'est simplement pas pressé de résoudre vu où cela mène commercialement.

## Pourquoi des archives .7z

Les 4 dossiers compagnons peuvent contenir des dizaines de milliers de petits fichiers (`Previews.lrdata` dépasse facilement 25 000 fichiers sur un vrai catalogue). Or chaque fichier individuel a un coût fixe pour un outil de sync : vérification, requête réseau, passage antivirus. Ce coût s'additionne, indépendamment de la taille des données. Résultat : synchroniser 25 000 petits fichiers prend beaucoup plus de temps que synchroniser une seule archive de la même taille totale.

Les deux scripts empaquettent donc chaque dossier en une archive `.7z` en mode "stockage" (`-mx0`, sans compression réelle : les données Lightroom sont déjà compressées en interne, l'objectif est la vitesse d'empaquetage, pas le gain de place). L'outil de sync ne voit plus que 5 fichiers au lieu de dizaines de milliers.

Bénéfice secondaire important : les archives sont créées de zéro par 7-Zip et n'héritent jamais de l'attribut Système que Lightroom pose sur les dossiers d'origine. Tout le problème d'attributs décrit plus haut devient sans objet pour ces 4 dossiers.

## Compatibilité avec d'autres outils

Aucun des deux scripts ne parle directement à l'outil de sync : ils manipulent uniquement des dossiers et fichiers locaux (robocopy et 7-Zip entre deux chemins sur le disque). L'outil de sync n'intervient qu'en aval, pour propager `_SyncedCopy` vers l'autre machine. **N'importe quel outil de sync cloud fonctionne donc**, à condition de savoir le limiter au seul dossier `_SyncedCopy`.

| Outil | Réglage équivalent |
|---|---|
| Synology Drive Client | Synchro sélective (par dossier) |
| Infomaniak kDrive | Gérer les dossiers à synchroniser (client desktop) |
| Dropbox | Synchronisation sélective (Selective Sync) |
| OneDrive | Choisir les dossiers |
| Google Drive (Drive pour ordinateur) | Synchroniser uniquement ces dossiers / mode miroir |

Dans tous les cas, la règle reste identique : ne cocher/synchroniser que `_SyncedCopy`, jamais `_NoSync_WorkingFiles`, jamais le dossier Lightroom entier.

## Prérequis

- Windows 10 ou 11
- Lightroom Classic (testé avec la 14.4)
- [7-Zip](https://www.7-zip.org/) installé (les deux scripts vérifient sa présence au démarrage et te guident s'il manque)
- Un outil de sync configurable par dossier (voir tableau ci-dessus)
- Le même nom de catalogue sur toutes les machines

## Lequel choisir ?

| | [`At each start/`](At%20each%20start/README.fr.md) | [`On demand/`](On%20demand/README.fr.md) |
|---|---|---|
| **Adapté si** | Tu alternes souvent entre les deux PC | Tu travailles 90%+ du temps sur un seul PC |
| **Quand ça se déclenche** | À chaque lancement de Lightroom | Seulement quand tu décides de changer de machine |
| **Friction au quotidien** | Un court pull/push à chaque session | Aucune : tu lances Lightroom normalement |
| **Script** | `start-lightroom.bat` | `sync-catalog.bat` |

Les deux partagent tout ce qui est décrit sur cette page, plus la même base de sécurité détaillée plus bas (pull non destructif, transport par archives `.7z`, tests d'intégrité, sauvegardes anti-crash). Les README de [`At each start`](At%20each%20start/README.fr.md) et [`On demand`](On%20demand/README.fr.md) ne couvrent que ce qui est propre à chacun : comment ça tourne au quotidien, ses étapes d'installation exactes, et son propre tableau de configuration.

Tu peux utiliser les deux en parallèle si ça t'arrange : voir la FAQ du README [`On demand`](On%20demand/README.fr.md) pour l'unique précaution à connaître si tu les mélanges.

## Organisation des dossiers

```
Lightroom Sync/
  At each start/
    README.md, README.fr.md      <- ce qui est propre a cette variante
    start-lightroom.bat          <- edite CATALOG avant usage, puis place-le pres de ton catalogue
  On demand/
    README.md, README.fr.md      <- ce qui est propre a cette variante
    sync-catalog.bat             <- edite CATALOG avant usage, puis place-le pres de ton catalogue
```

Chaque script regroupe ses variables configurables en haut : ouvre-le dans un éditeur de texte, règle `CATALOG` sur le nom de ton catalogue, enregistre, et place-le dans ton dossier Lightroom.

## Épingler un script à la barre des tâches

Windows bloque l'épinglage direct d'un fichier `.bat` à la barre des tâches (restriction de sécurité depuis Windows 10). Le contournement standard passe par un raccourci qui appelle `cmd.exe`, puisque Windows autorise l'épinglage d'un vrai `.exe`. Même méthode pour les deux scripts, seul le nom de fichier dans la Cible change.

**Méthode recommandée**, pour ne jamais avoir de raccourci qui traîne sur le Bureau :

1. `Win + R`, tape `shell:programs`, Entrée (ouvre le dossier réel du menu Démarrer).
2. Clic droit dans ce dossier, **Nouveau > Raccourci**, et renseigne (utilise `start-lightroom.bat` ou `sync-catalog.bat` selon celui que tu utilises) :
   ```
   C:\Windows\System32\cmd.exe /c "C:\chemin\vers\ton\dossier\Lightroom\start-lightroom.bat"
   ```
3. *(Optionnel)* Clic droit sur le raccourci créé, **Propriétés > Changer d'icône**, choisis `Lightroom.exe` pour une icône reconnaissable plutôt que celle de `cmd.exe`.
4. Le raccourci apparaît automatiquement dans la liste des applications du menu Démarrer. Clic droit dessus, **Épingler à Démarrer** et/ou **Épingler à la barre des tâches**.

Le `/c` exécute le script dans cette fenêtre `cmd` puis la ferme une fois terminé ; les invites `pause` du script continuent de fonctionner normalement puisqu'elles s'exécutent dans cette même session.

Si un raccourci a déjà été créé sur le Bureau et épinglé : le supprimer du Bureau ne casse pas l'épinglage à la barre des tâches (Windows conserve sa propre référence au moment de l'épinglage). Pour le menu Démarrer, c'est moins fiable selon les versions de Windows 11 ; par prudence, déplace plutôt le raccourci du Bureau vers `shell:programs` au lieu de le supprimer.

À refaire une fois par PC, avec le chemin propre à chaque machine dans le champ Cible.

## Sécurité : ce que les scripts font pour protéger tes données

Chaque mécanisme ci-dessous répond à un risque réel rencontré pendant le développement, et est implémenté à l'identique dans les deux scripts :

- **Pull jamais destructif.** Le pull fusionne (`/E` + `/XO`) : il ajoute et met à jour, mais n'écrase jamais un fichier local plus récent et ne supprime jamais rien en local. Si Lightroom a écrit des données fraîches lors de ta dernière session, un pull ne peut pas les détruire.
- **Push en miroir complet.** Le push (`/MIR` via les archives) fait de `_SyncedCopy` le reflet exact de ton état local : c'est voulu, les suppressions légitimes faites par Lightroom doivent se propager.
- **Test d'intégrité de chaque archive, dans les deux sens.** Au pull, une archive est testée (`7z t`) avant toute extraction : si elle est corrompue (un transfert incomplet, par exemple), le script s'arrête pour ce dossier et ta version locale reste intacte. Au push, l'archive fraîchement créée est testée avant d'être envoyée : jamais d'archive douteuse dans le circuit.
- **Sauvegarde de sécurité avant chaque pull.** Le `.lrcat` et `.lrcat-data` (le catalogue et son dossier le plus étroitement lié) sont copiés dans `_NoSync_WorkingFiles\_CrashBackups\` avec un horodatage, avant que le pull ne touche à quoi que ce soit. Scénario couvert : Lightroom plante sur le PC A avant le push, tu travailles ensuite sur le PC B, puis tu reviens sur le PC A ; le pull écraserait alors ton travail non poussé, mais la sauvegarde horodatée te permet de le récupérer. Les 2 sauvegardes les plus récentes sont conservées (réglable via `BACKUPS_KEEP`), les plus anciennes sont purgées automatiquement.
- **Détection agrégée des problèmes.** Chaque anomalie (copie échouée, archive corrompue, sauvegarde impossible...) allume un drapeau interne. Avant d'ouvrir Lightroom, si un problème est survenu au pull, le script te prévient et te laisse le choix de t'arrêter. En fin de cycle, si un problème est survenu où que ce soit, le message final devient un avertissement explicite ("NE PAS SUPPOSER QUE TOUT EST A JOUR") au lieu du message de succès.
- **Vérification post-push.** Après le push, le script vérifie que le `.lrcat` est bien présent dans `_SyncedCopy`.
- **Pause de sécurité avant la compression.** 8 secondes avant que le push commence à compresser, pour laisser les écritures en arrière-plan (aperçus, cache IA) se terminer après la fermeture de Lightroom.
- **Garde-fous au démarrage.** Les deux scripts refusent de tourner si Lightroom est déjà ouvert, si le catalogue n'est pas dans `_NoSync_WorkingFiles`, ou si 7-Zip est introuvable, avec à chaque fois un message expliquant quoi faire.

Ce que les scripts ne peuvent pas faire : vérifier eux-mêmes que la synchro réseau est terminée (aucune API/CLI fiable trouvée chez les outils de sync grand public). Cette vérification reste visuelle et humaine, c'est la seule étape de discipline qui t'incombe.

## Retour d'expérience : un incident réel

Pendant le développement, une première version utilisait `/MIR` (miroir avec suppression) aussi pour le pull. Résultat concret : après une session de travail locale, Lightroom avait créé des fichiers frais dans `.lrcat-data` ; le pull suivant, en "miroir", a supprimé ces fichiers locaux parce qu'ils n'existaient pas encore dans le dossier relais. Le catalogue (protégé par `/XO`, donc jamais remplacé) référençait alors des données que le pull venait d'effacer : Lightroom refusait de s'ouvrir avec une erreur générique, très difficile à diagnostiquer.

Leçons intégrées aux deux scripts :

- Le pull n'utilise plus jamais `/MIR` : il ne supprime rien, quoi qu'il arrive.
- Les archives sont testées avant toute extraction : un transfert incomplet est détecté au lieu de produire un état local incohérent.
- La sauvegarde `_CrashBackups` conserve ensemble le `.lrcat` et `.lrcat-data`, car restaurer l'un sans l'autre peut recréer exactement cette incohérence.

Si tu adaptes ces scripts, retiens le principe : **la direction relais vers local ne doit jamais supprimer quoi que ce soit**. C'est la propriété qui garantit qu'un transfert raté est récupérable au lieu d'être destructeur.

## Limites et conditions de test

- **Testé sur** : Windows 11, Lightroom Classic 14.4, Synology Drive Client (desktop), 7-Zip, catalogue utilisant activement Denoise IA, sélections générées, reconnaissance de visages et sync cloud Adobe.
- **Discipline manuelle obligatoire** : rien n'empêche techniquement d'ouvrir Lightroom sur les deux machines en même temps si on ignore les messages des scripts. La protection dépend du respect du flux pull/récupération → travail → push/envoi.
- **Pas de vérification automatique de fin de synchro** : aucune CLI ou API officielle trouvée chez Synology Drive Client pour interroger l'état de synchro par script. La vérification reste visuelle (icône dans la zone de notification), point de friction assumé.
- **Non officiellement supporté par Adobe** : cette méthode reste un contournement communautaire. Les `_CrashBackups` sont un filet à court terme (2 versions), pas un remplacement des vraies sauvegardes : garde la sauvegarde native de Lightroom (à la fermeture) et/ou une sauvegarde externe en parallèle.
- **`.lrcat-shm` / `.lrcat-wal` / `.lrcat.lock`** : fichiers temporaires SQLite, intentionnellement exclus de la copie. Ne jamais les sauvegarder ni les synchroniser.
- **Scripts volontairement sans accents (ASCII pur)** : un `.bat` avec des caractères accentués dépend de son encodage de sauvegarde. Selon l'éditeur utilisé pour le modifier, le fichier peut se corrompre silencieusement et provoquer des erreurs `n'est pas reconnu en tant que commande` à l'exécution. Rester en ASCII pur élimine ce risque durablement.
- **Scripts volontairement sans sous-routines (`call :label`)** : ce mécanisme batch s'est révélé fragile en usage réel (échec intermittent "le système ne trouve pas le nom de fichier de commandes", probablement lié à un verrouillage passager du `.bat` par l'antivirus ou l'outil de sync pendant que `cmd.exe` relit le fichier pour localiser l'étiquette). Tout est écrit en ligne : plus verbeux, mais sans ce point de défaillance. Le menu de `sync-catalog.bat` utilise de simples `goto`, exécutés avant toute activité disque.

## Pistes non retenues

- **Changer d'outil de sync (kDrive, Dropbox, OneDrive, Google Drive...) sans dossier relais** : même catégorie de problème quel que soit l'outil (voir [Ce que d'autres ont essayé](#ce-que-dautres-ont-essayé-et-pourquoi-ça-échoue) plus haut). Changer de fournisseur seul ne résout rien à la racine.
- **Symlink pour contourner l'attribut Système** : évoqué dans certains forums, résultats mitigés selon les configurations. Non retenu par manque de fiabilité constatée.
- **Vérification automatique de la synchro** : pas d'API/CLI officielle ; certains retours communautaires signalent même que l'icône de statut peut rester bloquée sans refléter l'état réel. Un faux sentiment de sécurité aurait été pire qu'une vérification manuelle.
- **Vérification du nombre de fichiers au pull** : implémentée puis retirée. Un écart au pull est normal et fréquent (le pull ne supprime jamais rien en local, donc les fichiers obsolètes s'y accumulent légitimement) : ce contrôle générait du bruit sans signal. Le passage aux archives a de toute façon rendu la question obsolète.
- **Lecteur virtuel (`subst`) pour unifier les chemins des photos** : fonctionne, mais ajoute une configuration par machine à maintenir (la commande ne survit pas au redémarrage). Non retenu ici ; garder la même arborescence de photos sur les deux PC est plus simple.

## Licence

Licence MIT : usage et modification libres, y compris en usage commercial, à la seule condition de conserver la mention de copyright et de licence ci-dessous dans toute redistribution : c'est ce qui garantit que ce dépôt reste cité comme source.

```
MIT License

Copyright (c) 2026 tnalias

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

À placer aussi dans un fichier `LICENSE` séparé à la racine du dépôt (convention GitHub).
