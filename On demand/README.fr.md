# Variante synchronisation a la demande : `sync-catalog.bat`

[English](README.md) | **Français**

Ce document accompagne le projet. Voir le [README racine](../README.fr.md) pour tout le contexte (le problème, pourquoi les outils de sync corrompent les catalogues Lightroom, et la justification du transport en `.7z`), et le README de [`At each start`](../At%20each%20start/README.fr.md) pour l'architecture à dossier relais et le déroulé détaillé de l'installation. Lis ces deux documents d'abord si ce n'est pas fait.

## Quand choisir cette variante plutôt que `start-lightroom.bat`

`start-lightroom.bat` synchronise à **chaque** lancement de Lightroom. C'est le bon choix quand tu alternes souvent entre machines : la discipline est intégrée, impossible d'oublier.

`sync-catalog.bat` synchronise **uniquement quand tu le demandes**. C'est le bon choix quand tu travailles 90% du temps sur une seule machine : au quotidien tu lances Lightroom normalement (double-clic, ton raccourci habituel, zéro rituel, zéro attente), et tu lances ce script seulement le jour où tu changes réellement de machine. Ça fonctionne quelle que soit ta machine principale, et les deux scripts peuvent coexister dans le même dossier.

La contrepartie : la protection n'est plus systématique, elle repose sur le fait de penser à synchroniser avant de changer. Le script compense avec un garde anti-divergence (ci-dessous) qui rattrape le cas dangereux si tu oublies.

## Comment ça marche

Lance `sync-catalog.bat` (Lightroom fermé). Il affiche où en sont les choses, puis pose une seule question situationnelle :

```
Ou en es-tu ?

  [1] Je viens de TRAVAILLER sur CE PC
      -> J'envoie mes modifications vers l'autre PC

  [2] Je vais MAINTENANT travailler sur CE PC
      -> Je recupere d'abord les modifications de l'autre PC

  [3] Annuler (ne rien faire)
```

Pas de jargon push/pull : tu réponds selon ta situation, pas selon la mécanique de sync. Après ton choix, le script affiche un récapitulatif d'une ligne de ce qu'il va exactement faire (quelle machine envoie ou reçoit, quelle version sera remplacée, envoyée par qui et quand) et attend une dernière touche avant d'agir.

## Changer de machine : la séquence complète

1. **Sur le PC où tu viens de travailler** : ferme Lightroom, lance `sync-catalog.bat`, choisis **[1] Envoyer**.
2. **Attends** que ton outil de sync ait propagé (icône "à jour" sur les deux machines).
3. **Sur le PC où tu vas travailler** : lance `sync-catalog.bat`, choisis **[2] Récupérer**, puis ouvre Lightroom normalement.

C'est tout. Entre deux changements de machine : aucun script, aucun rituel, utilise juste Lightroom.

## Le garde anti-divergence

Le vrai danger du mode à la demande n'est pas technique, c'est **l'oubli**. Scénario : tu travailles trois semaines sur le PC B sans synchroniser (normal, pas besoin), puis tu prends le PC A un jour en oubliant d'envoyer d'abord. Tu travailles sur le PC A par-dessus une vieille version, tu envoies depuis le PC A... et te voilà avec deux versions divergentes du catalogue. Lightroom ne sait pas fusionner deux catalogues divergents. C'est le pire scénario possible, pire qu'une corruption.

Le garde : chaque envoi réussi écrit un fichier témoin (`last-sync-state.txt`) dans `_SyncedCopy`, mémorisant quelle machine a envoyé et quand. Chaque machine garde aussi une trace locale de la dernière version qu'elle a récupérée. Grâce à ça :

- **À l'envoi**, si la version actuelle du relais vient de l'autre machine ET n'a jamais été récupérée ici, le script s'arrête avec une alerte bloquante explicite ("envoyer maintenant écraserait le travail fait sur [autre PC]") et un choix délibéré oui/non, orienté vers l'annulation et la récupération d'abord.
- **À la récupération**, le script t'indique toujours qui a envoyé la version actuelle du relais et quand. Si elle vient de ce PC même (rien de nouveau à récupérer), il le dit et demande si tu veux vraiment continuer, plutôt que d'exécuter en silence une opération à vide que tu pourrais prendre pour un transfert réussi.

Les fichiers d'état ne sont écrits que si l'opération se termine **sans aucune erreur** : un envoi partiel n'est jamais enregistré comme version valide du relais.

## Tout ce qui est hérité de `start-lightroom.bat`

Même structure de dossiers, mêmes prérequis, et les mêmes mécanismes de sécurité (récupération non destructive, tests d'intégrité des archives, sauvegardes anti-crash, détection agrégée des erreurs, garde-fous au démarrage) que `start-lightroom.bat`, tous détaillés dans le [README racine](../README.fr.md), non répétés ici. L'installation suit la même structure de dossiers et le même principe, détaillée plus bas et renvoyant au README de [`At each start`](../At%20each%20start/README.fr.md) là où les étapes sont identiques.

## Installation

Mêmes dossiers que `start-lightroom.bat` (`_NoSync_WorkingFiles` + `_SyncedCopy`), même principe, adapté au menu envoyer/récupérer de ce script plutôt qu'à un pull-puis-push automatique :

**Sur le premier PC (celui qui a déjà le catalogue) :**
1. Édite `CATALOG` dans `sync-catalog.bat` (voir [Configuration](#configuration) plus bas).
2. Place `sync-catalog.bat` dans ton dossier Lightroom. Lightroom fermé, crée `_NoSync_WorkingFiles` et déplace-y le `.lrcat` et ses 4 dossiers compagnons, exactement comme décrit aux étapes 3-5 de l'installation du README `At each start`.
3. Lance `sync-catalog.bat`, choisis **[1] Envoyer** (ça crée `_SyncedCopy` au premier lancement et y pousse le contenu).
4. Dans ton outil de sync, active la synchro sélective sur **uniquement** `_SyncedCopy`.
5. Attends que la synchro remonte complètement avant de passer au PC suivant.

**Sur le(s) PC suivant(s) :**
1. Copie le même `sync-catalog.bat` déjà configuré dans ton dossier Lightroom là-bas.
2. Configure ton outil de sync sur `_SyncedCopy`, et attends que le `.lrcat` et les 4 archives apparaissent entièrement synchronisés.
3. Crée `_NoSync_WorkingFiles`, et copie manuellement uniquement le fichier `.lrcat` dedans (le script exige sa présence comme garde-fou ; les 4 dossiers seront extraits automatiquement à la première récupération).
4. Lance `sync-catalog.bat`, choisis **[2] Récupérer**.
5. Ouvre Lightroom via Fichier > Ouvrir un catalogue, en pointant vers le `.lrcat` dans `_NoSync_WorkingFiles`. Il s'ouvrira automatiquement par la suite.

### À quoi ça ressemble une fois en place

Par défaut, Lightroom Classic crée son catalogue dans le dossier Images de ton utilisateur Windows, typiquement `C:\Users\<TonNomUtilisateur>\Pictures\Lightroom\` (voir le README de [`At each start`](../At%20each%20start/README.fr.md#à-quoi-ça-ressemble-une-fois-en-place) pour la note complète à ce sujet). Exemple concret, avec un catalogue nommé `NomCatalogue` :

```
Lightroom\
  sync-catalog.bat
  _NoSync_WorkingFiles\
    NomCatalogue.lrcat
    NomCatalogue.lrcat-data\
    NomCatalogue Previews.lrdata\
    NomCatalogue Helper.lrdata\
    NomCatalogue Sync.lrdata\
    _CrashBackups\                    <- cree automatiquement, copies de securite
    _last-pull-state.txt              <- cree automatiquement, trace la derniere version recuperee ici
  _SyncedCopy\
    NomCatalogue.lrcat
    NomCatalogue.lrcat-data.7z
    NomCatalogue Previews.lrdata.7z
    NomCatalogue Helper.lrdata.7z
    NomCatalogue Sync.lrdata.7z
    last-sync-state.txt               <- cree automatiquement, enregistre qui a envoye en dernier et quand
```

Même disposition que `start-lightroom.bat` (voir le README de [`At each start`](../At%20each%20start/README.fr.md#à-quoi-ça-ressemble-une-fois-en-place) pour le rôle de chaque dossier) : les deux ajouts ici sont les fichiers témoins dont dépend le garde anti-divergence, tous deux créés et mis à jour automatiquement, jamais à toucher à la main.

## Configuration

La configuration tient en 2-3 variables en haut de `sync-catalog.bat` :

| Variable | Rôle | À modifier ? |
|---|---|---|
| `CATALOG` | Nom de ton catalogue, sans `.lrcat` | **Oui, obligatoire** (une seule fois, le même sur tous les PC) |
| `ZIP7` | Chemin vers `7z.exe` | Seulement si 7-Zip est installé ailleurs que `C:\Program Files\7-Zip\` |
| `BACKUPS_KEEP` | Nombre de sauvegardes de sécurité conservées | Optionnel (2 par défaut) |

`LIGHTROOM_EXE` n'existe pas dans ce script : inutile, puisque `sync-catalog.bat` ne lance jamais Lightroom.

## Épingler le script

Même méthode que pour `start-lightroom.bat` : voir [Épingler un script à la barre des tâches](../README.fr.md#épingler-un-script-à-la-barre-des-tâches) dans le README racine. Seule différence : pointe la Cible du raccourci vers `sync-catalog.bat` à la place :
```
C:\Windows\System32\cmd.exe /c "C:\chemin\vers\ton\dossier\Lightroom\sync-catalog.bat"
```

## FAQ

**Le script a bloqué mon envoi avec une alerte "RISQUE DE PERTE DE TRAVAIL". Que faire ?**
Ça signifie que le relais contient une version venant de l'autre machine, que tu n'as jamais récupérée sur ce PC. Dans presque tous les cas, la bonne réponse est : réponds N, fais d'abord **[2] Récupérer**, vérifie ton catalogue dans Lightroom, puis envoie. Ne force avec O que si tu es certain que la version de ce PC est celle à garder et que celle de l'autre machine doit être abandonnée.

**J'ai choisi Récupérer mais rien n'a semblé changer.**
Regarde le message : si la dernière version du relais a été envoyée par ce même PC, il n'y avait réellement rien de nouveau à récupérer. Le travail fait sur l'autre machine n'atteint le relais qu'après avoir fait **[1] Envoyer** là-bas.

**Puis-je continuer à utiliser `start-lightroom.bat` en parallèle ?**
Oui, les deux scripts partagent les mêmes dossiers et archives et peuvent coexister. Une réserve : `start-lightroom.bat` ne met pas à jour le fichier témoin (son flux systématique pull puis push n'en a pas besoin). Si tu pousses via `start-lightroom.bat`, le témoin devient périmé, et le garde anti-divergence peut donner un verdict erroné au prochain envoi manuel. Règle simple et sûre : un seul mode par période ; si tu les mélanges malgré tout, fais **[2] Récupérer** sur l'autre machine avant de te fier à un envoi.

## Licence

Même licence MIT que le reste du projet (voir le [README racine](../README.fr.md)).
