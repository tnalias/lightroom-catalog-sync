# Synchronisation d'un catalogue Lightroom Classic entre deux PC

[English](README.md) | **Français**

Deux façons de synchroniser en toute sécurité un catalogue Lightroom Classic entre deux ordinateurs via un outil de sync cloud (Synology Drive, kDrive, Dropbox, OneDrive, Google Drive...), sans le corrompre. Choisis le dossier qui correspond à ta façon de travailler.

**Windows uniquement.** Les deux scripts sont des fichiers `.bat` Windows qui s'appuient sur des outils spécifiques à Windows (`robocopy`, `attrib`, PowerShell). Il n'existe pas de version macOS ni Linux, même si l'approche sous-jacente (dossier relais, pull non destructif, transport en `.7z`) n'est pas spécifique à Windows en soi et pourrait être portée en scripts shell. Contributions bienvenues.

## Lequel choisir ?

| | [`At each start/`](At%20each%20start/README.fr.md) | [`On demand/`](On%20demand/README.fr.md) |
|---|---|---|
| **Adapté si** | Tu alternes souvent entre les deux PC | Tu travailles 90%+ du temps sur un seul PC |
| **Quand ça se déclenche** | À chaque lancement de Lightroom | Seulement quand tu décides de changer de machine |
| **Friction au quotidien** | Un court pull/push à chaque session | Aucune : tu lances Lightroom normalement |
| **Script** | `start-lightroom.bat` | `sync-catalog.bat` |

Les deux partagent la même base de sécurité (dossier relais, pull non destructif, transport par archives `.7z`, tests d'intégrité, sauvegardes anti-crash), documentée en entier dans le README de [`At each start`](At%20each%20start/README.fr.md). Le README de [`On demand`](On%20demand/README.fr.md) ne couvre que ce qui diffère dans cette variante, et suppose que tu as déjà lu le premier.

Tu peux utiliser les deux en parallèle si ça t'arrange : voir la FAQ du README [`On demand`](On%20demand/README.fr.md) pour l'unique précaution à connaître si tu les mélanges.

## Organisation des dossiers

```
Lightroom Sync/
  At each start/
    README.md, README.fr.md      <- documentation complete (a lire en premier)
    start-lightroom.bat          <- edite CATALOG avant usage, puis place-le pres de ton catalogue
  On demand/
    README.md, README.fr.md      <- documentation de ce qui differe
    sync-catalog.bat             <- edite CATALOG avant usage, puis place-le pres de ton catalogue
```

Chaque script regroupe ses variables configurables en haut : ouvre-le dans un éditeur de texte, règle `CATALOG` sur le nom de ton catalogue, enregistre, et place-le dans ton dossier Lightroom.

## Licence

MIT, texte complet dans l'un ou l'autre README.
