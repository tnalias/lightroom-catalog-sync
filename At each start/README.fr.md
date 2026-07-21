# Synchroniser un catalogue Lightroom Classic entre deux PC via un outil de sync cloud (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...)

[English](README.md) | **Français**

## En bref

Tu veux travailler sur le même catalogue Lightroom Classic depuis deux ordinateurs (un fixe et un laptop, par exemple), en utilisant ton outil de sync habituel pour faire voyager les données. Problème : les outils de sync cloud et les catalogues Lightroom ne font pas bon ménage, et cela finit en catalogues corrompus ou en données silencieusement non synchronisées.

Ce dépôt fournit un script unique, `start-lightroom.bat`, qui remplace ton raccourci Lightroom habituel. À chaque lancement, il fait trois choses :

1. Il **récupère** la dernière version du catalogue (au cas où tu aurais travaillé sur l'autre PC).
2. Il **lance Lightroom** et attend que tu le fermes.
3. Il **sauvegarde** tes modifications pour qu'elles repartent vers l'autre PC.

Ton outil de sync ne touche jamais aux fichiers que Lightroom utilise réellement : il ne voit qu'un dossier relais, manipulé uniquement quand Lightroom est fermé. C'est ce qui rend la méthode sûre.

Ce document ne couvre que ce qui est propre à cette variante `start-lightroom.bat` : les étapes ci-dessous supposent que tu as déjà lu le [README racine](../README.fr.md), qui couvre tout ce qui est partagé par les deux scripts (le problème, pourquoi les outils de sync corrompent les catalogues Lightroom, les prérequis, l'organisation des dossiers, les mécanismes de sécurité, les limites, et plus).

**Deux modes d'utilisation sont disponibles** : `start-lightroom.bat` synchronise automatiquement à chaque lancement de Lightroom (ce document), tandis que `sync-catalog.bat` synchronise uniquement à la demande, pour ceux qui travaillent 90% du temps sur une seule machine : voir [la variante à la demande](../On%20demand/README.fr.md).

## Sommaire

- [Comment ça marche](#comment-ça-marche)
- [Installation](#installation)
- [Adapter le script à ton cas](#adapter-le-script-à-ton-cas)
- [Usage quotidien](#usage-quotidien)

## Comment ça marche

Principe : ne jamais laisser l'outil de synchronisation toucher aux fichiers vivants du catalogue. À la place, un dossier relais sert d'intermédiaire, et n'est manipulé que lorsque Lightroom est fermé, donc jamais en cours d'écriture.

```
Lightroom\
  ├── start-lightroom.bat     <- le script (remplace ton raccourci habituel)
  ├── _NoSync_WorkingFiles\   <- fichiers vivants, utilises par Lightroom
  │                              JAMAIS synchronises
  └── _SyncedCopy\            <- dossier relais
                                 SEUL dossier synchronise
                                 contient : le .lrcat + 4 archives .7z
```

À chaque lancement, le script déroule 4 étapes :

1. **Vérification** : Lightroom ne doit pas être déjà ouvert sur cette machine (sinon le script s'arrête).
2. **Pull** : le script te demande de confirmer visuellement que ton outil de sync est "à jour", puis récupère depuis `_SyncedCopy` le `.lrcat` et les 4 archives, teste l'intégrité de chaque archive, les extrait, et fusionne le contenu vers `_NoSync_WorkingFiles`. Cette fusion n'écrase jamais un fichier local plus récent et ne supprime jamais rien : si quelque chose se passe mal, ta version locale reste intacte.
3. **Lightroom** : le script lance Lightroom et attend, en arrière-plan, que tu le fermes. Tu travailles normalement.
4. **Push** : après une pause de sécurité (le temps que Lightroom finisse ses écritures en arrière-plan), le script compresse chacun des 4 dossiers en une archive `.7z`, teste l'intégrité de chaque archive fraîchement créée, puis les copie avec le `.lrcat` vers `_SyncedCopy`. Ton outil de sync prend le relais et propage tout vers l'autre PC.

Le script est auto-localisant (`%~dp0` : il déduit son propre emplacement) et identique sur toutes les machines : un seul fichier à copier, pas de chemin à éditer, seul le nom du catalogue est à configurer une fois.

## Installation

### Sur le premier PC (celui qui a déjà le catalogue)

1. Ouvre `start-lightroom.bat` dans un éditeur de texte et remplace `NomCatalogue` dans la ligne `set "CATALOG=NomCatalogue"` par le vrai nom de ton catalogue, sans l'extension `.lrcat` (voir [Adapter le script à ton cas](#adapter-le-script-à-ton-cas) pour les autres réglages).
2. Place `start-lightroom.bat` directement dans ton dossier Lightroom.
3. Lightroom fermé, crée le dossier `_NoSync_WorkingFiles` dans ce même dossier.
4. Déplace-y le `.lrcat` et les 4 dossiers associés (`.lrcat-data`, `Previews.lrdata`, `Helper.lrdata`, `Sync.lrdata`).
5. Ouvre Lightroom une fois en double-cliquant directement sur le `.lrcat` à son nouvel emplacement (pour que Lightroom mémorise le nouveau chemin), puis referme-le.
6. Lance `start-lightroom.bat` : au premier lancement, il crée automatiquement `_SyncedCopy` et te rappelle l'étape suivante. Laisse-le dérouler un cycle complet (pull à vide, Lightroom, push) : à la fermeture de Lightroom, il remplit `_SyncedCopy` avec le `.lrcat` et les 4 archives.
7. Dans ton outil de sync, active la synchro sélective sur **uniquement** `_SyncedCopy`.
8. Attends que la synchro remonte complètement les 5 fichiers vers le cloud/NAS avant de passer au PC suivant.

### Sur le(s) PC suivant(s)

Ce PC ne possède pas encore de catalogue : il va le récupérer via la synchro.

1. Copie le même `start-lightroom.bat` (déjà configuré) dans ton dossier Lightroom sur cette machine.
2. Configure ton outil de sync pour synchroniser uniquement `_SyncedCopy`, et attends que les 5 fichiers (le `.lrcat` + les 4 archives `.7z`) y apparaissent entièrement synchronisés.
3. Crée le dossier `_NoSync_WorkingFiles` à côté.
4. Copie manuellement le seul fichier `.lrcat` depuis `_SyncedCopy` vers `_NoSync_WorkingFiles` (le script exige sa présence comme garde-fou avant de tourner ; les 4 dossiers, eux, seront extraits automatiquement des archives au premier pull).
5. Lance `start-lightroom.bat` : le pull extrait les 4 archives vers `_NoSync_WorkingFiles`, puis Lightroom se lance. À cette toute première ouverture sur cette machine, Lightroom ne connaît pas encore ce catalogue : ouvre-le via Fichier > Ouvrir un catalogue, en pointant le `.lrcat` dans `_NoSync_WorkingFiles`. Les fois suivantes, il s'ouvrira automatiquement.

## Adapter le script à ton cas

Toutes les variables à personnaliser sont regroupées en haut du script :

| Variable | Rôle | À modifier ? |
|---|---|---|
| `CATALOG` | Nom de ton catalogue, sans `.lrcat` | **Oui, obligatoire** (une seule fois, le même sur tous les PC) |
| `LIGHTROOM_EXE` | Chemin de `Lightroom.exe` | Seulement si installation non standard (clic droit sur ton raccourci Lightroom > Propriétés > Cible pour le trouver) |
| `ZIP7` | Chemin de `7z.exe` | Seulement si 7-Zip est installé ailleurs que `C:\Program Files\7-Zip\` |
| `BACKUPS_KEEP` | Nombre de sauvegardes de sécurité conservées | Optionnel (2 par défaut) |

Le reste s'adapte tout seul : le script détecte son propre emplacement (`%~dp0`), donc les chemins des dossiers n'ont jamais besoin d'être édités, même si ton dossier Lightroom est sur `C:` sur une machine et `D:` sur l'autre.

Si ton dossier Lightroom vit à des emplacements différents selon les PC, aucun souci pour le catalogue. En revanche, si tes **photos** vivent aussi à des chemins différents, Lightroom les marquera "introuvables" en changeant de machine : garde la même arborescence de photos sur les deux PC pour éviter ça.

## Usage quotidien

- Toujours lancer Lightroom via `start-lightroom.bat`, jamais directement.
- Ne jamais ouvrir Lightroom sur les deux PC en même temps.
- Avant d'ouvrir Lightroom sur l'autre PC, vérifier visuellement que ton outil de sync affiche "à jour" (pas de synchro en cours).
- Si le script affiche des lignes ATTENTION, les lire : il te préviendra explicitement en fin de cycle et te déconseillera de passer sur l'autre PC tant que le problème n'est pas compris.
