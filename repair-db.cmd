@echo off
REM Checks and repairs the Turtle WoW character database.
REM Run from the same folder as docker-compose.yml and .env.
REM The database container must be running.
REM mangosd and realmd will be stopped before database maintenance.

setlocal

echo ==============================
echo   Repair Turtle WoW Database
echo ==============================
echo.

REM Read the database root password from .env
set DBPASS=
for /f "tokens=1,* delims==" %%A in ('findstr /b "DB_ROOT_PASSWORD=" .env 2^>nul') do set DBPASS=%%B

if not defined DBPASS (
    echo ERROR: DB_ROOT_PASSWORD was not found in .env.
    goto :end
)

set /p CHECKCONFIRM=Stop the game services and check the character database? (Y/N):
if /i not "%CHECKCONFIRM%"=="Y" (
    echo Cancelled.
    goto :end
)

echo.
echo Stopping mangosd and realmd...
docker compose stop mangosd realmd

if errorlevel 1 (
    echo.
    echo ERROR: Could not stop the game services.
    goto :end
)

echo.
echo Checking tw_char and automatically repairing damaged tables...
docker compose exec -T db mariadb-check -uroot -p%DBPASS% --check --auto-repair tw_char

if errorlevel 1 (
    echo.
    echo ERROR: The database check or repair failed.
    echo mangosd and realmd have been left stopped.
    goto :end
)

echo.
echo Verifying tw_char after repair...
docker compose exec -T db mariadb-check -uroot -p%DBPASS% --check tw_char

if errorlevel 1 (
    echo.
    echo ERROR: Verification failed.
    echo Review the results above before restarting the server.
    echo mangosd and realmd have been left stopped.
    goto :end
)

echo.
echo Database verification completed successfully.
echo.

set /p RESTARTCONFIRM=Start realmd and mangosd now? (Y/N):
if /i "%RESTARTCONFIRM%"=="Y" (
    docker compose up -d realmd mangosd

    if errorlevel 1 (
        echo.
        echo ERROR: The services could not be started.
        goto :end
    )

    echo.
    echo Services started.
    echo Wait for "World server is up and running!" before logging in.
) else (
    echo.
    echo Services remain stopped.
    echo Start them later with:
    echo docker compose up -d realmd mangosd
)

:end
echo.
pause
endlocal
