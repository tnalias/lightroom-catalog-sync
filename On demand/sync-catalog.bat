@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  sync-catalog.bat - synchronisation A LA DEMANDE
REM
REM  Variante de start-lightroom.bat pour ceux qui travaillent a
REM  90%% sur une seule machine : au quotidien, lance Lightroom
REM  normalement (sans script). Lance CE script uniquement quand
REM  tu changes de machine :
REM    - Sur le PC ou tu viens de travailler : choix [1] ENVOYER
REM    - Sur le PC ou tu vas travailler      : choix [2] RECUPERER
REM
REM  A CONFIGURER : CATALOG (obligatoire), LIGHTROOM inutile ici,
REM  ZIP7 si 7-Zip est installe ailleurs.
REM
REM  STRUCTURE ATTENDUE (identique a start-lightroom.bat) :
REM    PARENT\_NoSync_WorkingFiles\  <- fichiers vivants, JAMAIS synchronises
REM    PARENT\_SyncedCopy\           <- relais, SEUL dossier synchronise
REM
REM  PROTECTION ANTI-DIVERGENCE (le vrai danger du mode manuel) :
REM  un fichier temoin (last-sync-state.txt) dans _SyncedCopy
REM  memorise quelle machine a envoye la derniere version, et
REM  chaque PC garde la trace de la derniere version qu'il a
REM  recuperee. Si tu tentes d'ENVOYER alors que la version du
REM  relais vient de l'autre PC et n'a jamais ete recuperee ici,
REM  le script bloque et t'explique : envoyer ecraserait du
REM  travail fait sur l'autre machine. Deux catalogues divergents
REM  sont IMPOSSIBLES a fusionner dans Lightroom - cette alerte
REM  est la pour eviter ce scenario, pire qu'une corruption.
REM
REM  Les fichiers d'etat ne sont ecrits que si l'operation s'est
REM  terminee SANS erreur : un envoi partiel ne sera jamais
REM  considere comme une version valide du relais.
REM
REM  IMPORTANT : fichier volontairement sans accents (ASCII pur)
REM  et sans sous-routines "call :label" (fragilite constatee en
REM  usage reel pendant les operations disque intenses). Seuls
REM  des "goto" simples servent au branchement du menu, avant
REM  toute activite disque.
REM ============================================================

set "PARENT=%~dp0"
set "BASE=%PARENT%_NoSync_WorkingFiles"
set "SYNCED=%PARENT%_SyncedCopy"
set "CATALOG=NomCatalogue"
set "ZIP7=C:\Program Files\7-Zip\7z.exe"
set "STAGING=%TEMP%\LightroomSyncStaging"
set "LOG=%PARENT%sync-backup.log"
set "BACKUPS_KEEP=2"
set "HAD_ERROR=0"
set "STATE_FILE=%SYNCED%\last-sync-state.txt"
set "LOCAL_STATE_FILE=%BASE%\_last-pull-state.txt"

cls
echo ================================================================
echo   SYNCHRONISATION DU CATALOGUE LIGHTROOM - %COMPUTERNAME%
echo ================================================================
echo.

REM --- Garde-fous ---
if not exist "%BASE%\%CATALOG%.lrcat" (
    echo   PROBLEME : impossible de trouver "%CATALOG%.lrcat" dans
    echo   %BASE%
    echo.
    echo   Ce script suppose que ton catalogue vit deja dans
    echo   _NoSync_WorkingFiles. Consulte le README pour la mise en
    echo   place initiale ^(identique a celle de start-lightroom.bat^).
    echo.
    pause
    exit /b 1
)
if not exist "%ZIP7%" (
    echo   PROBLEME : 7-Zip introuvable a l'emplacement configure :
    echo   %ZIP7%
    echo.
    echo   Installe 7-Zip ^(https://www.7-zip.org/^) ou corrige la
    echo   ligne ZIP7 en haut de ce script.
    echo.
    pause
    exit /b 1
)
if not exist "%SYNCED%\" (
    echo   Premier lancement detecte : creation du dossier _SyncedCopy.
    mkdir "%SYNCED%" 2>NUL
    echo   Pense a configurer ton outil de sync pour ne synchroniser
    echo   QUE ce dossier ^(voir README^).
    echo.
)
tasklist /FI "IMAGENAME eq Lightroom.exe" 2>NUL | find /I "Lightroom.exe" >NUL
if "%ERRORLEVEL%"=="0" (
    echo   PROBLEME : Lightroom est ouvert sur cette machine.
    echo   Ferme-le d'abord, puis relance ce script.
    echo.
    pause
    exit /b 1
)

REM --- Lecture de l'etat du relais et de la trace locale ---
set "REMOTE_STATE="
if exist "%STATE_FILE%" set /p REMOTE_STATE=<"%STATE_FILE%"
set "LOCAL_STATE="
if exist "%LOCAL_STATE_FILE%" set /p LOCAL_STATE=<"%LOCAL_STATE_FILE%"
set "REMOTE_MACHINE="
set "REMOTE_WHEN="
if not "!REMOTE_STATE!"=="" for /f "tokens=1,2 delims=|" %%A in ("!REMOTE_STATE!") do (
    set "REMOTE_MACHINE=%%A"
    set "REMOTE_WHEN=%%B"
)

REM --- Contexte affiche avant le choix ---
if "!REMOTE_STATE!"=="" (
    echo   Etat du relais : aucune version encore envoyee ^(premiere
    echo   utilisation de cette variante^).
) else (
    echo   Etat du relais : derniere version envoyee par [!REMOTE_MACHINE!]
    echo   le !REMOTE_WHEN!.
    if /I "!REMOTE_MACHINE!"=="%COMPUTERNAME%" (
        echo   ^(c'est CE PC qui a envoye la derniere version^)
    ) else (
        if "!LOCAL_STATE!"=="!REMOTE_STATE!" (
            echo   ^(cette version a deja ete recuperee sur ce PC^)
        ) else (
            echo   ^(cette version n'a PAS encore ete recuperee sur ce PC^)
        )
    )
)
echo.
echo ----------------------------------------------------------------
echo   Ou en es-tu ?
echo.
echo   [1] Je viens de TRAVAILLER sur CE PC
echo       -^> J'envoie mes modifications vers l'autre PC
echo.
echo   [2] Je vais MAINTENANT travailler sur CE PC
echo       -^> Je recupere d'abord les modifications de l'autre PC
echo.
echo   [3] Annuler ^(ne rien faire^)
echo ----------------------------------------------------------------
choice /C 123 /N /M "  Ton choix [1/2/3] : "
set "MENU=!ERRORLEVEL!"
echo.
if "!MENU!"=="3" exit /b 0
if "!MENU!"=="1" goto DO_PUSH
if "!MENU!"=="2" goto DO_PULL
exit /b 0

REM ================================================================
:DO_PUSH
REM ================================================================

REM --- Protection anti-divergence ---
if not "!REMOTE_STATE!"=="" if /I not "!REMOTE_MACHINE!"=="%COMPUTERNAME%" if not "!LOCAL_STATE!"=="!REMOTE_STATE!" (
    echo ================================================================
    echo   STOP : RISQUE DE PERTE DE TRAVAIL DETECTE
    echo ================================================================
    echo.
    echo   La version actuellement dans le relais a ete envoyee par
    echo   [!REMOTE_MACHINE!] le !REMOTE_WHEN!, et ce PC ne l'a JAMAIS
    echo   recuperee.
    echo.
    echo   Si tu envoies maintenant, tu vas ECRASER le travail fait
    echo   sur [!REMOTE_MACHINE!] par la version plus ancienne de ce
    echo   PC. Deux catalogues divergents ne peuvent PAS etre
    echo   fusionnes ensuite dans Lightroom.
    echo.
    echo   Sauf si tu es absolument certain que la version de ce PC
    echo   est celle a garder, choisis N, puis fais d'abord [2]
    echo   Recuperer ^(ou clarifie la situation avant^).
    echo.
    choice /C ON /N /M "  Continuer quand meme et ECRASER ? [O/N] : "
    if "!ERRORLEVEL!"=="2" (
        echo.
        echo   Operation annulee. Rien n'a ete modifie.
        pause
        exit /b 0
    )
    echo.
)

REM --- Recapitulatif et confirmation ---
echo ----------------------------------------------------------------
echo   RECAPITULATIF : cette machine [%COMPUTERNAME%] va ENVOYER sa
echo   version du catalogue vers le relais _SyncedCopy.
if not "!REMOTE_STATE!"=="" echo   La version actuelle du relais ^(de [!REMOTE_MACHINE!], le !REMOTE_WHEN!^) sera remplacee.
echo ----------------------------------------------------------------
echo   Appuie sur une touche pour lancer, ou ferme cette fenetre
echo   pour annuler.
pause >NUL
echo.
echo   Pause de securite ^(8 secondes^) pour laisser Lightroom
echo   terminer d'eventuelles ecritures en arriere-plan...
ping -n 9 127.0.0.1 >NUL
echo.
echo   Compression et envoi en cours, merci de patienter...
echo.

if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL
mkdir "%STAGING%" 2>NUL

robocopy "%BASE%" "%SYNCED%" "%CATALOG%.lrcat" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
set "RC=!ERRORLEVEL!"
if !RC! GEQ 8 (
    echo       ATTENTION : probleme lors de la copie de "%CATALOG%.lrcat" ^(code !RC!^)
    set "HAD_ERROR=1"
) else (
    if not exist "%SYNCED%\%CATALOG%.lrcat" (
        echo       ATTENTION : "%CATALOG%.lrcat" absent de la destination apres copie
        set "HAD_ERROR=1"
    ) else (
        echo       OK - "%CATALOG%.lrcat"
    )
)

if not exist "%BASE%\%CATALOG%.lrcat-data\" (
    echo       ^(pas trouve a la source, saute^) "%CATALOG%.lrcat-data"
) else (
    if exist "%STAGING%\%CATALOG%.lrcat-data.7z" del /Q "%STAGING%\%CATALOG%.lrcat-data.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG%.lrcat-data.7z" "%BASE%\%CATALOG%.lrcat-data\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de compression de "%CATALOG%.lrcat-data" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG%.lrcat-data.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG%.lrcat-data" - envoi annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG%.lrcat-data.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de "%CATALOG%.lrcat-data.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%CATALOG%.lrcat-data.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Previews.lrdata\" (
    echo       ^(pas trouve a la source, saute^) "%CATALOG% Previews.lrdata"
) else (
    if exist "%STAGING%\%CATALOG% Previews.lrdata.7z" del /Q "%STAGING%\%CATALOG% Previews.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Previews.lrdata.7z" "%BASE%\%CATALOG% Previews.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de compression de "%CATALOG% Previews.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Previews.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Previews.lrdata" - envoi annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Previews.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de "%CATALOG% Previews.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%CATALOG% Previews.lrdata.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Helper.lrdata\" (
    echo       ^(pas trouve a la source, saute^) "%CATALOG% Helper.lrdata"
) else (
    if exist "%STAGING%\%CATALOG% Helper.lrdata.7z" del /Q "%STAGING%\%CATALOG% Helper.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Helper.lrdata.7z" "%BASE%\%CATALOG% Helper.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de compression de "%CATALOG% Helper.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Helper.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Helper.lrdata" - envoi annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Helper.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de "%CATALOG% Helper.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%CATALOG% Helper.lrdata.7z"
            )
        )
    )
)

if not exist "%BASE%\%CATALOG% Sync.lrdata\" (
    echo       ^(pas trouve a la source, saute^) "%CATALOG% Sync.lrdata"
) else (
    if exist "%STAGING%\%CATALOG% Sync.lrdata.7z" del /Q "%STAGING%\%CATALOG% Sync.lrdata.7z" 2>NUL
    "%ZIP7%" a -t7z -mx0 -r "%STAGING%\%CATALOG% Sync.lrdata.7z" "%BASE%\%CATALOG% Sync.lrdata\*" >NUL 2>&1
    set "RC=!ERRORLEVEL!"
    if !RC! GEQ 1 (
        echo       ATTENTION : echec de compression de "%CATALOG% Sync.lrdata" ^(code !RC!^)
        set "HAD_ERROR=1"
    ) else (
        "%ZIP7%" t "%STAGING%\%CATALOG% Sync.lrdata.7z" >NUL 2>&1
        set "RC=!ERRORLEVEL!"
        if !RC! GEQ 1 (
            echo       ATTENTION : archive corrompue pour "%CATALOG% Sync.lrdata" - envoi annule pour ce dossier
            set "HAD_ERROR=1"
        ) else (
            robocopy "%STAGING%" "%SYNCED%" "%CATALOG% Sync.lrdata.7z" /A-:SH /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
            set "RC=!ERRORLEVEL!"
            if !RC! GEQ 8 (
                echo       ATTENTION : probleme lors de l'envoi de "%CATALOG% Sync.lrdata.7z" ^(code !RC!^)
                set "HAD_ERROR=1"
            ) else (
                echo       OK - "%CATALOG% Sync.lrdata.7z"
            )
        )
    )
)

echo %DATE% %TIME% - ENVOI manuel termine ^(HAD_ERROR=!HAD_ERROR!^). >> "%LOG%"

REM --- Ecriture des fichiers d'etat, UNIQUEMENT si tout s'est bien passe ---
if "!HAD_ERROR!"=="0" (
    set "TS="
    for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH:mm:ss" 2^>NUL') do set "TS=%%T"
    if "!TS!"=="" set "TS=heure-inconnue"
    set "NEW_STATE=%COMPUTERNAME%|!TS!"
    (echo !NEW_STATE!)>"%STATE_FILE%"
    (echo !NEW_STATE!)>"%LOCAL_STATE_FILE%"
)

if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL
echo.
if "!HAD_ERROR!"=="1" (
    echo ================================================================
    echo   ENVOI TERMINE AVEC DES PROBLEMES
    echo ================================================================
    echo.
    echo   Au moins un probleme est survenu ^(voir les lignes ATTENTION
    echo   ci-dessus^). Le relais n'a PAS ete marque comme a jour :
    echo   corrige le probleme et relance l'envoi avant de recuperer
    echo   quoi que ce soit sur l'autre PC.
) else (
    echo ================================================================
    echo   ENVOI TERMINE
    echo ================================================================
    echo.
    echo   Ta version a ete envoyee vers _SyncedCopy. Ton outil de sync
    echo   va maintenant la propager.
    echo.
    echo   SUR L'AUTRE PC, quand tu voudras travailler :
    echo   1. Verifie que l'outil de sync y indique "a jour"
    echo   2. Lance ce meme script et choisis [2] Recuperer
    echo   3. Ouvre ensuite Lightroom normalement
)
echo ================================================================
pause
exit /b 0

REM ================================================================
:DO_PULL
REM ================================================================

REM --- Information si la version du relais vient de ce PC ---
if not "!REMOTE_STATE!"=="" if /I "!REMOTE_MACHINE!"=="%COMPUTERNAME%" (
    echo ----------------------------------------------------------------
    echo   INFO : la derniere version du relais a ete envoyee par CE PC
    echo   ^(le !REMOTE_WHEN!^). Il n'y a probablement rien de nouveau a
    echo   recuperer. C'est sans danger de continuer ^(la recuperation
    echo   ne supprime jamais rien^), mais si tu t'attendais a recuperer
    echo   du travail fait sur l'autre PC, celui-ci n'a pas encore ete
    echo   envoye : va d'abord faire [1] Envoyer la-bas.
    echo ----------------------------------------------------------------
    choice /C ON /N /M "  Continuer la recuperation quand meme ? [O/N] : "
    if "!ERRORLEVEL!"=="2" (
        echo.
        echo   Operation annulee. Rien n'a ete modifie.
        pause
        exit /b 0
    )
    echo.
)

REM --- Recapitulatif et confirmation ---
echo ----------------------------------------------------------------
echo   RECAPITULATIF : cette machine [%COMPUTERNAME%] va RECUPERER la
echo   version du relais _SyncedCopy vers son dossier de travail.
if not "!REMOTE_STATE!"=="" echo   Version du relais : envoyee par [!REMOTE_MACHINE!] le !REMOTE_WHEN!.
echo   Ta version locale ne sera jamais supprimee, et une sauvegarde
echo   de securite est faite avant toute modification.
echo ----------------------------------------------------------------
echo   AVANT DE CONTINUER : verifie que ton outil de sync indique
echo   "a jour" ^(pas de synchronisation en cours^).
echo.
echo   Appuie sur une touche pour lancer, ou ferme cette fenetre
echo   pour annuler.
pause >NUL
echo.
echo   Recuperation en cours, merci de patienter...
echo.

if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL
mkdir "%STAGING%" 2>NUL

REM --- Sauvegarde de securite avant toute modification ---
if not exist "%BASE%\_CrashBackups\" mkdir "%BASE%\_CrashBackups" 2>NUL
set "TS="
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>NUL') do set "TS=%%T"
if "!TS!"=="" (
    echo       ATTENTION : horodatage impossible - sauvegarde de securite sautee
    set "HAD_ERROR=1"
) else (
    copy /Y "%BASE%\%CATALOG%.lrcat" "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat" >NUL 2>&1
    if not exist "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat" (
        echo       ATTENTION : la sauvegarde de securite a echoue ^(disque plein ? permissions ?^)
        set "HAD_ERROR=1"
    )
    if exist "%BASE%\%CATALOG%.lrcat-data\" robocopy "%BASE%\%CATALOG%.lrcat-data" "%BASE%\_CrashBackups\%CATALOG%_!TS!.lrcat-data" /E /R:1 /W:2 /NFL /NDL /NJH /NJS >NUL
)
for /f "skip=%BACKUPS_KEEP% delims=" %%F in ('dir /b /o-d "%BASE%\_CrashBackups\%CATALOG%_*.lrcat" 2^>NUL') do del /Q "%BASE%\_CrashBackups\%%F" 2>NUL
for /f "skip=%BACKUPS_KEEP% delims=" %%F in ('dir /b /ad /o-d "%BASE%\_CrashBackups\%CATALOG%_*.lrcat-data" 2^>NUL') do rd /S /Q "%BASE%\_CrashBackups\%%F" 2>NUL

if not exist "%SYNCED%\%CATALOG%.lrcat" (
    echo       ^(pas trouve dans le relais, saute^) "%CATALOG%.lrcat"
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
    echo       ^(pas trouve dans le relais, saute^) "%CATALOG%.lrcat-data"
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
                    echo       ATTENTION : probleme lors de la fusion de "%CATALOG%.lrcat-data" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%CATALOG%.lrcat-data"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Previews.lrdata.7z" (
    echo       ^(pas trouve dans le relais, saute^) "%CATALOG% Previews.lrdata"
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
                    echo       ATTENTION : probleme lors de la fusion de "%CATALOG% Previews.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%CATALOG% Previews.lrdata"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Helper.lrdata.7z" (
    echo       ^(pas trouve dans le relais, saute^) "%CATALOG% Helper.lrdata"
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
                    echo       ATTENTION : probleme lors de la fusion de "%CATALOG% Helper.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%CATALOG% Helper.lrdata"
                )
            )
        )
    )
)

if not exist "%SYNCED%\%CATALOG% Sync.lrdata.7z" (
    echo       ^(pas trouve dans le relais, saute^) "%CATALOG% Sync.lrdata"
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
                    echo       ATTENTION : probleme lors de la fusion de "%CATALOG% Sync.lrdata" ^(code !RC!^)
                    set "HAD_ERROR=1"
                ) else (
                    echo       OK - "%CATALOG% Sync.lrdata"
                )
            )
        )
    )
)

echo %DATE% %TIME% - RECUPERATION manuelle terminee ^(HAD_ERROR=!HAD_ERROR!^). >> "%LOG%"

REM --- Trace locale : cette machine connait desormais la version du relais ---
if "!HAD_ERROR!"=="0" if not "!REMOTE_STATE!"=="" (echo !REMOTE_STATE!)>"%LOCAL_STATE_FILE%"

if exist "%STAGING%\" rd /S /Q "%STAGING%" 2>NUL
echo.
if "!HAD_ERROR!"=="1" (
    echo ================================================================
    echo   RECUPERATION TERMINEE AVEC DES PROBLEMES
    echo ================================================================
    echo.
    echo   Au moins un probleme est survenu ^(voir les lignes ATTENTION
    echo   ci-dessus^). Ta version locale n'a rien perdu ^(la
    echo   recuperation ne supprime jamais rien^), mais elle n'est
    echo   peut-etre pas complete : n'ouvre pas Lightroom avant d'avoir
    echo   compris le probleme, puis relance la recuperation.
) else (
    echo ================================================================
    echo   RECUPERATION TERMINEE
    echo ================================================================
    echo.
    echo   Ta machine est a jour. Tu peux ouvrir Lightroom normalement
    echo   et travailler.
    echo.
    echo   Quand tu auras fini de travailler sur ce PC et voudras
    echo   repasser sur l'autre : relance ce script et choisis [1]
    echo   Envoyer.
)
echo ================================================================
pause
exit /b 0
