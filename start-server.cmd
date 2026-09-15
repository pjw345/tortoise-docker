@echo off
REM Interactive start for the tortoise-wow server (db, realmd, mangosd).
REM Run this from the same folder as your docker-compose.yml.

setlocal

echo ============================
echo   Start Turtle WoW Server
echo ============================
echo.

docker compose ps

echo.
set /p CONFIRM=Start/restart the stack now? (Y/N):
if /i not "%CONFIRM%"=="Y" (
    echo Cancelled.
    goto :end
)

echo.
echo Starting tortoise-wow server...
docker compose up -d

if errorlevel 1 (
    echo.
    echo ERROR: Docker Compose could not start the server.
    goto :end
)

echo.
echo Containers are starting.
echo This can take several minutes while bot caches and travel data load.
echo.
echo The filtered log will show:
echo   - World server ready
echo   - Server restart or shutdown messages
echo   - Crashes, fatal errors and out-of-memory errors
echo.
echo The window may remain blank while the server is loading.
echo Press Ctrl+C to stop watching. This will not stop the containers.
echo.

set /p WATCH=Watch filtered live logs now? (Y/N):
if /i "%WATCH%"=="Y" (
    powershell -NoProfile -Command "docker compose logs -f --tail=500 mangosd 2>&1 | Select-String -Pattern 'World server is up and running|DB AutoUpdater FAILED|Migration .* failed|Unknown column|doesn.t exist|database structure|Assertion|Segmentation fault|unexpected EOF|bad_alloc|out of memory|OOM|OOMKilled|Killed|fatal|crash|terminate called|exited with code|Restart in|restart the Server|Shutting down|shutdown'"
) else (
    docker compose ps
)

:end
echo.
pause
endlocal
