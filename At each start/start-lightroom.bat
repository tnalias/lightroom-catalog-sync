@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  start-lightroom.bat
REM    1) Pull : recupere la derniere version du catalogue depuis _SyncedCopy
REM    2) Lance Lightroom, attend que tu le fermes
REM    3) Push : renvoie tes modifs vers _SyncedCopy
REM
REM  A CONFIGURER : PARENT, CATALOG, LIGHTROOM_EXE, ZIP7 (voir dessous)
REM  LIGHTROOM_EXE : clic droit sur ton raccourci Lightroom > Proprietes > Cible
REM  ZIP7 : chemin vers 7z.exe (7-Zip), deja au chemin standard d'installation
REM
REM  Script auto-localisant : PARENT = le dossier ou se trouve CE
REM  fichier .bat. Place-le directement dans ton dossier Lightroom,
REM  sur n'importe quel PC. A CONFIGURER ci-dessous :
REM    - CATALOG : le nom de ton catalogue, SANS l'extension .lrcat
REM    - LIGHTROOM_EXE / ZIP7 : deja aux chemins standard ; ne les
REM      modifie que si tes installations sont differentes
REM
REM  STRUCTURE ATTENDUE (dossiers freres, PAS imbriques) :
REM    PARENT\_NoSync_WorkingFiles\  <- fichiers vivants, JAMAIS synchronises
REM    PARENT\_SyncedCopy\           <- relais, SEUL dossier synchronise
REM
REM  Ton outil de sync (Synology Drive, kDrive, Dropbox, OneDrive...) :
REM  configure-le pour ne synchroniser QUE "_SyncedCopy".
REM  Jamais "_NoSync_WorkingFiles", jamais le dossier Lightroom entier -
REM  sinon le catalogue vivant serait synchronise directement, ce qui
REM  cause des erreurs/corruptions.
REM
REM  IMPORTANT : les 4 dossiers de donnees compagnons (.lrcat-data,
REM  Previews.lrdata, Helper.lrdata, Sync.lrdata) sont transportes sous
REM  forme d'archives .7z, pas comme des dossiers de fichiers bruts.
REM  Raison : ces dossiers peuvent contenir des dizaines de milliers de
REM  petits fichiers (Previews.lrdata en particulier). Que ce soit en
REM  local ou via l'outil de sync, chaque fichier individuel a un cout
REM  fixe (verification, acces disque, antivirus...) qui s'additionne -
REM  une seule grosse archive est presque toujours plus rapide que des
REM  milliers de petits fichiers, meme a volume de donnees egal.
REM  L'integrite de chaque archive est testee ^(7z t^) AVANT toute
REM  extraction ou fusion : si une archive est corrompue, le script
REM  s'arrete a cette etape et ne touche jamais ta version locale.
REM  La fusion finale apres extraction reste non destructive ^(/E + /XO,
REM  jamais /MIR^), meme principe de securite qu'avant.
REM  Effet de bord utile : les .7z sont crees de zero par 7-Zip et
REM  n'heritent jamais de l'attribut Systeme que Lightroom pose sur les
REM  dossiers d'origine - la saga des attributs S/H/P/U devient sans
REM  objet pour ces 4 dossiers.
REM
REM  IMPORTANT : ce fichier est volontairement sans accents (ASCII pur).
REM  Un .bat avec accents depend de son encodage de sauvegarde (UTF-8,
REM  ANSI...) et peut se corrompre silencieusement selon l'editeur
REM  utilise pour le modifier, causant des erreurs "n'est pas reconnu
REM  en tant que commande". Ne pas reintroduire d'accents ici.
REM
REM  IMPORTANT : ce script n'utilise volontairement AUCUNE sous-routine
REM  (pas de "call :label"). Ce mecanisme s'est revele fragile en usage
REM  reel. Tout est donc ecrit en ligne, plus verbeux mais sans point de
REM  defaillance de ce type.
REM
REM  IMPORTANT : apres chaque copie du .lrcat en PUSH, le script compte
REM  les fichiers cote source et destination et compare (le push est un
REM  miroir complet, source et destination doivent etre identiques).
REM  Cette verification n'est volontairement pas faite au pull, ou un
REM  ecart est normal (le pull ne supprime jamais rien en local).
REM ============================================================

set "PARENT=%~dp0"
set "BASE=%PARENT%_NoSync_WorkingFiles"
set "SYNCED=%PARENT%_SyncedCopy"
set "CATALOG=NomCatalogue"
set "LIGHTROOM_EXE=C:\Program Files\Adobe\Adobe Lightroom Classic\Lightroom.exe"
set "ZIP7=C:\Program Files\7-Zip\7z.exe"
set "STAGING=%TEMP%\LightroomSyncStaging"
set "LOG=%PARENT%sync-backup.log"
set "BACKUPS_KEEP=2"
set "HAD_ERROR=0"

cls
echo ================================================================
echo   DEMARRAGE DE LIGHTROOM AVEC SYNCHRONISATION - %COMPUTERNAME%
echo ================================================================
echo.

REM --- Securite : le catalogue doit deja etre dans _NoSync_WorkingFiles ---
if not exist "%BASE%\%CATALOG%.lrcat" (
    echo   PROBLEME : impossible de trouver "%CATALOG%.lrcat" dans
    echo   %BASE%
    echo.
    echo   Ce script suppose que ton catalogue vit deja dans _NoSync_WorkingFiles.
    echo   Si c'est la premiere fois que tu l'utilises, fais ceci
    echo   d'abord ^(Lightroom ferme^) :
    echo     1. Cree le dossier _NoSync_WorkingFiles dans %PARENT%
    echo     2. Deplace-y "%CATALOG%.lrcat" et les 4 dossiers associes
    echo        ^(.lrcat-data, Previews.lrdata, Helper.lrdata, Sync.lrdata^)
    echo     3. Ouvre Lightroom une fois en double-cliquant directement
    echo        sur le .lrcat a son nouvel emplacement
    echo     4. Relance ensuite ce script normalement
    echo.
    pause
    exit /b 1
)

REM --- Securite : 7-Zip doit etre installe ---
if not exist "%ZIP7%" (
    echo   PROBLEME : 7-Zip introuvable a l'emplacement configure :
    echo   %ZIP7%
    echo.
    echo   Installe 7-Zip ^(https://www.7-zip.org/^) ou corrige la ligne
    echo   ZIP7 en haut de ce script si ton installation est ailleurs.
    echo.
    pause
    exit /b 1
)

REM --- Premier lancement : le dossier relais n'existe pas encore ---
if not exist "%SYNCED%\" (
    echo   Premier lancement detecte sur cette machine : creation du
    echo   dossier _SyncedCopy ^(le relais utilise par ton outil de sync^).
    mkdir "%SYNCED%" 2>NUL
    echo.
    echo   IMPORTANT : va dans ton outil de sync ^(Synology Drive,
    echo   kDrive, Dropbox, OneDrive...^) et configure sa synchro
    echo   selective pour ne cocher QUE ce dossier _SyncedCopy
    echo   ^(pas _NoSync_WorkingFiles, pas le dossier Lightroom entier^). Sans
    echo   ca, rien ne sera synchronise vers l'autre PC.
    echo.
    pause
    echo.
)

REM --- Preparation du dossier de travail temporaire (zips/extraction) ---
if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL
mkdir "%STAGING%" 2>NUL

REM --- Etape 1/4 ---
echo [1/4] Verification que Lightroom n'est pas deja ouvert...
tasklist /FI "IMAGENAME eq Lightroom.exe" 2>NUL | find /I "Lightroom.exe" >NUL
if "%ERRORLEVEL%"=="0" (
    echo.
    echo   PROBLEME : Lightroom est deja ouvert sur cette machine.
    echo   Ferme-le d'abord, puis relance ce script.
    echo.
    pause
    exit /b 1
)
echo       OK - Lightroom n'est pas ouvert.
echo.

REM --- Etape 2/4 : PULL ---
echo [2/4] Recuperation de la derniere version du catalogue
echo       ^(au cas ou tu aurais travaille sur l'autre PC^)
echo.
echo       AVANT DE CONTINUER, VERIFIE :
echo       - Regarde l'icone de ton outil de sync en bas a droite
echo       - Elle doit dire "a jour", PAS "synchronisation en cours"
echo       - Si tu n'es pas sur, attends une minute et reverifie
echo.
echo       Appuie sur une touche UNIQUEMENT quand c'est confirme
echo       ^(ou ferme cette fenetre pour tout annuler sans rien faire^)
pause >NUL
echo.
echo       Copie en cours, merci de patienter...
echo.

REM --- Sauvegarde de securite du catalogue local AVANT tout pull ---
REM Toujours faite, inconditionnellement : simple et fiable plutot que
REM d'essayer de detecter le cas precis "crash sans push". Si jamais un
REM pull remplace une version locale non poussee (PC A plante sans
REM pousser, PC B pousse plus tard, retour sur PC A), cette sauvegarde
REM reste le point de retour. .lrcat + .lrcat-data sont sauvegardes
REM (le catalogue et son dossier de donnees le plus etroitement lie,
REM ensemble suffisants pour restaurer un etat coherent) ; Previews,
REM Helper et Sync sont volontairement exclus (regenerables ou peu
REM critiques, et Previews.lrdata est bien trop volumineux pour une
REM sauvegarde a chaque pull).
if not exist "%BASE%\_CrashBackups\" mkdir "%BASE%\_CrashBackups" 2>NUL
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%T"
if "!TS!"=="" (
    echo       ATTENTION : impossible de generer un horodatage ^(PowerShell indisponible ?^) - sauvegarde de securite sautee
    set "HAD_ERROR=1"
) else (
    copy /Y "%BASE%\%CATALOG%.lrcat" "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat" >NUL 2>&1
    if not exist "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat" (
        echo       ATTENTION : la sauvegarde de securite du catalogue a echoue ^(disque plein ? permissions ?^)
        set "HAD_ERROR=1"
    )
    if exist "%BASE%\%CATALOG%.lrcat-data\" robocopy "%BASE%\%CATALOG%.lrcat-data" "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat-data" /E /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
)
for /f "skip=%BACKUPS_KEEP% delims=" %%F in ('dir /b /o-d "%BASE%\_CrashBackups\%CATALOG%_*.lrcat" 2^>NUL') do del /Q "%BASE%\_CrashBackups\%%F" 2>NUL
for /f "skip=%BACKUPS_KEEP% delims=" %%F in ('dir /b /ad /o-d "%BASE%\_CrashBackups\%CATALOG%_*.lrcat-data" 2^>NUL') do rd /S /Q "%BASE%\_CrashBackups\%%F" 2>NUL

if not exist "%SYNCED%\%CATALOG%.lrcat" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%CATALOG%.lrcat"
) else (
    robocopy "%SYNCED%" "%BASE%" "%CATALOG%.lrcat" /XO /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de "%CATALOG%.lrcat" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        echo       OK - "%CATALOG%.lrcat"
    )
)

if not exist "%SYNCED%\%CATALOG%.lrcat-data.7z" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%BASE%\%CATALOG%.lrcat-data"
) else (
    robocopy "%SYNCED%" "%STAGING%" "%CATALOG%.lrcat-data.7z" /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de l'archive "%CATALOG%.lrcat-data.7z" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG%.lrcat-data.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG%.lrcat-data" - version locale inchangee
            set "HAD_ERROR=1"
        ) else (
            if exist "%STAGING%\extracted\" rd /S /Q "%STAGING%\extracted" 2>NUL
            mkdir "%STAGING%\extracted" 2>NUL
            "%ZIP7%" x "%STAGING%\%CATALOG%.lrcat-data.7z" -o"%STAGING%\extracted" -y >NUL 2>&1
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 1 (
                echo       ATTENTION : echec d'extraction pour "%CATALOG%.lrcat-data"
                set "HAD_ERROR=1"
            ) else (
                robocopy "%STAGING%\extracted" "%BASE%\%CATALOG%.lrcat-data" /E /XO /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
                set "RC=!ERRORLEVEL!"
                if !RC! GEQ 8 (
                    echo       ATTENTION : probleme lors de la fusion locale de "%CATALOG%.lrcat-data" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%BASE%\%CATALOG%.lrcat-data"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Previews.lrdata.7z" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%BASE%\%CATALOG% Previews.lrdata"
) else (
    robocopy "%SYNCED%" "%STAGING%" "%CATALOG% Previews.lrdata.7z" /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de l'archive "%CATALOG% Previews.lrdata.7z" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Previews.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Previews.lrdata" - version locale inchangee
            set "HAD_ERROR=1"
        ) else (
            if exist "%STAGING%\extracted\" rd /S /Q "%STAGING%\extracted" 2>NUL
            mkdir "%STAGING%\extracted" 2>NUL
            "%ZIP7%" x "%STAGING%\%CATALOG% Previews.lrdata.7z" -o"%STAGING%\extracted" -y >NUL 2>&1
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 1 (
                echo       ATTENTION : echec d'extraction pour "%CATALOG% Previews.lrdata"
                set "HAD_ERROR=1"
            ) else (
                robocopy "%STAGING%\extracted" "%BASE%\%CATALOG% Previews.lrdata" /E /XO /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
                set "RC=!ERRORLEVEL!"
                if !RC! GEQ 8 (
                    echo       ATTENTION : probleme lors de la fusion locale de "%CATALOG% Previews.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%BASE%\%CATALOG% Previews.lrdata"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Helper.lrdata.7z" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%BASE%\%CATALOG% Helper.lrdata"
) else (
    robocopy "%SYNCED%" "%STAGING%" "%CATALOG% Helper.lrdata.7z" /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de l'archive "%CATALOG% Helper.lrdata.7z" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Helper.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Helper.lrdata" - version locale inchangee
            set "HAD_ERROR=1"
        ) else (
            if exist "%STAGING%\extracted\" rd /S /Q "%STAGING%\extracted" 2>NUL
            mkdir "%STAGING%\extracted" 2>NUL
            "%ZIP7%" x "%STAGING%\%CATALOG% Helper.lrdata.7z" -o"%STAGING%\extracted" -y >NUL 2>&1
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 1 (
                echo       ATTENTION : echec d'extraction pour "%CATALOG% Helper.lrdata"
                set "HAD_ERROR=1"
            ) else (
                robocopy "%STAGING%\extracted" "%BASE%\%CATALOG% Helper.lrdata" /E /XO /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
                set "RC=!ERRORLEVEL!"
                if !RC! GEQ 8 (
                    echo       ATTENTION : probleme lors de la fusion locale de "%CATALOG% Helper.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%BASE%\%CATALOG% Helper.lrdata"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Sync.lrdata.7z" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%BASE%\%CATALOG% Sync.lrdata"
) else (
    robocopy "%SYNCED%" "%STAGING%" "%CATALOG% Sync.lrdata.7z" /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de l'archive "%CATALOG% Sync.lrdata.7z" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Sync.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Sync.lrdata" - version locale inchangee
            set "HAD_ERROR=1"
        ) else (
            if exist "%STAGING%\extracted\" rd /S /Q "%STAGING%\extracted" 2>NUL
            mkdir "%STAGING%\extracted" 2>NUL
            "%ZIP7%" x "%STAGING%\%CATALOG% Sync.lrdata.7z" -o"%STAGING%\extracted" -y >NUL 2>&1
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 1 (
                echo       ATTENTION : echec d'extraction pour "%CATALOG% Sync.lrdata"
                set "HAD_ERROR=1"
            ) else (
                robocopy "%STAGING%\extracted" "%BASE%\%CATALOG% Sync.lrdata" /E /XO /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
                set "RC=!ERRORLEVEL!"
                if !RC! GEQ 8 (
                    echo       ATTENTION : probleme lors de la fusion locale de "%CATALOG% Sync.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%BASE%\%CATALOG% Sync.lrdata"
                )
            )
        )
    )
)

echo %DATE% %TIME% - PULL termine. >> "%LOG%"
echo.
echo       Recuperation terminee.
echo.

if "!HAD_ERROR!"=="1" (
    echo   ================================================================
    echo     ATTENTION : au moins un probleme est survenu pendant la
    echo     recuperation ^(voir les lignes ATTENTION ci-dessus^). Si tu
    echo     continues, Lightroom va ouvrir ta version LOCALE actuelle,
    echo     qui n'est peut-etre pas la plus recente venant de l'autre PC.
    echo   ================================================================
    echo.
    echo   Appuie sur une touche pour continuer quand meme, ou ferme
    echo   cette fenetre pour t'arreter ici et investiguer d'abord.
    pause >NUL
    echo.
)

REM --- Etape 3/4 : Lancement de Lightroom ---
echo [3/4] Lancement de Lightroom...
echo       Travaille normalement. Cette fenetre attend en arriere-plan
echo       et reprendra automatiquement quand tu fermeras Lightroom.
echo.
start "" /WAIT "%LIGHTROOM_EXE%"
echo       OK - Lightroom est ferme.
echo.
echo       Pause de securite ^(8 secondes^) pour laisser Lightroom terminer
echo       d'eventuelles ecritures en arriere-plan ^(apercus, cache IA...^)
echo       avant de commencer la copie.
ping -n 9 127.0.0.1 >NUL
echo.

REM --- Etape 4/4 : PUSH ---
echo [4/4] Sauvegarde de tes modifications vers _SyncedCopy
echo       ^(pour que ton outil de sync les remonte vers l'autre PC^)
echo.
echo       Compression et copie en cours, merci de patienter...
echo.

if not exist "%BASE%\%CATALOG%.lrcat" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%CATALOG%.lrcat"
) else (
    robocopy "%BASE%" "%SYNCED%" "%CATALOG%.lrcat" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
    set "RC=!ERRORLEVEL!"
    set "SRC_COUNT=1"
    set "DST_COUNT=0"
    if exist "%SYNCED%\%CATALOG%.lrcat" set "DST_COUNT=1"
    if !RC! GEQ 8 (
        echo       ATTENTION : probleme lors de la copie de "%CATALOG%.lrcat" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else if not "!SRC_COUNT!"=="!DST_COUNT!" (
        echo       ATTENTION : "%CATALOG%.lrcat" absent de la destination apres copie
        set "HAD_ERROR=1"
    ) else (
        echo       OK - "%CATALOG%.lrcat"
    )
)

if not exist "%BASE%\%CATALOG%.lrcat-data\" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%SYNCED%\%CATALOG%.lrcat-data.7z"
) else (
    if exist "%STAGING%\%CATALOG%.lrcat-data.7z" del /Q "%STAGING%\%CATALOG%.lrcat-data.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG%.lrcat-data.7z" "%BASE%\%CATALOG%.lrcat-data\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de la compression de "%BASE%\%CATALOG%.lrcat-data" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG%.lrcat-data.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive fraichement creee corrompue pour "%CATALOG%.lrcat-data" - push annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG%.lrcat-data.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de l'archive "%CATALOG%.lrcat-data.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%SYNCED%\%CATALOG%.lrcat-data.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Previews.lrdata\" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%SYNCED%\%CATALOG% Previews.lrdata.7z"
) else (
    if exist "%STAGING%\%CATALOG% Previews.lrdata.7z" del /Q "%STAGING%\%CATALOG% Previews.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Previews.lrdata.7z" "%BASE%\%CATALOG% Previews.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de la compression de "%BASE%\%CATALOG% Previews.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Previews.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive fraichement creee corrompue pour "%CATALOG% Previews.lrdata" - push annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Previews.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de l'archive "%CATALOG% Previews.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%SYNCED%\%CATALOG% Previews.lrdata.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Helper.lrdata\" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%SYNCED%\%CATALOG% Helper.lrdata.7z"
) else (
    if exist "%STAGING%\%CATALOG% Helper.lrdata.7z" del /Q "%STAGING%\%CATALOG% Helper.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Helper.lrdata.7z" "%BASE%\%CATALOG% Helper.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de la compression de "%BASE%\%CATALOG% Helper.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Helper.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive fraichement creee corrompue pour "%CATALOG% Helper.lrdata" - push annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Helper.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de l'archive "%CATALOG% Helper.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%SYNCED%\%CATALOG% Helper.lrdata.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Sync.lrdata\" (
    echo       ^(pas trouve a la source, saute - rien a copier^) "%SYNCED%\%CATALOG% Sync.lrdata.7z"
) else (
    if exist "%STAGING%\%CATALOG% Sync.lrdata.7z" del /Q "%STAGING%\%CATALOG% Sync.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Sync.lrdata.7z" "%BASE%\%CATALOG% Sync.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de la compression de "%BASE%\%CATALOG% Sync.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Sync.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive fraichement creee corrompue pour "%CATALOG% Sync.lrdata" - push annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Sync.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de l'archive "%CATALOG% Sync.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%SYNCED%\%CATALOG% Sync.lrdata.7z"
            )
        )
    )
)

echo %DATE% %TIME% - PUSH termine. >> "%LOG%"

REM --- Nettoyage du dossier de travail temporaire ---
if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL

echo.
if "!HAD_ERROR!"=="1" (
    echo ================================================================
    echo   TERMINE AVEC DES PROBLEMES - NE PAS SUPPOSER QUE TOUT EST A JOUR
    echo ================================================================
    echo.
    echo   Au moins un probleme est survenu pendant ce cycle ^(remonte
    echo   les lignes ATTENTION ci-dessus pour voir lesquels^). Certaines
    echo   de tes modifications n'ont peut-etre pas ete envoyees vers
    echo   _SyncedCopy correctement.
    echo.
    echo   NE PASSE PAS sur l'autre PC avant d'avoir compris et resolu
    echo   le ou les problemes signales.
) else (
    echo ================================================================
    echo   TOUT EST TERMINE
    echo ================================================================
    echo.
    echo   Tes modifications ont ete envoyees vers _SyncedCopy sous forme
    echo   d'archives .7z. Ton outil de sync va maintenant les remonter
    echo   vers le cloud/NAS, puis redescendre vers l'autre PC ^(nettement
    echo   plus rapide qu'avant : quelques gros fichiers au lieu de
    echo   milliers de petits^).
    echo.
    echo   AVANT D'OUVRIR LIGHTROOM SUR L'AUTRE PC :
    echo   - Verifie que ton outil de sync y indique "a jour"
    echo   - Lance ce meme script sur cette autre machine ^(il fera le
    echo     pull automatiquement avant d'ouvrir Lightroom^)
    echo.
    echo   Tu peux fermer cette fenetre.
)
echo ================================================================
pause
exit /b 0
